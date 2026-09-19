# BOMBA

A 2–6 player online party game: a board game in third person that keeps dropping everyone into
first-person minigames. Godot 4.7, GDScript, netfox. Built to be played with friends.

Read `DESIGN.md` first. It is the single source of truth. Then `STYLE.md` (visuals),
`NETPLAN.md` (netcode), `DECISIONS.md` (every assumption, one line each) and `STATUS.md`
(what actually works, with numbers).

## Running

Open the folder in Godot 4.7 and press play, or from a shell (`GODOT` defaults to the macOS app):

```sh
# Host with two bots and start the arena straight away
/Applications/Godot.app/Contents/MacOS/Godot --path . -- --host --bots=2 --start

# Join a host, routed through the "bad" network profile (120 ms RTT, 30 ms jitter, 3 % loss)
/Applications/Godot.app/Contents/MacOS/Godot --path . -- --join=127.0.0.1:27015 --conditioner=bad
```

With no arguments the main menu opens: HOST LAN, HOST ONLINE (a friend code through the noray
relay, default `tomfol.io:8890`, changeable in SETTINGS), JOIN (a friend code or address:port),
LINE (conditioner profile for direct joins), SETTINGS (name, sensitivity, volumes), BOTS +/−,
BOARD (cycles the shipped boards), START MATCH (the board, a random minigame each round) or
QUICK ARENA. FPS controls: WASD, Space
jump, LMB fire, RMB scope, 1/2/Q weapons, R reload, LMB switches who you watch when you are
out in LAST STAND, Esc pauses (resume, settings, leave), F5
reloads `tuning/*.json` in debug builds. Board controls: click ROLL, a fork button, an item
button and then a player row, or Space / A D / 1 2 / Enter. Sound is synthesised at startup;
nothing is loaded from disk.

Online from a shell: `-- --host_online --bots=1 --start --expect=1` prints `HOST_CODE=…`;
`-- --join_code=CODE` (add `--relay` to skip NAT punching). `tools/noray_test.sh` does both.

A full match from a shell: `-- --host --bots=2 --start --board --autoplay --board_rounds=2
--board_minigame_seconds=8 --soak=120` runs the board → minigame → board loop with bots (the
minigame is drawn from `minigames/*/manifest.json` each round: ARENA, SNIPERS or LAST STAND;
`--minigame=snipers` pins it; `--board_id=eight` picks the other board); the lobby's START
MATCH does the same for humans, QUICK ARENA skips the board.

Useful flags after `--`: `--autoplay` (a bot drives your seat), `--seed=N`, `--soak=SECONDS`
(quit and write `reports/<label>_summary.json` + `_traj.csv`), `--report=LABEL`, `--expect=N`
(host waits for N humans before `--start`), `--round_seconds=N`, `--log=0..4`,
`--screenshot=path.png --screenshot_at=5 --screenshot_quit` (add
`--screenshot_event=minigame|reward|myturn|mychoose|finished|out|results` to start the timer on
an event; `--give_item=bomb` and `--board_auto_roll` exercise the board UI from a fresh match),
`--spectate` (fixed showcase camera,
no local player), `--rounds=N` (host rematches N times), `--scripted` (seeded per-tick inputs for
every seat this peer owns; the determinism harness uses it).

## Verifying

```sh
tools/check_all.sh       # everything below except the soak, PASS/FAIL per stage, ~3 min (SOAK=1 adds it)
tools/test.sh            # unit tests + compile-all (re-imports first)
tools/determinism.sh     # same seeded input log at 60 and 240 fps must give identical trajectories
tools/soak.sh bad 45 1 1 # host + 1 client through a profile + 1 bot, 45 s; prints NETPLAN §11 numbers
python3 tools/shot_diff.py reports/soak_bad_host.log reports/soak_bad_client1.log   # needs LOG=1
python3 tools/remote_diff.py reports/soak_bad_host_traj.csv reports/soak_bad_client1_remote.csv
```

## Layout

One folder per subsystem (`DESIGN.md` §4): `core/` bootstrap and services, `board/` the turn-based
board (graph, rules, director, view; `BOARDPLAN.md`), `net/` transport,
conditioner, hitscan and history, `session/` lobby and registry, `fps/` player, weapons, view
and `fps/match/` the shared first-person match (map, spawns, clock, kill log),
`minigames/sdk/` the contract and `minigames/arena/`, `minigames/snipers/`,
`minigames/last_stand/` (a manifest and a few lines each; LAST STAND also carries its own map
table), `bots/`, `art/`
shaders and palette, `ui/` HUD, menu, results, `tools/` harnesses and tests, `tuning/` every
gameplay number as JSON. `addons/netfox` is vendored with two documented patches
(`addons/netfox/PATCHES.md`).
