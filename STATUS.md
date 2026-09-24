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
| `board/` | graph + rules (tested), director, 3D view, HUD, two items; the full loop verified with bots and with a client |
| Not started | `items/` as a module (items live in the board rules for now), Steam transport, melee, Windows export preset |

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
- **The board** (`BOARDPLAN.md`, `board/`): graph loaded from `board/boards/first.json` (26
  spaces, two forks, six goal candidates), pure rules (`BoardRules`) with 11 tests (seeded dice,
  forks, landing effects, goal claim and move, BOMB and TURBO, minigame rewards, round advance,
  finish, standings, serialisation, bot choices), a server-authoritative director replicating the
  state by reliable RPC, a 3D view (hex tiles by type, planks, goal ring, hopping pawns with
  bursts and floating labels, following camera, own palette and sky) and a HUD (turn strip with
  coins/Bombas/items, slammed dice, prompts, fork and item input). The lobby's START MATCH runs
  it; QUICK ARENA keeps the old flow.
  Verified headless: host + 2 bots, 2 rounds with 8 s arenas, board → arena → rewards → board →
  arena → finish, 0 errors; and host + client through `bad` with the same final standings on
  both peers. Not yet: a human has not played a board turn; 2 items only; one board.

### Session 3 additions (evening; Sean's menu notes applied first)

- **Menu**: no tagline, upright lettering everywhere, logo colours from `palette.json`
  `menu.logo_*` (tangerine fill, ink outline, white sticker border; provisional until Sean
  reacts). `docs/screenshots/main_menu.png` is current.
- **Minigame SDK proven with a second minigame**: the match logic left `minigames/arena` for
  `fps/match/fps_match.gd` (`FpsMatch`: layout → map, spawns, round clock from the manifest,
  respawns, kill log, `_score_for` hook). `minigames/arena/arena.gd` is 3 lines;
  `minigames/snipers/` (manifest `weapons: ["sniper"]`, 150 s, headshots score 2) was added
  without a change outside its folder. The registry finds it by folder scan (tested).
- **LAST STAND** (`minigames/last_stand/`): one life, last one standing, `scoring: "survival"`
  (rank by death tick, survivors tie first), ends early when one is left; the eliminated
  spectate a living player from a chase camera (LMB cycles) under "OUT · N LEFT · WATCHING
  <name>". Needed hooks in `FpsMatch` (`_respawns`, `_score_label`, `centre_text`) and a
  dead-body guard; nothing else outside its folder. The board's draw now honours
  `min_players`/`max_players`. Warmup shows a 3-2-1 under GET READY.
- **Board rounds draw their minigame** (seeded, no immediate repeat; `--minigame=ID` pins it):
  intro card "NEXT UP: SNIPERS" on the board, "SNIPERS · GET READY" in the FPS HUD, and a
  reward card with the ranked coins when the board resumes; pacing reserves 2.4 s for each.
- **Items**: SWAP (trade spaces) and SHIELD (passive, eats a BOMB) join BOMB and TURBO; 4 kinds
  can be drawn. Bots use SWAP only for a gain of ≥ 3 steps. 2 new tests (13 board tests).
- **Mouse on the board**: ROLL, fork (LEFT/RIGHT by the tiles' screen positions) and item
  buttons, click a player row as the target; keys unchanged.
- **Results after a board match** read "◆ Bombas · coins" instead of a composite score.
- **THE PIT**, LAST STAND's own map (26 × 22 m, `_layout()` hook, folder-only): 4-seat rounds
  end by elimination in 8.3 s mean / 12.9 s max over seeds 1–5, against 16.3 s / 35.7 s on the
  gray-box. A new layout test checks every bot waypoint edge is clear; it caught six broken
  edges in the gray-box (two through the mid walls, two corner waypoints and two spawns inside
  the buildings) which are fixed. Bots had been walking into those walls since session 1.
- **Second board** FIGURE EIGHT: hub start/fork, two loops, a raised bridge in each (27 spaces,
  3 forks, 6 goal candidates). Lobby button cycles boards; `--board_id=eight`. Tests: every
  board validates, loops to its start and reaches every goal from every space; 2-round
  headless match on it with 4 seats (SNIPERS then LAST STAND, one Bomba claimed), 0 errors.
- **`tools/check_all.sh`**: tests + compile-all, determinism, and a 4-seat 2-round headless
  board match on every shipped board with random minigames, PASS/FAIL per stage. Last run:
  4 of 4 PASS in 3 min 11 s (69 tests, 2400 trajectory rows identical, both boards clean).
- **Harness**: `--screenshot_event=minigame|reward|myturn|mychoose|finished|out|results|shield`,
  `--give_item=ID`, `--give_bots_item=ID`, `--board_auto_roll`, `--minigame=ID`.
- **Netcode soak after the refactor** (`tools/soak.sh bad 45 1 1`, 3 seats): client RTT 128.0 ms
  mean, misprediction 0.5 mm mean (0.217 m including the ±12 ticks around 3 deaths), 19 of 25
  predicted hits confirmed (0.76), death→client lag 5 / 1 / 13 ticks, no outages, host upload
  40.4 KB/s. Session-2 numbers were 126.6 ms, 1.7 mm, 11 of 14, ≤13 ticks, 37 KB/s: same
  behaviour.
- **Network regression** after the refactor: host + client through `bad` on FIGURE EIGHT, 2
  rounds (SNIPERS then ARENA): identical minigame rankings and final standings on both peers
  (BOT TANGERINE 1 Bomba 14 coins, client 20, bot 15, host 11), 0 errors either side. Six
  seats headless, 3 rounds on FIGURE EIGHT (LAST STAND ×2 with 6 seats, SNIPERS): 0 errors.

Numbers: `tools/test.sh` 73 tests, 9973 assertions, 89 scripts compiled, 0 failures. Headless
host + 2 bots, 2 rounds with 8 s minigames: round 1 ARENA (2 weapons), round 2 SNIPERS (1
weapon, one headshot kill scored 2), board → minigame → rewards → board → minigame → finish, log
24 lines, 0 warnings, 0 errors. Headless LAST STAND with 4 seats: 2 kills at ticks 394 and 608,
two survivors tied #1 at the 60 s clock, the dead ranked #3 (608) and #4 (394). Headless board,
3 rounds of 20 s: LAST STAND (ended early at tick 1389, one left), ARENA, LAST STAND (early at
6618), 0 errors. Windowed 1-round loop with the HUD present: 0 script errors after the fix
below.

Bugs found and fixed in this block: (0) weapons were never locked during the 3 s warmup, so
bots killed under GET READY (the LAST STAND intro screenshot showed the kill in the feed; in
the seed-9 headless run the first kill was at tick 51 with the round starting at 180); locked
through `PlayerContext.can_fire_at`, first kill now at tick 190. (1) the host never saw the reward card because Game
recreated the board HUD *after* emitting the ranking, and the director broadcasts the reward
events synchronously inside that emit (clients were fine; the screenshot proved it). (2) At
match end the HUD's process/draw called the director for three frames after it had left the
tree: 3 "get_unique_id on null" script errors per finish; guarded in both. (3) The dice from
the last roll showed through the intro card; cleared on the minigame event. (4) "ROUND 2 / 1"
after the last round; display clamps. (5) LAST STAND ended a loop before the last death was
processed (the victim's tick runs after the shooter's), so that player scored "FELL AT 0:00"
and the results screen printed 1073741824 for the survivor: the end check now waits for
pending deaths, and results carry labels (SURVIVED / FELL AT m:ss). (6) HUD health read "-24"
on a body that stayed down; clamped.

New screenshots: `board_intro_card.png`, `board_reward_card.png`, `board_roll_button.png`,
`snipers_intro.png`, `snipers_hip.png`, `results_board.png`, `last_stand_intro.png`,
`last_stand_out.png` (eliminated, "OUT · 4 LEFT"), `last_stand_spectate.png` (chase camera),
`results_last_stand.png`, `board_items.png` (item strip + ROLL), `board_fork.png` (LEFT/RIGHT),
`board_eight.png`, `board_shield.png` (a bomb eaten by a shield), `lobby.png` (board selector),
`last_stand_pit.png` (THE PIT from the showcase camera).

### Session 4 (evening, Sean's six notes after his first play)

His first launch (`Shoon`, HOST LAN, no bots) sat in empty 90 s minigames: the lobby now
seeds two bots. Then six notes, all done:

1. **Logo**: a drawn wordmark (`ui/shared/logo_mark.gd`): round-stroke throw-up letters,
   ink outline, teal drop layer, yellow spark; cream/ink/teal/yellow from the menu palette, no
   orange. `main_menu.png`. His verdict pending.
2. **Pawn flash**: state broadcasts no longer snap existing pawns; the events move them.
3. **Dice**: a 0.8 m score-yellow die with ink pips tumbles from the active pawn (0.55 s air,
   0.22 s settle to the real face, 0.8 s hold); the HUD number slams on touchdown.
   `board_dice_air.png`, `board_dice_landed.png`.
4. **Hitmarker**: CoD-style tick, 74 ms, spectral peak 3161 Hz, centroid 3251 Hz; headshot
   two ticks 45 ms apart over a 260 Hz thud, 189 ms. Measured, not yet heard by him.
5. **Sniper**: round barrel and a cylinder telescopic sight with rings, bell, eyepiece and a
   glow lens. `arena_hip_sniper.png`.
6. **One board**: BOMBA BAY (`board/boards/main.json`, `tools/gen_board.py`): 65 spaces, a
   35-space loop plus a raised 11-space bridge, two inner cuts and an outside detour; 4 forks,
   10 goal candidates, min tile spacing 3.17 m, hops 3.25–5.36 m. FIRST LOOP and FIGURE EIGHT
   removed (the small one is now the rules-test fixture); the lobby BOARD button is gone.
   `board_overview.png`, `board_turn.png`.

Then from his first full match log: kills counted twice a tick apart (fixed, deduped per life,
0 doubles in a 17-kill bot round) and a bot that headshot him 0.28 s into LAST STAND and won
SNIPERS 9–2 and 14–3 ("normal" retuned: 550 ms reaction, chest aim, 5.5° settling error,
260°/s turn, no head start in the countdown; bots now first kill 1.1–5.6 s after the start,
headshots 12 % of kills).

Third round while he played: hitmarker lowered to a 2.06 kHz-centroid click-knock (was 3.25
kHz), the sniper rebuilt rounded and Intervention-shaped with a closer 20° hip pose, and the
scope-in now goes through the glass (rifle up → iris closes → glass clears → zoom → reticle)
instead of zooming into the receiver. Frames: `arena_hip_sniper.png`, `sniper_ads_45.png`,
`sniper_ads_75.png`, `arena_scoped_target.png`.

Fourth round, "add details": board space markers, a 128 BPM match loop, arena and pit
dressing (posters, lamps, road paint, hazard stripes), a dusk palette for the pit, taglines
under GET READY, the sniper held low and across with the whole scope in frame. The bay under
the board went in and came out on his note (pink sky stays). The AR was left alone on his word.
Frames: `board_turn.png`, `arena_spectator_sky.png`, `last_stand_pit.png`, `snipers_intro.png`,
`arena_hip_sniper.png`.

Fifth round: music off (one constant), the sniper reloads one round at a time with a
"shell_in" sound per round (104 ms, centroid 2.2 kHz) and the ammo ticks filling one by one,
the trigger interrupts the reload once a round is in (3 new weapon-logic tests), the board
has item / damage / coin spots plus one safe spot that hands out a SHIELD (blocks the next
bomb or damage spot; tested), and the sniper hip pose is copied from his
`reference/Intervention_MW2.webp`. 73 tests, 9973 assertions.

Sixth round: menu sounds lowered (hover 280 Hz, click 222 Hz), the sniper's round-in sound
made heavy (peak 79 Hz), the sniper painted cream, the AR shot made crisp (centroid 4.1 kHz,
76 ms), fork hover glow on the board. His ARENA kill at tick 7170 was in the feed but scored 0:
scoring and the HUD now read the kill log, and a warning logs any state/log disagreement.
Not reproduced with bot or scripted seats.

Seventh round: the sniper is cream with a black scope and translucent, reflective glass on
both lenses; characters are humanoid now (a procedural `Figure`: cap, hoodie, pack, gloves,
big sneakers; walks, tucks, aims, tips over when dead) in the arena and on the board; the host
can click a bot's lobby card to set EASY / NORMAL / HARD. Frames: `arena_hip_sniper.png`,
`sniper_ads_45.png`, `arena_spectator_sky.png`, `board_turn.png`, `last_stand_spectate.png`,
`lobby.png`.

Autonomous block after the humanoids: results podium (top three figures on ink blocks, the
winner hopping, `results.png`), the board counts down the last 10 s before an auto-roll,
figures flinch when hit, pawns verified to face their travel direction mid-hop
(`board_hop.png`), `tools/check_all.sh` 3 of 3 PASS with the figures in.

Then: name labels over other players (hidden while down) and the held gun shows the weapon
slot (long cream rifle or short carbine); spectator rig creation guarded against a double
build on the death frame.

Board camera (Sean: "more zoomed in on whoever's turn it is, like Pummel Party"): 9 m out at
42° instead of 18 m, and it now orbits behind the moving pawn along its heading (eased ≤
100°/s, tighter follow during hops) and stands behind the pawn at a fork looking down the
middle of both paths, so LEFT and RIGHT are left and right on screen; the fork buttons moved
out to the sides. `board_turn.png`, `board_hop.png`, `board_fork.png`.

Eight-sided die (Sean): rolls 1–8 from `board.json` `dice_sides`, an octahedron with ink
numbers (opposite faces sum to 9) that lands to the camera's right with the number reading
upright; TURBO shows as "5 +3". Found while doing it: every `Label3D` in a post-processed scene
(pawn names, the "?" event sign, floating +3 labels, arena name tags, the die numbers) had
never rendered, because the outline post quad samples the screen texture from the opaque pass
and paints over transparent objects drawn before it. Labels now use alpha-cut (opaque pass)
and get inked with everything else. Pawn name tags moved to the HUD (projected from each
head, sized by distance, pushed apart when four pawns share the start tile, the active
player's in the accent colour). `board_dice_landed.png`, `board_turn.png`.

Board icons went flat onto the tile faces for one build and came straight back as the
floating, spinning markers on Sean's word ("it looks ugly on the spot"). Die numbers are bold
(96 px with a 16 px same-colour outline). `board_turn.png`, `board_dice_landed.png`.

Sean's notes on the sights: the sniper scope's far end is black like the scope (the eyepiece
keeps its glass); the AR keeps its old boxy sight with a red dot floating above it, aligned to
the aim point at ADS, and the HUD crosshair hides there (`ar_ads.png`, `arena_hip_ar.png`,
`arena_hip_sniper.png`). His log's 2.3 s / 1.6 s stalls at board and arena start did not
reproduce (build times 4–31 ms; cold shader cache: one 208 ms hitch at arena start); frames
over 150 ms wall-clock are now logged with the phase so the next occurrence names itself.

Characters rebuilt to Sean's FLCL references (Canti): boxy cream screen head with a dark
screen, scanline and ears in the identity colour on a thin neck; open bomber jacket in the
identity colour over a dark ribbed core with a shirt in the opening; belt; thin jointed arms
with cream forearm guards and dark gloves; long thin legs with knee balls; chunky boots with
red soles. Same rig, so arena, board and podium changed together. The AR's sight got its red
dot on the screen itself (a translucent pane you aim through at ADS). `figures.png`,
`board_turn.png`, `last_stand_spectate.png`, `ar_ads.png`.

Quality-of-life pass (Sean asked for QOL and more board detail): fork hover previews the whole
move down that branch with a cream landing tile; hold Tab for the whole board (blends in and
out); rows show steps to the goal, a NEXT tag and flash on coin changes; a ROUND N / M banner;
Tab scoreboard in the minigames (kills, deaths, best first). Board detail: a bomb-with-fuse
beacon over the goal, eight floating islands with props drifting in the void, a pulsing ring
under the active pawn. `board_fork.png`, `board_map.png`, `board_turn.png`,
`arena_scoreboard.png`. Harness: `--board_map`, `--show_scoreboard`.

Sean picked two from the QOL list: minigame rewards now show as "+N" beside each player row
while the reward card plays (`board_reward_card.png`), and the board has a social layer: E or
middle-click pings the tile under the cursor (a bouncing pin in your colour with your name,
3 s, a chirp) and F1–F4 send GG / NICE! / OH NO / HURRY UP as a speech bubble over your pawn
(2.4 s, a pop). One any_peer RPC on the director, cosmetic, rate-limited to one per 0.4 s per
peer, payloads validated; works on anyone's turn. `board_ping.png`; `--social_test` harness.

Graphics pass: 1.5× supersampling so ink lines and cel edges are anti-aliased, line width
scaled by render scale and distance, 8192 24-bit directional shadows (117 texels/m on the
board). 60 FPS at the vsync cap in the board and the arena at 1600×900 on the M4 (headroom
past the cap not measured). Moon theme: the board on a floating slab of grey moon rock with
craters, boulders, posts under every tile, a rocket on a landing pad, a satellite dish, a
buggy, a buried probe, a crew member and flag; asteroids, a ringed planet, a small moon and a
UFO doing laps; pink sky kept. `board_turn.png`, `board_map.png`, `board_overview.png`,
`arena_hip_sniper.png`, `board_planet.png`. RENDER SCALE is a setting (default 1.5) for weaker
GPUs; `--render_scale`, `--board_cam` harness flags.

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
`arena_hip_ar.png`, `arena_burst.png` (`--fx_test`), `arena_scoped_target.png`, `main_menu.png`,
`lobby.png`, `pause.png`, `results.png`, `board_turn.png`, `board_shared_tile.png`, and the earlier
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
- Late join / reconnect: a client joining after the start is now refused with a reason (menu:
  "NO SEAT: MATCH IN PROGRESS"; headless exit code 2), but cannot be seated mid-match.
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

1. A human plays it (checklist above, plus one board turn with the mouse, a LAST STAND death
   and the spectator camera) and writes the verdict into this file. `tools/check_all.sh`
   first, so the verdict is about feel and not about a broken build.
2. Bandwidth: quantise position, pack weapon ints, so six seats fit the public relay cap.
3. A third-person or objective minigame (the SDK's `camera` field is still read by nothing;
   `scoring` now has kills and survival behind it).
4. Real map pass on the gray-box (`fps/match/graybox_layout.gd` is a table) and first proper
   viewmodels.
5. Choose the display face (OFL candidates: Bowlby One, Rubik Mono One, Titan One, Chango,
   Bungee) and build the type styles once.

## 2026-09-19 — session 5: first session on Sean's Windows desktop

Machine: RTX 5090 (driver 32.0.16.1088), Ryzen 7 9800X3D, 62 GB, one 5120×2160 display at
165 Hz, Godot 4.7.2 at `C:\Users\Shoon\Tools\Godot`, no Python installed. Everything below was
run on it.

- **Setup**: `core.autocrlf=true` had checked every shell script out as CRLF, so none of the
  harness ran (`$'\r': command not found`). `.gitattributes` now keeps every text file LF on
  every machine. Git identity set; the editor's rewrite of `project.godot` (uid autoload paths,
  default keys dropped) accepted, no setting changed.
- **Harness without Python**: `tools/report.gd` (traj_diff, soak_report, shot_diff, remote_diff)
  replaces the four Python tools, same output line for line; checked with identical trajectories
  (PASS, exit 0), three altered rows (listed, exit 1) and a real soak.
  `tools/check_all.sh`: 3 of 3 PASS in 1 min 41 s (74 tests, 10018 assertions, 90 scripts
  compiled, 2400 trajectory rows identical at 60 vs 240 fps, board 'main' 4 seats 2 rounds 0
  warnings); the M4 took 3 min 11 s. `tools/determinism.sh` alone: 22.8 s.
- **Soak on Windows** (`PORT=27077 LOG=1 tools/soak.sh bad 45 1 1`, 3 seats): client RTT
  131.1 ms mean, rollback 16.0 mean / 54 max, misprediction 1.7 mm mean (82 mm including one
  death), 12 of 14 predicted hits confirmed (0.86), death→client lag 7 ticks, 0 outages, 57 of
  57 shots agree between client and host, remote view error 2.9 cm and 6.3 cm mean (every
  sample over 30 cm is a respawn teleport), host upload 42.5 KB/s (1913 KB over 45 s; the M4
  measured 40.4 KB/s in session 3). Same behaviour as the Mac.
- **Frame rate** (`FPS at soak end`, vsync off, host + 2 bots, render scale 1.5 unless noted):

  | Scene | Window | FPS |
  |---|---|---|
  | board | 1600×900 | 162 |
  | arena | 1600×900 | 162 |
  | board | 5120×2160 fullscreen | 162 |
  | arena | 5120×2160 fullscreen | 158 |
  | arena | 5120×2160 fullscreen, scale 2.0 | 149 |

  162 in every windowed case is the 165 Hz refresh, so those are floors, not the GPU's limit.
  At native 5K with the default 1.5× supersampling the arena renders at the display's rate;
  RENDER SCALE can stay at 1.5 here.
- **Sean's stalls reproduce on this machine** (the M4 never showed them) and are mostly gone.
  Before: boot first frame 1.5–1.7 s, board start 704 ms with a cold shader cache and 162–184 ms
  warm, arena start 811 + 255 ms cold and 313–381 ms warm, board → minigame 278–292 ms. The
  hitch log now prints what the slow frame did (GPU memory change, script and physics time,
  nodes and resources created, pipeline compilations by source), which ruled out the 635 MB
  first-frame allocation (a 247 MB variant stalled the same) and pipeline compilation (0 at draw
  time) and pinned it on the switch frame's own work: first load of the FPS script graph
  106 ms, HUD scene 31 ms, match build 76–83 ms. Fixes at boot behind the boot colour:
  `Game._preload_resources()` (221 ms) and `PipelineWarmup` (125–186 ms, three frames of every
  material kind). `--no_warmup` skips both.

  | Frame | Before (warm cache) | After |
  |---|---|---|
  | board start | 162–184 ms | under 150 ms, not logged |
  | arena start from boot | 313–381 ms | 100–160 ms |
  | board → minigame switch | 278–292 ms | 150–161 ms |
  | results screen | 190 ms | under 150 ms, not logged |
  | boot first frame | 1.53–1.65 s | 1.83–1.88 s |

  What remains is the switch frame's build (match build 75–83 ms of which map 1 ms, HUD
  15 ms, freeing the old scene) under the wipe's cover. A shared primitive-mesh cache was tried
  and reverted (no change).
- **Bandwidth** (Next item 2, done by measurement): the six-seat soak (host + 3 clients through
  `bad` + 2 bots, 30 s) showed the real cost: 113 KB/s per client in 1100 packets/s, at the
  relay cap, because netfox transmitted every resimulated tick's state (the host rolls back
  ~7 ticks a loop with lagged clients) and every fire action broadcast every loop. netfox
  patches #5 and #6 (`addons/netfox/PATCHES.md`):

  | Seats, profile | Host upload per client | Packets/s per client | Client RTT | Mispredict | Hit confirm | Death→client lag |
  |---|---|---|---|---|---|---|
  | 6, bad, before | 113 KB/s | 1100 | 131–144 ms | 2–129 mm | 0.55–0.67 | ≤ 22 ticks |
  | 6, bad, after | 30 KB/s | 263 | 131–137 ms | 3–6 mm | 0.71–1.11 | ≤ 8 ticks |
  | 3, bad, before | 42.5 KB/s | 487 | 131 ms | 1.7 mm | 0.86 | 7 ticks |
  | 3, bad, after | 14.9 KB/s | 147 | 133 ms | 3.7 mm | 0.89 | 1 tick |

  Zero outages and zero client warnings after; 28 of 28 shots agree at three seats; remote
  players as the client sees them err 0.3–0.7 mm mean excluding respawn teleports (was 2.3–3.0 mm). Client
  upload is 25 KB/s, so a relayed client now moves ~55 KB/s both ways against the 128 kB/s cap.
  The first cut of patch #5 ("the loop's newest tick") broke every client (128-tick rollbacks
  each loop, disconnects) because a client's own player is not simulated on the host at the
  loop's newest ticks; the shipped patch sends each node's newest simulated tick.
- **Soak harness**: host outlives its clients by 3 s, a headless client whose host leaves
  finishes its soak or quits (one had sat for 5 min 48 s), reports keep the peer id from the
  start, `remote_diff` prints the mean without respawn teleports.

### Next (after session 5)

1. Sean plays on this machine: the §8 checklist above, plus a board turn with the mouse, a
   LAST STAND death and the spectator camera, and a friend joining by code. The stalls he
   reported should be gone at the board and 100–160 ms under the wipe elsewhere; his log will
   say (`Frame hitch` lines name what the frame did).
2. Windows export for friends: install the 4.7.2 export templates (Editor → Manage Export
   Templates; `%APPDATA%\Godot\export_templates` is empty) and add a Windows Desktop preset;
   nothing platform-specific has been written.
3. Then: a third-person or objective minigame, proper viewmodels, the display face (the map
   pass is in as dressing, pending his verdict).

## 2026-09-20 — session 6: for the friends' machines

Sean: his resolution doesn't matter (ultrawide 5K); his friends play 16:9 at 1080p or 1440p
on ordinary PCs. "Just make the game look really good and run well." Everything below is
measured at 1920×1080 unless noted, on the 5090, and extrapolated.

- **Client CPU** (netfox patch #7, no per-tick state apply for the players a client only
  watches): six-seat client tick loop p95 11–13 ms → 5–6 ms; hit confirmation 0.67–0.90,
  death lag ≤ 5 ticks, 0 outages, 0 warnings. Host unchanged (7.0 ms mean, it simulates all).
- **GPU** (`--perf`, host + 2 bots, 12 s, mean / p95 ms on the RTX 5090):

  | Scene, window, settings | GPU ms |
  |---|---|
  | arena 1080p, scale 1.5, MSAA 2, shadow 8192 (default) | 0.64 / 0.96 |
  | board 1080p, default | 0.63 / 0.64 |
  | arena 1080p, scale 1.0 | 0.36 / 0.38 |
  | board 1080p, scale 1.0 | 0.36 / 0.38 |
  | arena 1080p, shadow 4096 | 0.64 / 0.96 |
  | board 1080p, shadow 4096 | 0.60 / 0.62 |
  | arena 1080p, MSAA off | 0.42 / 0.43 |
  | arena 1440p, default | 1.04 / 1.35 |
  | arena 5120×2160 fullscreen, default | 2.90 / 3.24 |

  Render CPU 0.15–0.41 ms. A mid-range GPU is 8–20× slower, so 1080p at the default lands
  at 5–13 ms: fine on an RTX 3060 or GTX 1660, over a 60 Hz frame on a GTX 1060 or a laptop.
- **Auto quality** (`core/quality.gd`): RENDER SCALE is the cap; the game steps the 3D scale
  down (to 0.75) when measured GPU time exceeds 11.7 ms p90 and back up when there is room,
  one step per 3 s. Forced test at 1080p with a 0.5 ms budget: 1.5 → 1.25 → 1.0 three
  seconds apart, then held; the real budget never moves it here.
- **Window and vsync**: SETTINGS → WINDOW (WINDOWED / FULLSCREEN), VSYNC; F11 toggles
  fullscreen. Vsync on by default. `--window`, `--vsync`, `--resolution` for the harness.
- **1080p frames checked** (menu, board turn, sniper hip, AR ADS): ink lines and hard shadows
  crisp, HUD fits 16:9. Seen: a pawn's projected name tag can print over the player rows at
  the top-left of the board HUD; and the arena is still the gray-box, the largest look item left.
- **Arena dressing** (`fps/match/map_dressing.gd`, decor only, play untouched): a skyline of
  two block bands with lit windows, a crane and a mast outside the walls; windows, doors, a
  cornice, pipes and two billboards on the walls; windows and roof units on the buildings,
  straps on the crates, a beacon on the tower, a plaza, sidewalks and grates on the floor,
  barrels and a dumpster at the edges. The pit gets the same city in its dusk tones. Cost at
  1080p: 409 → 744 objects, GPU 0.64 → 0.66 ms, build 1 → 9 ms. Frames retaken:
  `arena_hip_sniper.png`, `arena_hip_ar.png`, `arena_spectator_sky.png`, `last_stand_pit.png`.
  His verdict on the look is pending.
- **Board detail pass** (`board/board_dressing.gd`; Sean: "add a bunch of detail... make it look
  great"): tile insets, post collars, plank stripes and cables, 11 lamps, a pennant start line;
  9 small props beside the path (cones, bins, kiosks, a spool, crates); 12 hatches, 10 rock
  clusters, pebbles, dust, cracks, rim rock; two annex platforms with bridges
  (the base: habitat domes, corridors, greenhouse, cargo, oxygen; the works: fuel tanks, solar
  array, telescope, antenna); on the slab solar arrays, cargo, a comms mast, antennas, a drill
  rig, landing lights, three signs; alive: a patrol drone, a driving buggy with tracks, blinking
  lights, a shooting star, a space station, a freighter. Built in 25 ms; board GPU at 1080p
  0.63 ms (unchanged), render CPU 0.41 → 0.84 ms. Frames retaken: `board_turn.png`,
  `board_overview.png`, `board_map.png`. His verdict pending.
- **The vending machine** (Sean's new goal): the two annexes carry it (his correction: "just those
  original two spots that you made originally", not five new pads). `tools/mark_spots.gd` flags the
  walkway space nearest each annex (L20 for the habitat annex, L9 for the works), a level plated
  bridge runs from the space to the annex, and the machine stands on the annex facing it; the live
  one is lit (L20 at the start, the farther from L0). Pass or land on its space with 10 coins and a
  toy pops out and flies to you; the machine moves to the other annex (the rule still picks the
  candidate farthest on average from everyone, never the one just used). First to 4 toys ends the
  match at once; the round cap (10) ends it otherwise. Bombas are gone from state, HUD, results.
  Lobby MATCH SETTINGS (host): FIRST TO, TURN TIME, ROUND CAP, TOY PRICE. 76 tests, a headless
  first-to-one match ended in round 3. Props, signs and landmarks keep out of the bridge corridors.
  Frames: `board_machine.png` (the live annex), `board_toy.png` (a purchase), `board_overview.png`,
  `board_map.png`, `board_turn.png`, `lobby.png`. His verdict pending.
- **Visual pass** (Sean: "is it possible for you to make the visuals look better?"): (1) both
  cel shaders multiplied by ALBEDO inside light(), which Godot does again afterwards, so every
  surface rendered as albedo squared: lit planes clamped at the ceiling, shadows near black
  (last_stand_pit 82 % of pixels under V 0.25, the references 5–19 %). Fixed; shadow band 0.7;
  the palettes retuned so the accepted look holds (S up a fifth, V up 0.06–0.12 on the field,
  counter and skyline tones). (2) A print layer on the big planes: ink seams on a metre grid
  (paving, wall panels, storeys) with a flat value step per cell, hard-edged mottle on the moon;
  numbers in `tuning/palette.json` "print". (3) `tools/report.gd -- frame_stats` measures frames
  the way STYLE.md measured the references. At 1080p: arena spectator saturated 47 % (reference
  22–52 %), mean S 0.57 (0.56–0.71), dark 11 % (5–19 %); the pit dark 82 → 14 %. GPU 0.71 ms
  arena, 0.69 board (was 0.64 / 0.63). Ten doc frames retaken. His verdict pending.
- **Board items, the laser gun** (Sean's spec: Q hotbar, 1–9 / wheel, E; a laser gun, left
  click fires where the red line points, the character turns with the cursor, 30 HP, bleeding
  and blood). Everyone has 30 HP (`board.hp`). The LASER item (`board.items.laser`): a beam 3
  spaces long (11.3 m here), 1.4 m wide; all 30 within a space, 10 at the end; a shield eats it;
  at 0 HP half your coins go to the shooter and you respawn at the other annex with full HP.
  Blood splats live in the state so they survive the board rebuild. Bots fire at whoever the
  beam hurts most. HUD: a nine-slot hotbar with drawn icons, HP bars on the rows. 78 tests; a
  headless match with lasers in every hand: 5 shots, 3 kills, no errors. Frames:
  `board_items.png` (the hotbar), `board_laser.png` (the shot). His verdict pending.
- **Sean's five notes** (2026-09-21): the sniper's bipod hangs from the barrel (hinge block and
  clip); the ARENA tower has three flights of 0.75 m steps to the top with rails, and the corner
  buildings' windows and roof units sit where they should (they had the centre height added
  twice, floating 2 m up); target mode moves the camera to the targeted pawn; an item pickup pops
  its icon over the head instead of the name; the hitmarker is a dice tick (headshot two), and the
  muzzle burst is gone. Frames: `arena_hip_sniper.png`, `arena_spectator.png`, `arena_hip_ar.png`,
  `board_items.png` (target mode), `board_item_pop.png`. His verdict pending.
- **Sean's ten notes** (2026-09-21): the muzzle flash is back as a round red-orange puff and the
  impact stars are 45 % of their size; a Halo-shaped sniper crack with the hanging ring; the
  BOMBA BAY sign is gone; the rocket has a skirt, a bell and right-triangle fins; the AR's dot
  is 30 % smaller and its body is a receiver, handguard, barrel, magazine, grip and stock; the
  minigame reward's icon pops over the winner's head as their turn begins; the turn order is
  the last minigame's ranking (tested); the pawns rollerskate across the board (a level glide,
  a push-glide walk, wheels under the boots). Frames: `arena_hip_ar.png`, `arena_burst.png`,
  `board_turn.png`, `board_hop.png`, `board_reward_card.png`. His verdict pending.
- **Guns aim at the reticle; pawns face the walkway at the start** (Sean, 2026-09-23): the hip
  angles are derived from each gun's position so the barrel converges on the camera axis 20 m out
  (sniper yaw +0.67° / pitch +0.55°, AR +0.73° / +0.58°, no cant; they were −11° / −19° yaw with a
  cant, muzzles swung right). Measured on the 1080p frame: the sniper barrel's line hits the
  reticle; the scope passes 6 px over it. The sniper then moved 7 cm left (x 0.16) so the whole
  scope is in frame: its eyepiece had projected past the right edge. A new board pawn faces its first step (they stood
  facing north, backs to the walkway). His verdict pending.
- **BOMBA BAY at 20 turns a lap** (Sean, 2026-09-23): `tools/gen_board.gd` (GDScript now; the
  Python is gone) makes the same board bigger: 116 spaces, a loop of 86 with four short
  branches, every lap 86–92 steps = 19–20 turns of the d8 (was 30–40 steps, 8 turns). The moon
  base keeps its density on the 4.3× slab (craters, rocks, props scale with the area); the
  machine spots are L49 and L74, 8+ hops from the start. Flag: the first machine is now a lap
  away and a 10-round cap ends most matches on rounds, not toys. His verdict pending.

## 2026-09-22 — session 8: the lost kill, the export preset, KING OF THE HILL

"continue", with the previous session's notes settled. Three pieces, each verified and committed.

- **The lost kill, fixed** (`tools/check_all.sh` failed at HEAD on the 2026-09-18 tripwire: "state
  says 0 kills, the kill log says 1"). A five-bot LAST STAND stress lost a kill or a death in six
  of eight rounds; per-tick diagnostics showed why: a kill at tick T is counted in the victim's
  `_rollback_tick`, netfox patches #4/#5 left the transmitter's latest state tick one behind the
  simulation on alternate loops, the host restarted every other rollback loop at a tick it had
  simulated, and in that tick only the nodes the fire actions mark mutated (every recent
  shooter) ran again while the victim was re-applied from history, so the record for T+1
  overwrote both counters with pre-death values. Fixed twice: netfox patch #8 (the authority's
  latest state tick is the newest simulated tick; the decimation counts from its own tick), and
  `kills`/`deaths` are plain once-per-life counters kept in step with the kill message, not
  rollback state (two ints fewer per state). After: LAST STAND five bots eight rounds 40 kills
  0 lost, SNIPERS 74 kills 0 lost, 78 tests, determinism identical, soak `bad` (host + 1 client +
  1 bot, 45 s): rtt 131 ms, misprediction 5 mm, hit confirmation 0.93, 32 of 32 shots agree,
  death → client 2 ticks, 0 outages. Known: with lagging clients netfox still re-runs a shooter's
  tick without a victim who has not fired within the window, rewinding that victim one tick of
  movement (≤ 5 cm); a late-simulation pass in netfox would close it.
- **Windows export** (Next item 2 from session 5): `export_presets.cfg` is checked in (Windows
  Desktop, x86_64, pack embedded, no signing) and `tools/export_windows.sh` writes
  `export/BOMBA.exe`. It stops with the path when the 4.7.2 export templates are missing, which
  they are on this desktop (`%APPDATA%\Godot\export_templates` is empty): Sean installs them once
  from the editor (Manage Export Templates) or with the two lines in the script's header, then
  the script runs. `reports/` carries a `.gdignore` (140 stray `.import` files from CSVs).
- **KING OF THE HILL** (Next item 3, the objective minigame): planned in `MINIGAMES.md` §3, built
  in `minigames/hill/` on the shared FPS match with five new hooks (status lines, score cell and
  header, rank value, objective position) that the other three minigames do not use. A glass
  hill on a ring with a pennant and a beam, eight spots on the arena (tower top, roofs, catwalk,
  four lanes), moving every 30 s along a seeded order; a tick alone inside scores, contested
  scores nobody, 60 s alone wins; bots path to it and hold it (the roofs are bot-free). Numbers
  in `tuning/hill.json`. Verified: 83 tests (5 new, `HillRules`), a headless four-seat round
  (three placements, ranked result 790 / 615 / 266 / 0 ticks), `check_all` with HILL drawn in
  round 1 of the board match, frames at 1080p: `hill_spectator.png` (saturated 51 %, dark 8 %,
  the arena's 50 % / 8 %), `hill_hip.png` (the hill held, the status lines), `hill_scoreboard.png`
  (the HILL column), `board_intro_hill.png` (the NEXT UP card). Switch frame into HILL under the
  wipe 175–186 ms. His verdict pending; "KING OF THE HILL" is a long name for the card.
- **Sean's item notes** (later the same day): TURBO gone; the BOMB thrown into a ring of range
  with AOE HP damage and a shove (bots never bomb their own blast); SWAP is PORTAL, a framed
  doorway with the menu swirl inside that you go through and push the mark back through; the
  SHIELD a pulsing aura; CLAW, aimed like the laser, extends three spaces along its line and
  grabs one item from the first player in its path (coins from an empty bar, a shield eats it);
  every icon redrawn with detail. 84 tests,
  three headless matches with the item in every hand (0 errors), frames: `board_bomb_aim.png`,
  `board_bomb_blast.png`, `board_portal.png`, `board_claw_aim.png`, `board_claw.png`, `board_shield.png`,
  `board_items.png`, `board_item_pop.png`. His verdict pending.
- **Characters rebuilt to Canti** (his reference, `reference/canti.webp`): an iMac G3 head in
  profile (a flat bezel, a big dome behind it, no handle) with a visor slit and ear piece, armoured chest with a badge and red trim, pauldrons, gauntlets,
  red pelvis, kneecaps and toe caps, a backpack; same pivots and hooks, so nothing else moved.
  Frames: `figures.png`, `board_turn.png`, `arena_spectator.png`, `results.png`. His verdict
  pending.

### Next (after session 8)

1. Sean plays: a KING OF THE HILL round with friends or bots (is 30 s per spot and a minute to
   win right; is the beam enough to find it; does the name want to be HILL), and the §8 checklist.
2. Export templates installed once, then `tools/export_windows.sh` and a friend runs the exe.
3. The display face (OFL candidates listed in session 4), a fifth minigame (Jenga needs synced
   physics props; Duck Hunt and Monster Trucks the vehicle controller), and the netfox late-
   simulation pass if the one-tick victim rewind ever shows in play.

## 2026-09-22 — session 9: Sean's nine notes, the arena stutter

Everything below was run on Sean's desktop today (`tools/check_all.sh`: 79 tests, 97 scripts,
determinism identical, a headless four-seat board match over two rounds with random minigames).

- **KING OF THE HILL removed** (his note 1): the folder, its tuning, five tests, two sounds, two
  events, the layout's eight spots, two harness flags, four frames, its MINIGAMES.md section. The
  five FpsMatch hooks and the bots' objective code stay with defaults. Rotation: ARENA, SNIPERS,
  LAST STAND.
- **Shooting has nothing red** (note 2): no muzzle flash on either weapon; the body-hit star is
  paper; the headshot hitmarker is the score yellow. **AR** (notes 3, 4): dot radius 0.001715
  (30 % smaller again), the sight base 3.5 cm tall (30 % lower), the screen assembly down 1.5 cm
  with it and the ADS position matched: `ar_ads.png` has the dot at the frame's centre.
- **Sniper** (note 9): the eyepiece and its reflective glass were removed by mistake and put back
  byte for byte on his word ("the best feature"; a settled verdict now). The part in his picture
  was the bolt handle (tan bolt + dark knob, the bottom-right corner of the hip view at his 2.37:1
  aspect); found by hiding each rear part in turn. Gone. `arena_hip_sniper.png` retaken.
- **Pawns face their travel** (note 5): `hop_to` no longer half-turns after `look_at`; three
  frames into the first glide show the face forward. `board_hop.png` retaken.
- **One-piece head** (note 6): `Figure.head_mesh()`, a superellipsoid, boxy front to round back,
  one mesh in the identity colour; bezel, brow, cheek and chin pieces gone. `figures.png` retaken.
- **No match start or end sound** (note 8): `round_start` and `round_end` gone from the arena
  and the board HUD, and from the synth.
- **The arena stutter** (note 7), measured on his machine fullscreen (5120×2160, 165 Hz, vsync,
  host + 3 bots + autoplay, 25 s, `--perf --hitch_ms=12`):

  | | before | after |
  |---|---|---|
  | frames over 1.5× the 6.00 ms median | 48 (1.3 %) | 11 (0.3 %) |
  | frames over 2× the median | 28 | 1 |
  | frames over 12 ms in play | 29 (13–22 ms) | 2 (14 ms, and the quit) |
  | pipelines compiled while playing | 49 surface + 48 spec | 0 + 2 |
  | GPU ms mean / p95 | 2.86 / 3.54 | 2.90 / 3.48 |

  Cause: every shot built new meshes and materials for its burst and tracer, each a pipeline
  compilation on the shot's frame (27 of the 29 slow frames carried a shot's effects; the "physics
  13–16 ms" on those frames was the local shot's effects inside the tick loop). `Burst` and
  `Tracer` now share meshes and materials, size by node scale, fade by instance transparency, and
  the boot warm-up draws them. New harness aids: `--hitch_ms=N`, the `PACING` line under `--perf`.

### Next
1. Sean plays: the arena with friends (does it feel smooth now; the hitch log at `--hitch_ms=12`
   will say what any remaining slow frame did), the AR sight and dot, the sniper's corner, the
   heads, the pawns' facing, the silent match start and end.
2. If a windowed run still stutters for him (windowed showed runs of consecutive slow frames that
   fullscreen never did), the WINDOW setting → FULLSCREEN is the first thing to try.

### Smoothness plan (2026-09-22, measured; his call on the order)
Measured on his desktop after the shot-effects fix: pacing 0.1–0.5 % late frames, motion even to the
millimetre (35.8 mm every frame while walking), GPU 2.9 ms of a 6 ms frame at 5K, worst physics step
3.3 ms (4 seats, host). What is left, by what a player would feel:
1. DONE (2026-09-22, later the same day): the switch into a minigame stalled 150–200 ms and the
   return 119–148 ms; now 27 ms in and 17 ms back (the look built over frames under a held cover,
   the board view asleep through the minigame instead of rebuilt, shared viewmodel materials,
   one unit box mesh, netfox patch #9). The first board build of a match followed on 2026-09-23
   (session 11): 176 ms → 38 ms worst frame, built over 18 frames under the held cover.
2. MEASURED (2026-09-22): six seats, host loop 5.8 ms mean 9 p95, the players' own simulation 0.9 ms of it;
   85 % is netfox's per-property bookkeeping. A vendored-library change, deferred. The old text follows:
   the host's tick loop measured 7.0 ms mean (2026-09-19), which at
   165 Hz misses a refresh on every tick-carrying frame; fine at 60 Hz. Profile the loop with three
   clients and cut it (netfox's per-property apply, bot AI every other tick) before calling the host
   smooth at 165 Hz with friends.
3. DONE (2026-09-22): frame_queue_size 1 and swapchain 2 (pacing unchanged), fullscreen the default;
   audio latency left at 15 ms (unverifiable). The old text follows: `rendering/rendering_device/vsync/frame_queue_size`
   2 → 1 and `swapchain_image_count` 3 → 2 (one queued frame fewer; check pacing holds), audio
   `output_latency` 15 → 10 ms, and fullscreen rather than windowed by default (windowed showed runs
   of slow frames that fullscreen never did).
4. For the friends' machines: the client loop is 5–6 ms p95 on a 9800X3D; on a mid-range CPU that is
   half a 60 Hz frame before rendering. Same profiling as 2.

## 2026-09-22 — session 10 (evening): the die, hands, the round's end, the briefing

- **The die lands on the ground** (Sean's note 1): the moon's slab beside the tile, not tile
  height in the air; off the slab it stays at tile height. `board_dice_landed.png`.
- **Hands on the weapons** (note 4): two hands and forearms per weapon in the character's colour,
  built like the Figure's arms (gauntlet, pale cuff, palm, fingers, thumb). `arena_hip_ar.png`,
  `arena_hip_sniper.png`, `ar_ads.png` retaken.
- **The round's end** (note 3): everyone freezes at the end tick, ROUND OVER and the winner for
  2 s, the final kill replayed from the killer's eyes for 3.3 s (`KillCam`, from a 5 s replay
  ring every body keeps), then the switch; 5.7 s in all, 2.4 s with no kill in reach. Headless
  hosts hold nothing. `round_over.png`, `killcam.png`. Verified: check_all, a host and a client
  through two 12 s rounds.
- **The briefing** (note 2): before every minigame, a screen with the name, tagline, a live
  orbiting look at the map, HOW IT PLAYS, CONTROLS (two new manifest fields), seat cards with
  their READY state, READY (Space) and the host's FORCE START; everyone frozen until then.
  `briefing.png`. Harness: skipped unless `--briefing`; `--auto_ready=N` for unattended runs.
  Verified with a host and a headless client through the READY flow.

## 2026-09-23 — session 11: the wipe that never drew, the first board build over frames

Run on Sean's desktop, which now drives a 2560×1440 display at 240 Hz (the 5K 165 Hz panel is
gone; the friends' 1080p stays the yardstick). `tools/check_all.sh`: 79 tests, 99 scripts,
determinism identical, the headless four-seat board match over two rounds PASS.

- **The wipe draws** (found by accident, fixed): `Wipe._ready` set anchors only, which leaves a
  control under a CanvasLayer at 0 × 0, so every transition since session 2 was a cut and the
  held cover of the minigame switch hid nothing (a frame 50 ms into an arena start: the tan clear
  colour, the HUD, the look still building). With a size, a second fault showed: a `hold()` inside
  `Game.transition`'s callback was overwritten to "reveal" and the later `slam()` refused it, which
  would have left a full cover for the whole match. Both fixed. `wipe_reveal.png` (the band
  mid-sweep into the arena), `board_wipe.png` (into the board). His verdict on the band pending.
- **The first board build of a match over frames** (the smoothness plan's leftover): 176 ms on
  the start RPC's frame at 1080p (2795 nodes) is now 18 frames under the held cover, the longest
  35–38 ms (the annexes, the props); the start RPC's own frame stays 57–71 ms (the director 16,
  the HUD 2, the rest the transition frame's own work). `BoardView.build_visuals()` through
  `BoardDirector.build_view()`, the dressing a coroutine in five parts, a pawn per frame; state
  and events wait for `built`. The seeded layouts are unchanged.

  | first board build, 1080p windowed | before | after |
  |---|---|---|
  | longest frame | 176 ms | 38 ms (the RPC frame 55–71 ms) |
  | frames the build spans | 1 | 18 |
  | chunk ms | — | env 0, tiles 3, markers 4, moon 1, craters 6, props 29, crew 0, asteroids 0, horizon 0, dressing 9/17/5/4/1, pawns 6/1/1/1 |

- **The board at 60 fps on the new display, not in the game** (some forty runs, in DECISIONS):
  the old build in the real flow does it just as the new one; the present blocks one frame per four
  refreshes of the 240 Hz display; with the game window in the foreground, as in play, a whole 6 s
  run stayed at 60 fps. Not motion, not the present mode (his NVIDIA panel forces vertical sync on,
  so `--vsync=0` is not off on his desktop), not the build. His checks: Windows' refresh-rate setting
  (a dynamic 60/240 → the fixed 240) and the NVIDIA vertical sync for BOMBA, then a match with the
  driver's FPS overlay. The hitch line now carries the frame's phases (process → pre-draw, the
  draw, post-draw → next process), draw calls and primitives, and the boot line the screen size and
  refresh rate, so the next such question takes one run.

### Next
1. Sean: the Windows refresh-rate setting and the NVIDIA vertical sync for BOMBA (above), then a
   match with the driver's FPS overlay: is the board at 240 fps or 60. And the wipe (the accent band
   on every transition, seen for the first time) and the board's arrival under it.
2. The start RPC's frame (57–71 ms under the cover): the director's 16 ms and the transition
   frame's own work, if it ever shows.
3. Unchanged from session 10: his notes on the die, the hands, the round's end and the briefing.

## 2026-09-23 — session 12: Sean's eight notes, the 60 Hz beat

On his desktop (2560×1440, the game at 60 fps there until his display and driver settings change;
the friends' 1080p stays the yardstick). `tools/check_all.sh` green: 79 tests, 99 scripts,
determinism identical, the headless board match.

- **The briefing's text on a solid panel** (note 1), the map frame's style and size, the pair
  centred at any aspect. `briefing.png` retaken; checked at 2000×1080.
- **Full ammo on respawn** (note 2): `WeaponSlots.refill` inside `respawn_at`.
- **No barrel through a wall** (note 3): a shoulder ray per visible figure per frame; the gun lifts
  by the angle that clears the wall, eased. Engaged 4 times in 45 s of bot play.
- **One board camera heading** (note 4): south of the pawn, looking north, whichever way it travels.
  `board_turn.png`, `board_hop.png` retaken.
- **Red hitmarkers** (note 5), the headshot's a size bigger. `arena_hitmarker.png`. The impact stars
  and the missing muzzle flash keep their 2026-09-22 verdicts.
- **The kill cam scopes when the killer did** (note 6): the replay ring carries the scope-in, the
  camera zooms, the ghost weapon takes the ADS pose, the HUD draws the iris.
- **The floating weapon in the kill cam** (note 7): it was this peer's own first-person hands and
  gun at the live eye position, drawn because the kill camera draws every layer; hidden for the
  replay. `killcam.png` retaken.
- **Smoothness while strafing and aiming** (note 8), measured: the beat between the 60 Hz tick and
  a 60 Hz display. `physics/common/physics_jitter_fix` 0.5 → 0, the CameraRig after every
  TickInterpolator, `--max_fps=N` in the harness for the 60 Hz view.

  | arena, host + 3 bots, 15 s | jitter fix 0.5 | jitter fix 0 (three runs) |
  |---|---|---|
  | at 60 fps: stalled frames | 5 (0.76 %) | 0–2 (0–0.29 %) |
  | at 60 fps: double steps | 3 (0.46 %) | 1–2 (0.18–0.29 %) |
  | at 60 fps: step variation mean / p95 | 1.6 % / 2.7 % | 0.8–1.4 % / 1.7–2.8 % |
  | at 60 fps: physics step max | 16.3 ms | 5–13 ms |
  | at 165 fps: median / over 1.5× / stalls | 6.00 ms / 0.6 % / 0 | 6.00 ms / 0.7 % / 0 |

  Left: single ticks of 10–17 ms now and then (the WORST PER SECOND physics step; at 60 Hz each is
  a dropped frame), source not yet named; and his display at 60 Hz, which turns every late
  millisecond into a 33 ms frame.

### Next
1. Sean: the display's refresh-rate setting and the NVIDIA vertical sync for BOMBA (session 11),
   then a match: the eight notes, and whether strafing while scoped is smooth now.
2. The 10–17 ms ticks: name the source (bot pathing, a resimulation burst, the replay ring) with
   the hitch line's netfox and physics fields, then spread or cut it.
