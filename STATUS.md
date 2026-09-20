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
