# BOMBA — NETPLAN.md

The netcode design. Written before any netcode was implemented (2026-09-18) and kept current as the
implementation changes. `DESIGN.md` §3 states the rules; this file says how they are met with
Godot 4.7 + netfox 1.35.3, and where netfox is not enough and code is written by hand.

Provenance tags as in `STYLE.md`: `[netfox]` is how the addon actually works (read from its source),
`[ours]` is what we build on top, `[decision]` is an assumption logged in `DECISIONS.md`.

---

## 1. The question this spike answers

Does a one-shot quickscoping sniper and a no-spread AR feel tight at 120 ms round trip with 30 ms
jitter and 3 % loss (the `bad` conditioner profile)? Everything else in the project waits on that.
The spike is judged by a human on the build plus the numbers in §11. The agent never scores feel.

## 2. The model

`[netfox]` netfox is server-authoritative rollback: clients send **inputs**, the server simulates
and broadcasts **state**, and every peer keeps a per-tick history of both so it can rewind and
resimulate. The unit of simulation is `_rollback_tick(delta, tick, is_fresh)` on any node under a
`RollbackSynchronizer`. Ownership follows Godot's multiplayer authority:

| Node | Authority | Why |
|---|---|---|
| Player body (`CharacterBody3D`) and everything holding state | 1 (server) | Server decides position, health, ammo, score |
| Player `Input` node | that player's peer id | Only the player produces their input |
| Bot `Input` node | 1 (server) | Bots are server-driven players, no peer |

`[netfox]` A peer simulates a node in a rollback tick only when it has input for that tick, or the
node was *mutated* during the tick (`NetworkRollback.mutate()`), or prediction is enabled. So on a
client the **local body is predicted** from local input, **remote bodies are never simulated** (they
are pure state playback), and the **server simulates everybody** from the earliest new input.

`[decision]` Prediction of remote players (`enable_prediction`) is **off**. Input broadcast
(`enable_input_broadcast`) is **off**: inputs go to the server only. Both are bandwidth and
cheat-surface decisions and both match how a shooter should work.

## 3. Time

| | Value | Source |
|---|---|---|
| Simulation tick | 60 Hz (`netfox/time/tickrate = 60`) | `DESIGN.md` §3 |
| Godot physics tick | 60 Hz | so `NetworkTime.physics_factor` is 1.0 |
| State transmit rate | every tick, diff-encoded | `[netfox]` limitation, see §12 |
| Render rate | uncapped, decoupled | tick loop runs inside `_physics_process` (`sync_to_physics`), accumulator-driven |
| Rollback history | 90 ticks (1.5 s) | covers 250 ms RTT + 80 ms jitter + 250 ms rewind with margin |
| Input redundancy | 4 | 1 − 0.08⁴ ≈ 99.996 % of ticks arrive at 8 % loss |
| Input delay | 0 ticks | local response must be immediate |
| Display offset | 0 ticks | same reason |

`[netfox]` The tick loop is bound to the physics step (`netfox/time/sync_to_physics = true`) so
`physics_factor` is exactly 1.0 and every tick's `move_and_slide()` uses the same delta; run
from `_process` the factor is `ticktime / frame_delta` and 60 fps and 240 fps trajectories
differ in the last bits. The physics step itself is never used for simulation beyond that.

`[netfox]` `NetworkTime` keeps a stretched simulation clock synced to the host by an NTP-like loop.
Clients start ticking only after the initial sync. `NetworkEvents` starts and stops the loop when a
server or client starts and stops, so nothing calls `NetworkTime.start()` by hand except the
offline harnesses.

**Frame-rate independence** `[ours]` — the only things that touch the simulation are
`_rollback_tick` handlers and the input recorded per tick. Nothing in `_process` writes
simulation state. `tools/determinism.sh` runs the arena offline with a seeded per-tick input log
(`tools/soak/scripted_input.gd`, fed through `NetworkTime.before_tick`) at `--fixed-fps 60` and
`--fixed-fps 240` and diffs the per-tick trajectory of every player. Any difference fails the run.

## 4. What is state, what is input

Per player scene (`fps/player/player.tscn`):

**Input properties** (owned by the player, sent to the server, never broadcast):

| Property | Type | Notes |
|---|---|---|
| `Input:move` | Vector2 | wish direction in body space, sampled and averaged per frame |
| `Input:yaw`, `Input:pitch` | float | **absolute** look angles, not deltas, so packet loss cannot drift the aim |
| `Input:jump` | bool | one-off, buffered so a press between ticks is never lost |
| `Input:fire` | bool | held for auto weapons; one-off buffered for the sniper |
| `Input:ads` | bool | held |
| `Input:weapon` | int | requested slot |
| `Input:reload` | bool | one-off |
| `Input:view_tick` | float | the tick (fractional) at which this client was *rendering remote players* when the input was gathered. Used for hitbox rewind, §6 |

**State properties** (owned by the server, broadcast to all):

| Property | Notes |
|---|---|
| `:transform` | body position and yaw |
| `:velocity` | needed so acceleration survives a rewind |
| `:head_pitch` | pitch (netfox cannot address a child's nested field) |
| `:health`, `:kills`, `:deaths` | |
| `:protected_until_tick` | spawn protection |
| `:respawn_count` | lets clients detect a respawn and `teleport()` the interpolators |
| `Move:jump_buffer`, `Move:coyote`, `Move:on_floor` | movement bookkeeping ints/bools that must rewind |
| `Weapons:slot`, `Weapons:swap_until_tick` | |
| `Weapons:sniper_ammo`, `Weapons:sniper_next_fire_tick`, `Weapons:sniper_reload_until_tick`, `Weapons:ads_since_tick` | |
| `Weapons:ar_ammo`, `Weapons:ar_next_fire_tick`, `Weapons:ar_reload_until_tick`, `Weapons:ar_recoil_index`, `Weapons:ar_last_shot_tick`, `Weapons:recoil_pitch`, `Weapons:recoil_yaw` | |

Interpolated for display: `:transform` (local player via `TickInterpolator`; remote players via
the smoother in §7). Pitch is read raw from the mouse for the local camera.

## 5. Movement in rollback

`[ours]` `fps/player/movement_model.gd` is a plain class. `compute(velocity, on_floor, wish_dir,
jump, dt, cfg)` returns the new velocity and updated jump-buffer/coyote counters. It has no node
dependencies and is unit-tested. The body node calls it in `_rollback_tick`, then does the netfox
dance around `move_and_slide()`:

```
_force_update_is_on_floor()          # zero-velocity move so is_on_floor() is valid after a rewind
velocity = MovementModel.compute(...)
velocity *= NetworkTime.physics_factor
move_and_slide()
velocity /= NetworkTime.physics_factor
```

`[netfox]` `move_and_slide()` queries the physics space directly, so it is deterministic for
static geometry regardless of when the physics server last stepped. That is why the map is
`StaticBody3D` only and why nothing dynamic participates in rollback (`DESIGN.md` §2).

Halo 3 feel (all in `tuning/movement.json`): 5.8 m/s, no sprint, gravity 12.5, jump velocity
6.1 (1.49 m apex, 0.98 s air time), gradual ground acceleration, weak air control.

## 6. Shooting

### 6.1 Firing is predicted

`[netfox]` Each weapon fire is a `RewindableAction`. In `_rollback_tick`, every peer that
simulates the shooter (the shooter's client and the server) calls `set_active(fire and can_fire)`.
The client's action goes `CONFIRMING` immediately, so the shot resolves locally on the same tick
it was pressed. The server's own history is ground truth; if it disagrees, the client's action goes
`CANCELLING` on the next state.

`[ours]` After each tick loop, `has_confirmed()` drives **immediate local feedback**: muzzle flash,
tracer, impact decal, hitmarker, bolt animation, recoil kick. **Nothing is ever undone on
`CANCELLING`** except internal bookkeeping (`erase_context()`): a shot the server rejects simply
does no damage. This is the "never visually retract a hit" rule.

`[ours]` The action's `mutate(player)` is registered **on the server only**. On a client it would
re-record the client's prediction over authoritative states whenever the server disputes a
predicted shot; measured as a 130-tick outage after deaths (`DECISIONS.md`, 2026-09-18). The
client's own player is simulated every tick anyway, and disputed past ticks take the server's
answer through the action's queued changes.

### 6.2 Hit registration with hitbox rewind (written by hand)

netfox provides no lag compensation. The rollback-fps example raycasts against other players at
their *rollback-restored* positions for the shot tick, which on the server means positions the
shooter never saw. We do this instead:

1. `[ours]` Every player writes its **hitboxes** (head sphere, body capsule, both in world space)
   into a `HitboxHistory` ring buffer from inside `_rollback_tick`, keyed by the *state* tick
   (simulating tick T produces state T+1, netfox's convention). Resimulating a tick overwrites
   that entry, so the history stays consistent with netfox's own state history. On clients the
   history of remote players is filled from received state after each tick loop, keyed by
   `get_last_known_state()`, which is also a state tick.
2. The client renders remote players ~100 ms behind (§7). The tick it is rendering,
   `view_tick`, is sent as an input property with the fire.
3. When a shot resolves at tick T, the resolver samples every other player's history at
   `clamp(view_tick, T − lag_comp_max_ticks, T)` (250 ms → 15 ticks), interpolating between the
   two bracketing ticks, and tests the ray against those **analytic** shapes
   (`net/hitscan_math.gd`: ray–sphere, ray–capsule). The world is tested with one physics raycast
   on the `world` layer only. Nearest hit wins.
4. The same code runs on the shooter's client (with its own copy of the histories) and on the
   server. They agree except when the client's history has a gap from loss, which the interpolation
   papers over.

Nothing rewinds physics bodies. Nothing depends on the physics server's state for hits, so the
resolve is cheap enough to run several times per frame during resimulation.

### 6.3 Damage, health, death

`[ours]` `victim.take_damage(amount, shooter, tick)` subtracts health. On the server it also calls
`NetworkRollback.mutate(victim)`: `[netfox]` mutation makes the victim's synchronizer record the
change and resimulate the victim from that tick, so a hit whose input arrived late still sticks
and the death is detected. On the shooter's client the hit is **not** mutated: the local
`take_damage` return value is enough for an immediate hitmarker, and mutating a pure-playback
node would make netfox record its stale state under the current tick and shadow every newer
received state (measured: the victim froze on screen while being hit).

Death is resolved **only by the authority**: in the victim's `_rollback_tick`, `if
is_multiplayer_authority() and health <= 0` → `deaths += 1`, killer `kills += 1`, pick a spawn,
teleport, restore health, set `protected_until_tick`. Clients never predict a death or a respawn;
the victim learns of their death when the state arrives. That is the side of the inconsistency
players tolerate (`DESIGN.md` §3).

A remote player node on a client runs `_rollback_tick` only when mutated. It must not move on
such a tick: the body checks `_is_remote_on_client()` and returns after bookkeeping, so a predicted
hit never makes the victim visibly drift.

Kill feed: the server broadcasts kills from `after_tick_loop`, deduplicated by (victim,
death tick). A death can only be undone if the resimulation of an *old* tick changes a shot, which
the rewind rules make practically impossible; if it happens, the feed is wrong and the score is
right, and it is logged.

### 6.4 The sniper

Bolt action, one shot to head or body. `ads_since_tick` is state. `SCOPE_IN_TICKS`
(`tuning/weapons.json: sniper.scope_in_ticks`, 16 = 267 ms) is read by **both** the server's
accuracy rule (`tick − ads_since_tick >= scope_in_ticks` → zero spread, else hipfire cone) and the
viewmodel's scope-in tween duration. There is one number and the animation is authored to it.
Hipfire spread is a deterministic offset from `Rng.tick_stream("sniper_hip", tick, peer)`, so the
client's predicted hit and the server's resolve pick the same offset.

### 6.5 The AR

Full auto hitscan, zero spread. Recoil is a fixed pattern (`recoil_pattern_deg`) indexed by
`ar_recoil_index`, which increments per shot and resets after `recoil_reset_ticks` without firing.
The accumulated `recoil_pitch`/`recoil_yaw` are state, decay per tick, and offset the shot
direction *and* the camera, so what the player sees is what the server resolves. Damage falls off
linearly between `falloff_start_m` and `falloff_end_m`.

## 7. Presentation

**Local player** `[netfox]` `TickInterpolator` on `:transform`. Mouse look is
applied to the camera every frame from the raw accumulator; the tick merely samples it. Corrections
from the server are applied silently by rollback; the visual only "snaps" when the correction is
larger than `net.local_correction_snap_m`, and that event is counted (§11).

**Remote players** `[ours]` `net/snapshot_buffer.gd` per remote player: samples of
(tick, transform, pitch) pushed after each tick loop, rendered at `render_tick`, which tracks
`latest_tick − interp_delay_ticks` (100 ms = 6 ticks) with a rate-adjusted clock (never a hard
jump unless the error exceeds 1 s). Between samples it interpolates; past the newest sample it
extrapolates from the last velocity for at most `remote_extrapolate_max_ticks` (2), then holds.
A jump larger than `remote_snap_distance_m` (respawn) snaps. The mesh a remote player shows is
driven by this buffer, not by the body node, which stays at the latest state for hit history.

## 8. What the server validates

Assume every client is lying. On the server:

- Inputs are the only thing accepted from a client. Position, damage, hits, kills and RNG are never
  read from a client message.
- `view_tick` is clamped to `[T − 15, T]`.
- `yaw`/`pitch` are wrapped/clamped; `move` is clamped to unit length.
- `fire` is honoured only if `can_fire` (cooldown, ammo, reload, swap, not dead) holds in the
  server's own state.
- Sniper accuracy requires `SCOPE_IN_TICKS` of ADS in the server's own state.
- Spawn protection is checked from the server's own `protected_until_tick`.
- Damage numbers come from tuning, loaded on the server.

## 9. Bandwidth estimate

Per player per tick the full state is roughly 150 bytes of Variant payload. At 60 Hz with six
players and five remote peers the host's worst-case upload is 60 × 6 × 150 × 5 ≈ 270 KB/s
(≈ 2.2 Mbit/s) before diff encoding. Diff states cut idle players to near zero; a moving player
still changes `transform` and `velocity` every tick. This is acceptable for a friends' listen
server and is measured in the soak (§11). If it is not, the fix is transmit decimation in a
netfox fork or a `StateSynchronizer` at 30 Hz for non-predicted fields, not a lower tick rate.

## 10. Transport, NAT, conditioner

`[ours]` `net/transport.gd` is the interface: `host(port)`, `join(address, port)`, `leave()`,
`get_peer() -> MultiplayerPeer`, `get_stats()`. `net/enet_transport.gd` implements it with
`ENetMultiplayerPeer`. `net/noray_transport.gd` (async `host_async` / `join_async`) does the
noray flow: register with the relay server, register the external UDP address, then for a
client try NAT punchthrough (UDP handshake on the registered port, 5 s) and fall back to the
relay (10 s); `ENetMultiplayerPeer.create_client` binds the registered local port. The host
answers each connect command with the ENet handshake blast. The friend code is the noray
OpenID, shown in the lobby with a copy button; the join field accepts a code or `ip:port`. The
conditioner cannot sit in this path (the local port is fixed). Steam sockets drop in as a third
implementation later.

**Conditioner** `[ours]` `net/conditioner.gd` is an in-process UDP proxy on its own thread:
the client connects to `127.0.0.1:<proxy>` and the proxy forwards to the real host, delaying,
jittering and dropping in both directions. Delay per direction is `rtt_ms / 2 ± jitter_ms / 2`;
loss is applied per direction. All decisions use a seeded `RandomNumberGenerator`, so a run with
the same seed drops the same packets. It works in exported builds, never touches the OS, and its
profiles live in `tuning/net.json`. The netfox `NetworkSimulator` is not used: editor-only,
unseeded, no jitter.

## 11. Testing and the numbers to report

Nothing is declared working until it has run at `bad`.

**Determinism harness** (`tools/determinism.sh`) — offline host with bots, every seat driven by
the seeded per-tick input log, run twice at `--fixed-fps 60` and `--fixed-fps 240`. Pass:
per-tick positions, health and scores identical to the byte.

**Soak harness** (`tools/soak.sh`, joined by `tools/soak_report.py`) — launches one host and N clients as
separate headless Godot processes on this machine, clients driven by bots (`--autoplay`), each
with a conditioner profile, for a fixed duration. Every instance writes
`reports/soak_<peer>.csv` (per-tick positions of every player, shots, predicted hits, confirmed
hits, rollback depth, RTT). The harness joins them and prints:

| Metric | Meaning |
|---|---|
| `mispredict_mean_m`, `mispredict_p95_m`, `snaps` | local prediction error at the same tick vs server truth |
| `hit_predicted`, `hit_confirmed`, `hit_confirm_rate` | shooter-side hits vs server-side hits at the same tick |
| `rollback_ticks_mean`, `rollback_ticks_max` | resimulation depth |
| `rtt_ms_mean`, `loss_observed` | what the conditioner actually did |
| `tick_loop_ms_p95` | cost of the tick + rollback loop |
| `bytes_up`, `bytes_down` per instance | bandwidth |

**Unit tests** (`tools/test_runner.gd`) — movement model, hitscan math, hitbox history
interpolation, weapon logic (cooldowns, ADS rule, recoil, falloff), seeded RNG reproducibility,
snapshot buffer, tuning load, and a compile-all pass over every `.gd` file.

## 12. Known limitations, honestly

- **Bandwidth.** First measured 2026-09-18 with 33 state properties per player at 60 Hz: host
  upload ≈ 77–90 KB/s per client with three seats, ≈ 190 KB/s per client with six. Two changes
  later that day: `:position` + `:yaw` replace `:transform`, and netfox patch #4 sends state at
  30 Hz (`netfox/rollback/state_send_interval = 2`), the snapshot rate §3 asked for. Result with
  three seats: 37 KB/s per client, diff encoding sending 21 of 162 candidate properties per loop,
  hit agreement unchanged. The hard ceiling to respect is a noray relay's 128 kB/s per relay
  (`NORAY_UDP_RELAY_MAX_INDIVIDUAL_TRAFFIC`, 100 ms slices): the public relay throws inside its
  UDP handler when exceeded and the process dies, which is how the first two relayed matches
  ended. Next cuts if six seats through a relay need them: pack the fifteen weapon integers,
  quantise position to centimetres, 20 Hz for non-predicted fields.
- **Intermittent post-death desync on clients.** In 4 of 10 forty-five second soaks a client that
  died kept its stale health and position for 0.5–2.2 s, then recovered with a 128-tick rollback.
  netfox patch #3 (empty-diff acknowledgements) removed the accompanying warnings; whether it also
  removed the outage is being measured by the death→client lag line in `tools/soak_report.py`.
- **Vendored netfox carries four local patches** (`addons/netfox/PATCHES.md`). Each is a
  candidate for upstream; until then a netfox upgrade must re-apply them.
- **noray relay latency.** Through the public relay (`tomfol.io`) two processes on one machine
  measured 344–378 ms RTT; that is the relay's location, not the code. NAT punchthrough (the
  normal path between two homes) could not be tested from one machine and falls back to the
  relay automatically.
- netfox transmits state every tick; there is no separate 20–30 Hz snapshot rate yet (§9).
- The host has zero latency to itself. Listen-server host advantage is inherent; a dedicated
  headless host (`--host --headless`) removes it and is supported by the same code.
- `is_fresh` is unreliable with input delay; we use no input delay so it is fine.
- Physics props (Jenga-style) are not part of this plan; they are server-simulated and
  client-interpolated with a `StateSynchronizer`, per `DESIGN.md` §2.
- noray flow is implemented but can only be verified against a live noray server.
