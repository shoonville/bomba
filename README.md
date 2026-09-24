# BOMBA

A 2–6 player online party game: a board game in third person that keeps dropping everyone into
first-person minigames. Godot 4.7, GDScript, netfox. Built to be played with friends.

Read `DESIGN.md` first. It is the single source of truth. Then `STYLE.md` (visuals),
`NETPLAN.md` (netcode), `DECISIONS.md` (every assumption, one line each) and `STATUS.md`
(what actually works, with numbers).

## Running

Open the folder in Godot 4.7 and press play, or from a shell. `GODOT` is the executable: the
scripts default to the macOS app; on Windows run them from Git Bash with the console build:

```sh
# Windows (Git Bash). macOS: GODOT=/Applications/Godot.app/Contents/MacOS/Godot
export GODOT=/c/Users/Shoon/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe

# Host with two bots and start the arena straight away
"$GODOT" --path . -- --host --bots=2 --start

# Join a host, routed through the "bad" network profile (120 ms RTT, 30 ms jitter, 3 % loss)
"$GODOT" --path . -- --join=127.0.0.1:27015 --conditioner=bad
```

With no arguments the main menu opens: HOST LAN, HOST ONLINE (a friend code through the noray
relay, default `tomfol.io:8890`, changeable in SETTINGS), JOIN (a friend code or address:port),
LINE (conditioner profile for direct joins), SETTINGS (name, sensitivity, volumes, render scale), BOTS +/−,
START MATCH (the board, a random minigame each round) or QUICK ARENA. As host, click a bot's
card to set it EASY, NORMAL or HARD. FPS controls: WASD, Space
jump, LMB fire, RMB scope, 1/2/Q weapons, R reload (the sniper loads one round at a time; the
trigger interrupts it), LMB switches who you watch when you are
out in LAST STAND, Esc pauses (resume, settings, leave), F5
reloads `tuning/*.json` in debug builds. Board controls: click ROLL or press Space; A D or the
fork buttons at a fork; Q opens the item hotbar on your turn, 1–9 or the wheel pick a slot, E
(or a click on it) uses the item; a portal then wants a player (click a row or A/D + Enter), the
laser and the claw aim with the mouse and fire or grab on a click, the bomb shows a ring of range and
throws where you click (right click puts any of them away). Hover LEFT or
RIGHT at a fork to see where the move lands; hold Tab for the whole board, and in a minigame
for the scoreboard.
E (or middle-click) pings the tile under the cursor for everyone; F1–F4 send an emote. Sound is synthesised at startup;
nothing is loaded from disk.

Online from a shell: `-- --host_online --bots=1 --start --expect=1` prints `HOST_CODE=…`;
`-- --join_code=CODE` (add `--relay` to skip NAT punching). `tools/noray_test.sh` does both.

A full match from a shell: `-- --host --bots=2 --start --board --autoplay --board_rounds=2
--board_minigame_seconds=8 --soak=120` runs the board → minigame → board loop with bots (the
minigame is drawn from `minigames/*/manifest.json` each round: ARENA, SNIPERS or LAST STAND
(`MINIGAMES.md`); `--minigame=snipers` pins it); the lobby's START MATCH does the same for humans, QUICK ARENA
skips the board. The board is BOMBA BAY, drawn by Sean (2026-09-24) and traced by `tools/gen_board.gd`: 82
spaces of one-way walkways on a moon-base plot with 4 forks (the start, the F3 junction, F2 and
F4), every space reaching every other (`tools/board_laps.gd` prints every route from the start
back to it, 18–61 steps); `--board_overview` frames all of it for a screenshot. The currency is
TICKETS, like an arcade's. The goal is a vending machine on each of the two annexes off the rim
(the drawing's two domes; `tools/mark_spots.gd` flags the walkway space nearest each as its
machine spot, and a bridge runs from the space to the annex); pass or land on the live one with
10 tickets and a toy pops out, then the machine moves to the other annex. First to 4 toys wins
on the spot (the host sets FIRST TO, TURN TIME, ROUND CAP and TOY PRICE in the lobby's MATCH
SETTINGS; `--toys_to_win=N`, `--toy_price=N`, `--machine_at=ID` and `--rocket_test` in the
harness). Spots, their emblems part of the tile: tickets (+3, a fan of stubs), item (a mystery bag:
bomb, portal, shield, the laser gun or the claw), damage (−3 tickets, spikes), and one safe spot
(cyan dome) that hands out a SHIELD, a glowing aura that eats the next bomb, damage spot, laser
hit or claw grab. The ROCKET stands on its pad by one space: landing on or passing that space
with 10 tickets in hand offers a flight (TAKE THE ROCKET or NO THANKS): you climb in, it lifts
off, arcs over the base and sets you down on the landing spot on the far side, the rest of the
roll walked on from there, and the rocket flies itself home. Everyone has 30 HP; the laser and
the bomb take it by distance (the bomb also shoves everyone in its blast three spaces back), and
a downed player bleeds, drops half their tickets to the shooter and respawns at the annex that
is not the live machine. The claw extends three spaces along its aim and grabs one item from
the first player in its path (three tickets from an empty bar); the portal takes you to a player
and pushes them back through it to your space.

Before every minigame a briefing screen shows its name, a live look at the map, how it plays and
the controls; everyone presses READY (Space) or the host presses FORCE START, then the GET READY
countdown runs. At the round's end everyone freezes, ROUND OVER and the winner show, the final
kill replays from the killer's eyes, and the board returns. Harness runs (`--autoplay`,
`--screenshot`, `--soak`, headless) skip the briefing unless `--briefing` is given; `--no_briefing`
skips it anywhere; `--auto_ready=SECONDS` readies your seat that long in.

Useful flags after `--`: `--autoplay` (a bot drives your seat), `--seed=N`, `--soak=SECONDS`
(quit and write `reports/<label>_summary.json` + `_traj.csv`), `--report=LABEL`, `--expect=N`
(host waits for N humans before `--start`), `--round_seconds=N`, `--log=0..4`,
`--screenshot=path.png --screenshot_at=5 --screenshot_quit` (add
`--screenshot_event=minigame|reward|myturn|mychoose|finished|out|results|laser|hit` to start the
timer on an event, `--screenshot_event_index=N` on its Nth occurrence; `--spawn_index=N` puts you at
a chosen spawn for a frame; `--give_item=laser`,
`--give_bots_item=laser` (`--give_item` takes a comma list), `--hotbar_test` (the bar open), `--target_test`
(the portal's player picker), `--pop_test=ITEM` (a pickup icon over your pawn), `--aim_test=DEG` (the
laser drawn at an angle), `--throw_test=DEG` (the bomb's ring and reticle), `--claw_test=DEG` (the claw
aimed at an angle) and `--board_auto_roll` exercise the board UI from a fresh match),
`--ads_progress=0..1` (pins the scope-in for a frame), `--board_overview` (whole board),
`--board_cam=x,y,z:tx,ty,tz` (camera anywhere on the board), `--render_scale=N` (pins the 3D
render scale; the SETTINGS slider is the player's cap, default 1.5 supersampling, and the game
steps the scale down and back up on its own to keep the GPU under a 60 Hz budget,
`--gpu_budget_ms=N` to force it),
`--spectate` (fixed showcase camera,
no local player), `--rounds=N` (host rematches N times), `--scripted` (seeded per-tick inputs for
every seat this peer owns; the determinism harness uses it), `--no_warmup` (skip the boot
preload and pipeline warm-up, for A/B runs of the start-of-scene hitch), `--max_fps=N` (cap the frame rate: a 60 Hz
player's view of the tick interpolation), `--perf` (with `--soak`:
GPU, render-CPU and frame milliseconds, mean and p95, printed at the end), `--vsync=0|1|mailbox|adaptive` (the present mode; a driver that forces vertical sync, Sean's NVIDIA panel does, overrides it) and
`--window=fullscreen|windowed` (override the settings for a run; Godot's own `--resolution WxH`
sets the window size). Frames over 150 ms are logged as `Frame hitch` with what the frame did;
`--hitch_ms=N` lowers that threshold for a stutter diagnosis (each line carries the frame's phases, process → pre-draw, the draw, post-draw → next process, and its draw calls and primitives); `--motion_log[=path]` records the camera every frame and adds a `MOTION` line (how even the step from frame to frame is, stalls, double steps; the CSV at `path`); `--window=exclusive` is Windows exclusive fullscreen; and `--perf` also prints a `PACING`
line (the median frame, frames over 1.5× and 2× the median, the longest, and the GPU pipelines
compiled while playing, which should be 0).
In the game, F11 toggles fullscreen; SETTINGS has WINDOW (fullscreen by default since 2026-09-22), VSYNC and
RENDER SCALE. A harness frame at a set size needs `--window=windowed` beside `--resolution`, or the run goes fullscreen.

## Verifying

```sh
tools/check_all.sh       # everything below except the soak, PASS/FAIL per stage, ~2 min (SOAK=1 adds it)
tools/test.sh            # unit tests + compile-all (re-imports first)
tools/determinism.sh     # same seeded input log at 60 and 240 fps must give identical trajectories
tools/soak.sh bad 45 1 1 # host + 1 client through a profile + 1 bot, 45 s; prints NETPLAN §11 numbers
LOG=1 tools/soak.sh bad 45 1 1   # also prints the shot and remote-view diffs below
"$GODOT" --headless --path . --script tools/report.gd -- shot_diff reports/soak_bad_host.log reports/soak_bad_client1.log
"$GODOT" --headless --path . --script tools/report.gd -- remote_diff reports/soak_bad_host_traj.csv reports/soak_bad_client1_remote.csv
"$GODOT" --headless --path . --script tools/report.gd -- frame_stats docs/screenshots/arena_spectator.png   # STYLE.md numbers for a frame
```

Nothing needs Python: the report tools (`tools/report.gd`: `traj_diff`, `soak_report`, `shot_diff`,
`remote_diff`, `frame_stats`), the board generator (`tools/gen_board.gd`) and the machine spot marker all run in Godot; nothing needs Python. The
harnesses use their own ports (27077, 27101, 27103) so a running game on 27015 never fails a check.

## Exporting for friends

`tools/export_windows.sh` writes `export/BOMBA.exe`, one file with the pack embedded, from the
"Windows Desktop" preset in `export_presets.cfg` (checked in; no signing, no secrets). It needs
Godot's 4.7.2 export templates installed once (Editor → Manage Export Templates → Download and
Install, or the curl + unzip lines in the script's header); the script says so and stops if they
are missing. Friends need nothing else: the exe hosts, joins by friend code through the relay,
and keeps its settings in `%APPDATA%Godotpp_userdataBOMBA`.

## Layout

One folder per subsystem (`DESIGN.md` §4): `core/` bootstrap and services, `board/` the turn-based
board (graph, rules, director, view; `BOARDPLAN.md`), `net/` transport,
conditioner, hitscan and history, `session/` lobby and registry, `fps/` player, weapons, view
and `fps/match/` the shared first-person match (map, spawns, clock, kill log),
`minigames/sdk/` the contract and `minigames/arena/`, `minigames/snipers/`,
`minigames/last_stand/` (a manifest and a few lines each; LAST STAND also carries its own map
table), `bots/`, `art/`
shaders and palette, `ui/` HUD, menu, results, `tools/` harnesses and tests, `tuning/` every
gameplay number as JSON. `addons/netfox` is vendored with six documented patches
(`addons/netfox/PATCHES.md`).
