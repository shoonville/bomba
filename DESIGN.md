# BOMBA — DESIGN.md

The persistent design document for this project. Read this at the start of every session,
before doing anything else. It is the single source of truth for what this game is, how it is
built, and what the standing rules are. If something here is wrong, say so and propose a change
— do not quietly work around it.

Companion documents:
- `NETPLAN.md` — the netcode design. Written before any netcode was implemented.
- `DECISIONS.md` — an append-only log: every assumption made and why, one line each.
- `STATUS.md` — current state, what works, what's broken, what's next.
- `tuning/*.json` — all gameplay values. Plain JSON, never hardcoded, never engine-specific.

---

## 1. What this game is

**BOMBA.** A 2–6 player online party game for PC.

A board game in third person — players take turns and move around a board — that regularly drops
everyone into a **first-person minigame**. Winning minigames awards items, and items are used
back on the board against other players.

Reference points, in order of importance:
- **Pummel Party** — the board, the turn structure, the joy of ruining a friend's turn.
- **Halo 3 custom games** — what the minigames should feel like. Player-made, silly, competitive,
  built out of a small number of well-tuned mechanics.
- **Bomb Rush Cyberpunk** — the entire visual and menu identity.

It is not a commercial product. It is being built to be played with friends. Every decision
should be weighed against that: fun with six people in a voice call beats technical elegance,
and momentum beats architecture.

### Design pillars

1. **The shooting is real.** Minigame combat is not a party-game approximation of shooting. Aim
   matters, the sniper rewards skill, and the game feels tight at realistic latency.
2. **Confident visual identity.** See `STYLE.md`. Never default, never templated.
3. **2–6 players, always.** Every system is designed for six and tested at two.

---

## 2. Stack and platform

| | |
|---|---|
| Engine | Godot 4 (latest stable — pin the exact version in the repo) |
| Language | GDScript |
| Networking | netfox (timing, client-side prediction, server reconciliation, interpolation) |
| Transport | ENet now, behind a thin interface so Steam sockets drop in later |
| NAT traversal | noray (via netfox.noray) — friends join without port forwarding |
| Target platform | Windows |
| Dev machine | Windows desktop (9800X3D / 64GB / RTX 5090) |

**Godot was chosen over Unity and Unreal** for: text-based scenes and resources (so an agent can
author whole features end to end), the fastest iteration loop, the best UI system of the three —
and this game is half menus — and zero cost. The tradeoff accepted: server-side hitbox rewind is
not provided by netfox and is written by hand. See `DECISIONS.md`.

**The known Godot limitation, written down so nobody rediscovers it painfully:** Godot's physics
are not deterministic and physics cannot be re-simulated multiple times in a frame, so
RigidBodies cannot participate in rollback. Consequences:
- All player movement is on **CharacterBody3D**, never RigidBody.
- **Driveable vehicles** must be arcade controllers built on CharacterBody3D with hand-authored
  suspension, grip and boost — not rigidbody simulations. This is a known future cost.
- **Uncontrolled physics props** (falling towers, exploding crates, scattered objects) are fine:
  the server simulates them, clients interpolate, no prediction needed. Nobody aims with a
  falling block, so 100ms of lag on them is invisible.

---

## 3. Netcode rules

These are non-negotiable and they govern every system in the game. Full detail in `NETPLAN.md`.

- **Server-authoritative.** The client never decides position, damage, stun, score, dice rolls,
  item effects, or minigame results. Assume every client is lying.
- **Fixed 60 Hz simulation tick, 20–30 Hz snapshots, both decoupled from render rate.** Identical
  inputs at 60 fps and 240 fps must produce identical results. This is the classic bug and it is
  tested explicitly, every run.
- **Client-side prediction and reconciliation** for the local character. Corrections are applied
  silently — the player never sees themselves snap unless the error is genuinely large.
- **Remote players interpolated ~100 ms behind.** Extrapolate no more than 2 ticks.
- **Server-side lag compensation** for hitscan: rewind hitboxes to the shooter's rendered time,
  clamped at 250 ms.
- **Never make a player wait a round trip to see their own action.** Local feedback is immediate;
  the server confirms after.
- **Never visually retract a hit the server later rejects.** Eat the inconsistency on the
  victim's side, which is where players tolerate it.
- **Seeded RNG service.** Nothing calls `randi()` / `randf()` directly. Any match must be
  reproducible from seed + input log.

### Two tools that are part of the engine, not the content

1. **Network conditioner** — built into the transport layer, not OS tooling, so it works
   identically everywhere and is deterministic. Profiles: LAN (0ms), good (40/5/0.5%),
   bad (120/30/3%), awful (250/80/8%). Nothing is ever declared working until it has been run at
   `bad`.
2. **Bots** — every minigame must be fully playable by bots so a 6-player match can be soaked
   without six humans. A minigame that requires a human to test is not finished. Bots are a
   reusable system, not a per-minigame hack.

---

## 4. Architecture

One folder per subsystem. Modules never reach into each other's folders; they talk through
public APIs and events.

| Folder | Owns |
|---|---|
| `core/` | Bootstrap, autoloads, event bus, seeded RNG, config, logging |
| `net/` | Transport interface, replication, prediction, hitbox rewind, network conditioner |
| `session/` | Lobby, player registry, match config, ready-up, reconnection |
| `board/` | Board graph, turn state machine, movement, space effects, branching paths, camera |
| `items/` | Item definitions, inventory, awarding, targeting |
| `fps/` | First-person controller, weapon framework, stun/status system, hit feedback |
| `minigames/` | The SDK contract, plus one self-contained folder per minigame |
| `bots/` | Reusable bot behaviour, per-minigame hooks |
| `art/` | Cel shader, outline pass, palette, decals, post stack |
| `ui/` | Menus, HUD, board UI, results screens |
| `audio/` | Music, SFX, bus layout |
| `tools/` | Screenshot harness, network harness, replay harness, showcase scenes |

**Gameplay logic lives in plain classes, not in nodes.** Damage calculation, weapon state
machines, board turn resolution, and item effects are written as plain GDScript classes that take
inputs and return outputs. Nodes are a thin layer that calls into them. This makes the logic
testable headlessly, reviewable without running the game, and portable if the engine ever
changes.

**A module failure never takes down a match.** A broken minigame forfeits to a fallback and logs
loudly. Silent fallbacks that hide a broken feature are a defect, not a safety net.

### The minigame SDK contract

This is the most important interface in the project and it is treated as sacred. A minigame:

- **Declares**: player count range, camera mode (first or third person), scoring model, time
  limit, required weapons, bot difficulty hooks.
- **Receives**: N players, a seed.
- **Returns**: a ranked result.
- **Never** reaches into board, session, or item state.

**Adding minigame #12 must require zero changes outside its own folder.** If it doesn't, the SDK
is wrong, and the fix is to the SDK, not a workaround in the minigame.

---

## 5. The first minigame — 1v1 arena

A first-person fight. Designed as free-for-all supporting up to 6 spawns, tested at 1v1. The
finished game is 2–6 players and spawn logic and map scale should not need rebuilding later.

### Movement model

**Halo 3, not MW2.** Slower base speed, floaty jump arcs with real air time, no sprint, no
slide. Momentum carries; acceleration is gradual rather than snappy.

This pairs deliberately with the quickscoping sniper: Halo's sniper culture was built on snap
shots against airborne targets, and floaty arcs make a skilled flick readable and rewarding.
The sniper skill ceiling lives in the jump arcs.

### Round structure

Timed round, most kills wins. Respawns are instant.

Consequences that make spawning a real system rather than a placeholder:
- Spawn selection must avoid enemy line of sight, not just pick a free point.
- Brief spawn protection — a second or two — is required. A one-shot sniper on a small map
  makes spawn camping the obvious degenerate strategy.
- Spawn logic is written for up to 6 players from the start, even though it is tested at 1v1.

### The map

Built to **Rust's (MW2) principles**, not a recreation of its geometry: tiny footprint, strong
verticality, one central landmark everyone orbits, sightlines that reward the sniper but always
offer a flank.

**Scale up roughly 25% from Rust's actual footprint, and add vertical.** Rust was sized for MW2
movement with sprint. Halo 3 movement has no sprint but longer, higher jump arcs, so the same
footprint plays cramped and the arcs have nowhere to go.

Original layout. A traced copy is tuned to a different game's movement speed, TTK and hitboxes,
and will play wrong in ways that are hard to diagnose.

### Sniper (Intervention-like)

Bolt action, one shot kill to torso and head.

**Quickscoping is a first-class mechanic, not an exploit.** The whole feel of this weapon depends
on it:
- **Scope-in is an animation, MW2-style** — the weapon raises and the scope settles over a real
  duration, and quickscoping means firing at the moment it settles. The animation is the
  mechanic, not decoration.
- The animation is client-predicted and starts instantly on input. Never wait on the server to
  begin ADS.
- The shot fires on client authority with immediate local feedback — muzzle flash, tracer, impact
  decal, hitmarker. The server confirms after. A flick that waits a round trip is a failure.
- **Anti-cheat rule:** the server grants full accuracy only if the client has been in ADS for at
  least `SCOPE_IN_TICKS` before firing. Shots inside that window get hipfire accuracy.
- **`SCOPE_IN_TICKS` must match the point in the animation where the scope visually settles.**
  If the server grants accuracy earlier or later than the animation implies, the weapon will
  feel like it is lying to you — the most common way a quickscope mechanic goes wrong. The
  animation is authored to the tuning value, not the other way round.

### Assault rifle

Full auto, hitscan, **no spread** — every bullet leaves the crosshair centre. Skill comes from
recoil control and tracking, not from a cone.

- Recoil is a **deterministic pattern** — a curve, not random — client-predicted and identical on
  every machine. No spread means no shared RNG for hit resolution, which removes an entire class
  of desync bug.
- **Damage falloff over distance is required.** Without it, a no-spread laser AR invalidates the
  sniper at every range where you can track. Near damage, far damage, and both distances live in
  `tuning/`.

### Melee — deferred

**Not in the spike. Not in the first playable minigame.** Cut to keep the first build focused on
whether aiming and hit registration feel right; a stun mechanic muddies that signal.

It is coming back, and the design is already settled so it can be dropped in later: short range,
does not kill, applies a stun with an explicit duration, an explicit recovery window, and an
explicit counterplay window. Those frame numbers go into `tuning/` before implementation, not
derived from an animation.

**What this means now:** the `fps/` weapon framework is built so a third weapon slot and a
status-effect system can be added without restructuring. Do not build the stun; do build the
shape that will hold it.

---

## 6. Art direction

**See `STYLE.md`.** It is the authority on everything visual — palette behaviour, shading model,
outlines, HUD, viewmodel and menus — and this section defers to it entirely.

Summary only:

- **Reference:** Bomb Rush Cyberfunk for the world, environments and menus. Roboquest for the
  first-person viewmodel framing only.
- **The reference is a style, not a colour scheme.** Palette is an open authoring decision.
  Accent hues are unrestricted; purple is explicitly in scope.
- **Flat cel shading**, hard-edged single-value cast shadows, dark ink-style line work including
  interior edges, and a value ceiling that keeps the image reading as illustration.
- **The menus carry a large share of the game's identity**, because a party game keeps players
  in them constantly. Budget real time for them.

**Asset policy:** CC0 or procedural only (ambientCG, Poly Haven, Kenney, or generated). Nothing
ripped from any game. Reference screenshots in `reference/` are for looking at and sampling
colour from, never for extracting assets, textures, fonts or models.

## 7. Scope and order

Build order is chosen to retire the biggest risk first. The shell is the larger half of the work,
but it is built *second*, on top of a foundation known to work.

1. **Netcode spike.** Gray-box arena, two players, sniper + AR (no melee), network conditioner,
   bots. The only question: does the shooting feel good at 120 ms? Everything else waits on this
   answer. → `NETPLAN.md`
2. **First minigame, finished.** Real map, real feel, FFA-capable, bot-playable.
3. **The shell.** Lobby with match config (2–6 players, configurable match length), board graph
   and turn state machine, items with targeting, results screens, the full menu
   layer. This is months of work, not weeks.
4. **Vertical slice.** Full loop: lobby → board → minigame → items → winner, with bots filling
   empty slots.
5. **More minigames.** Only once the SDK has proven it can take one without modification.

### Minigame backlog (not scheduled)

From Halo 3 custom games: Duck Hunt (vehicles + snipers), Fat Kid, Jenga, Monster Trucks.

Note the dependency: **Duck Hunt and Monster Trucks both need the arcade vehicle controller.**
That's a single ~40–60 hour investment that unlocks both, and it should be built once, properly,
in `fps/` or its own `vehicles/` module — not hacked into whichever minigame needs it first.
Jenga needs no new tech; server-simulated physics props with client interpolation already cover
it.

---

## 8. Standing rules for the agent

- **Write the plan before the code.** For any substantial system, produce the design document
  first so it can be argued with before there's an implementation defending it.
- **Report real numbers.** Adjectives are not a status report. "Feels great" is not a
  measurement. Report what failed, what's missing, and what the numbers actually were.
- **Never claim something works that hasn't been run.** Screenshotted, soaked, or conditioner-
  tested — or it is not done.
- **Never score your own feel.** Whether the shooting is good is a human judgement. Produce the
  build, the numbers, and a checklist of specific things to try. The verdict is not yours.
- **All gameplay values in `tuning/*.json`.** Editable without a rebuild. Nothing hardcoded.
- **Append to `DECISIONS.md`** every time an assumption is made. One line, with the reason.
- **Don't ask questions mid-session.** Make routine decisions, write down the assumption, keep
  going.
- **Don't edit another module's folder.** Propose the change instead.
- **Keep the project loadable at all times.**

---

## 9. Open questions

Unresolved. Revisit when they become blocking; don't pre-solve them.

- Steam integration timing — noray works for now, but Steam friend invites are what everyone
  actually expects. When does the transport swap happen?
- Board design: how many spaces, branching or linear, what space types exist.
- Item list: what the first six items are and how each is countered.
- Does the board phase need its own camera-controlled movement, or is it purely turn-based?
- Character models and customisation — how much, and how early.
