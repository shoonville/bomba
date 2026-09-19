# BOMBA — STATUS.md

Current state. Updated at the end of every session. Numbers, not adjectives.

## 2026-09-18 — session 1: foundation + netcode spike

The build order in `DESIGN.md` §7 says the netcode spike comes first. It is built, it runs at
every conditioner profile, and the numbers are below. The feel verdict is a human's (§8); the
checklist for it is at the end. Everything listed as working was run on this machine today; the
harness that produced each number is named.

### What exists

| Area | State |
|---|---|
| Project | Godot 4.7-stable, Jolt physics, netfox 1.35.3 vendored with 4 documented patches (`addons/netfox/PATCHES.md`) |
| Docs | `DESIGN.md`, `STYLE.md` (given), `NETPLAN.md`, `DECISIONS.md` (41 entries), `README.md`, this file |
| `tuning/` | movement, weapons, arena, net, bots, palette, controls — every gameplay number, JSON |
| `core/` | bootstrap + CLI, event bus, seeded RNG service, tuning loader with F5 reload, logging to file |
| `net/` | transport interface + ENet, seeded in-process conditioner (LAN/good/bad/awful), analytic hitscan math, hitbox history with rewind, jitter-buffered remote snapshot playback |
| `session/` | host/join, registry with bots, colour assignment, start/result RPCs, rematch |
| `fps/` | Halo-3-style movement (pure model + CharacterBody3D), sniper + AR weapon logic (pure), predicted firing, lag-compensated hits, spawn protection, respawn, camera rig, gray-box viewmodels, remote player visuals, tracers |
| `minigames/sdk` | manifest, player, result, base class, folder-scan registry |
| `minigames/arena` | 48×40 m gray-box built from a layout table, LOS-aware spawn selection, timed FFA, kill feed, results |
| `bots/` | waypoint-graph hunting, LOS acquisition, reaction delay, aim error, quickscope at range, AR bursts; also drives `--autoplay` seats |
| `art/` | two-band cel shader (shadow = hue shift), ink outline + value ceiling + dither post pass, marbled swirl, viewmodel depth-squash shader, palette from JSON |
| `ui/` | shaped HUD (health swash, kills/timer, ammo ticks, crosshair, hitmarker, drawn scope, kill feed), main menu/lobby on the swirl, results screen |
| `tools/` | unit test runner, determinism harness, soak harness + report joiner, per-shot and remote-view diff tools, screenshot flags |
| `audio/` | procedural synth, buses, event-driven SFX, menu loop |
| Not started | `board/` (planned in `BOARDPLAN.md`), `items/`, Steam transport, melee, Windows export preset |

### Numbers

Unit tests (`tools/test.sh`): 48 tests, 5394 assertions, 63 scripts compiled, 0 failures.

Determinism (`tools/determinism.sh`, seeded per-tick input log, 4 players, 600 ticks):
60 fps vs 60 fps vs 240 fps — 2400 (peer, tick) rows compared, **0 differ**. With GodotPhysics3D
two 60 fps runs differed by 0.09 mm in resting height; Jolt is bit-exact.

Network soaks (`tools/soak.sh`, host + 1 client + 1 bot, 45 s, every seat bot-driven; client
routed through the conditioner; final code):

| Profile | RTT measured | Client rollback mean / max (ticks) | Mispredict mean (excl. deaths) | Deaths → client lag (ticks) | Shots agree | Hit confirm |
|---|---|---|---|---|---|---|
| good (40 / 5 / 0.5 %) | 50.0 ms | 6.5 / 21 | 0.5 mm | — | 13 / 13 | 4 / 4 |
| good, 2nd run | 49.9 ms | 6.7 / 24 | 1.0 mm | 9 | 23 / 23 | 6 / 9 |
| bad (120 / 30 / 3 %) | 126.6 ms | 16.5 / 58 | 1.7 mm | 2, 6, 1 | 44 / 45 | 11 / 14 |
| awful (250 / 80 / 8 %) | 251.8 ms | 27.0 / 71 | 43 mm | — | 18 / 18 | 1 / 1 |

"Shots agree" = the client's predicted hit test and the server's authoritative one gave the same
victim and hit kind for the same tick (`tools/shot_diff.py`). "Hit confirm" = predicted hits the
server counted. Remote players as seen by the client vs host truth (`tools/remote_diff.py`):
mean error 7 cm at `bad`, 3–7 cm at `awful`; every sample above 30 cm is a respawn teleport.

Six seats (host + 3 clients through `bad` + 2 bots, 30 s): all three clients mispredict 1–6 mm,
hit confirm 18/23, 12/15, 9/10, no post-death outages; host tick loop 8.0 ms mean, 10.8 ms p95.

Round flow: two consecutive 8 s rounds, host + client, identical rankings on both peers each
time; results screen and rematch verified. The host logs ~30 "cached node not found" errors at
the transition: the client's last input packets for the removed minigame, in flight for one RTT.
Harmless, not yet silenced.

Bandwidth (the biggest open number): host upload ≈ 45–90 KB/s per client with three seats,
≈ 170 KB/s per client (≈ 500 KB/s total, 4 Mbit/s) with six. Client upload ≈ 24 KB/s. See
`NETPLAN.md` §12 for the plan to cut it.

Cost: host tick loop 2.4–2.8 ms mean with three seats; client tick loop p95 4 ms (good), 8 ms
(bad), 11 ms (awful), on an M4 in headless mode.

### Session 2 additions (same day, after the first commit)

- **Audio**: everything synthesised (`audio/synth.gd`, 23 SFX + a 4-bar menu loop, seeded and
  deterministic, 23 sounds in ~60 ms at startup). Buses Music/SFX/UI, per-user volumes. Gunshots,
  hitmarker/headshot, kill sting, hurt, death, bolt, reload, dry fire, swap, footsteps, jump/land,
  round start/end, UI hover/click; remote shots are 3D-positioned.
- **Settings** (`core/settings.gd`, user://settings.json): name, sensitivity, scoped
  sensitivity, invert, four volumes, relay host, line profile. Panel in the menu and the pause
  overlay.
- **UI in the approved menu language** (`ui/shared/ui_style.gd`): lobby cards with identity
  colours and HOST/YOU/BOT tags, HOST ONLINE with a friend code and COPY, join by code or
  address, settings panel, pause overlay (resume / settings / leave), results restyled, diagonal
  wipe on the host's start and slams elsewhere, title slams, button sounds.
- **Friend-code joining through noray** (`net/noray_transport.gd`): NAT punch then relay
  fallback. Verified against the public relay `tomfol.io:8890`: a 25 s match with 3 seats held,
  378 ms RTT (the relay's location), 7 mm misprediction, 9 of 13 hits confirmed. The first two
  attempts died in two seconds because the host's state stream exceeded the relay's 128 kB/s
  per-relay cap, which the public server enforces by crashing.
- **Bandwidth** (that cap made it a blocker): `:position` + `:yaw` replace `:transform`, and
  netfox patch #4 sends state at 30 Hz. Three seats: host upload 37 KB/s per client (was 77–90),
  diff encoder sending 21 of 162 candidate properties per loop; six seats: 96 KB/s per client
  (was 170), 296 KB/s total. Hit agreement unchanged (17 of 17 on the LAN check). A six-seat
  match through the public relay would still exceed the cap; direct joins have no cap.
- `BOARDPLAN.md` and `tuning/board.json` written; the board itself is next.

### Bugs found and fixed today (all measured before and after)

1. Client's view of remote players lagged whole tick loops → 25 % hit confirmation. netfox
   recorded copies of stale state under new ticks for pure-playback nodes (patch #1).
2. Remote players froze on screen while shooting → 3 m mean error. Their broadcast
   `RewindableAction` mutated the playback node; mutation is now server-only.
3. Client kept its stale health/position 0.5–2.2 s after dying (4 of 10 runs). The client's own
   fire action re-queued a disputed shot tick every loop and re-recorded predictions over
   authoritative states until the tick left the 128-tick window. Same fix as 2; verified in
   6 later runs with the death→client lag detector (max 13 ticks).
4. Empty diff states acknowledged but never stored → 38–87 "reference tick missing" warnings and
   partial snapshots (patch #3). Now 0 per run.
5. Diff references aging out at 120 ms RTT (defaults 24 / 0 / 90 → 12 / 6 / 128).
6. Inputs queued before a death fired from the spawn point and cancelled spawn protection →
   12-tick post-respawn weapon lockout.
7. Rematch broke RPC paths (auto-renamed duplicate node) → old minigame removed before the new
   one is added.
8. Viewmodel clipped into walls → depth-squash shader.

### Visual state (screenshots taken today, `docs/screenshots/`)

`arena_spectator_sky.png` (`--spectate`, after the reference pass), `arena_hip_sniper.png`,
`arena_hip_ar.png`, `arena_burst.png` (`--fx_test`), `arena_scoped_target.png`, `main_menu.png`, `results.png`, and the earlier
`arena_spectator.png`. Cel bands with hard single-value shadows, ink line work on silhouettes and interior edges, value
ceiling, light dither, HUD as shaped elements, drawn scope overlay, kill feed, menu and results
on the marbled swirl. After the second reference drop (seven more images, measured in the
`STYLE.md` appendix): a procedural sky with flat two-tone drawn clouds (cream tops, cool
undersides, ink rims) exempt from the value ceiling, Roboquest-framed viewmodels with a sleeve
from the corner and per-weapon hip angles so the sniper still reads long, drawn star bursts for
muzzle and impacts, italic outlined HUD type. It is a gray-box: primitive boxes, capsule players,
box guns, the built-in font with a heavy outline (sheared for italics). Checked against `STYLE.md` §8: saturated coverage is low (field +
counter dominate), accents are small (a few purple crates, the top deck, visors), no soft
shadows, no bloom. Not yet: a display face, a sky beyond flat colour, any real modelling.

### Not verified / not done

- **Feel with a human.** Nobody has held the mouse yet. See the checklist.
- noray NAT punchthrough itself: only the relay fallback could be exercised from one machine.
- Steam sockets: interface only.
- Windows export: no preset; nothing platform-specific was written.
- Late join / reconnect: a client joining after the start gets no player (the six-seat run
  showed it before `--expect` was fixed).
- Player-vs-player collision: off by decision.
- The `_rpc_shot_fx` tracers for other players' shots are unreliable RPCs; not visually checked.

### Human checklist for the feel verdict (DESIGN.md §8)

Run the host on one machine and a client through `bad` (menu: LINE → BAD), or use two windows
on one machine with `tools/soak.sh`-style flags. Try, in this order:

1. Strafe-jump across the tower decks: does the arc feel floaty and readable, is air control weak
   but present, do buffered jumps and ledge (coyote) jumps fire when expected?
2. Quickscope a bot at 15–30 m: fire exactly as the scope settles (267 ms). Does the hit land
   when the crosshair says it should? Fire a tick early: it should feel like a hipfire miss, not
   a lie.
3. AR at 10 m and 35 m: 5 shots vs 9 shots to kill; does the recoil pattern feel learnable?
4. On the client: do your own movement and shots feel instant? Do remote players look smooth?
   After you die, how long until you see it?
5. Watch for the things that break the style: any soft shadow, any glow, any boxed HUD element.
6. Switch to AWFUL: things should degrade (hits rejected, remote players stepping) but nothing
   should snap you around except a death.

### Proposed changes to `DESIGN.md` (not applied; §0 says to propose, not edit)

- §2 stack table: physics engine is **Jolt**, with the reason (bit-exact character queries).
- §2 "known Godot limitation": still true for RigidBody; add that CharacterBody3D queries under
  Jolt are deterministic, which is what the movement relies on.
- §3: "20–30 Hz snapshots" is not what netfox does; state goes every tick with diff encoding.
  Either accept 60 Hz + a bandwidth budget or plan the decimation work (`NETPLAN.md` §9, §12).

### Next

1. A human plays it (checklist above) and writes the verdict into this file.
2. Bandwidth: quantise transform, pack weapon ints, 20 Hz for non-predicted fields.
3. Real map pass on the arena layout (it is a table in `layout.gd`) and first proper viewmodels.
4. Choose the display face (OFL candidates: Bowlby One, Rubik Mono One, Titan One, Chango,
   Bungee) and build the type styles once.
5. noray transport, then the shell (`DESIGN.md` §7 step 3).
