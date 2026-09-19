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
START ARENA. Controls: WASD, Space jump, LMB fire, RMB scope, 1/2/Q weapons, R reload, Esc
pauses (resume, settings, leave), F5 reloads `tuning/*.json` in debug builds. Sound is
synthesised at startup; nothing is loaded from disk.

Online from a shell: `-- --host_online --bots=1 --start --expect=1` prints `HOST_CODE=…`;
`-- --join_code=CODE` (add `--relay` to skip NAT punching). `tools/noray_test.sh` does both.

Useful flags after `--`: `--autoplay` (a bot drives your seat), `--seed=N`, `--soak=SECONDS`
(quit and write `reports/<label>_summary.json` + `_traj.csv`), `--report=LABEL`, `--expect=N`
(host waits for N humans before `--start`), `--round_seconds=N`, `--log=0..4`,
`--screenshot=path.png --screenshot_at=5 --screenshot_quit`, `--spectate` (fixed showcase camera,
no local player), `--rounds=N` (host rematches N times), `--scripted` (seeded per-tick inputs for
every seat this peer owns; the determinism harness uses it).

## Verifying

```sh
tools/test.sh            # unit tests + compile-all (re-imports first)
tools/determinism.sh     # same seeded input log at 60 and 240 fps must give identical trajectories
tools/soak.sh bad 45 1 1 # host + 1 client through a profile + 1 bot, 45 s; prints NETPLAN §11 numbers
python3 tools/shot_diff.py reports/soak_bad_host.log reports/soak_bad_client1.log   # needs LOG=1
python3 tools/remote_diff.py reports/soak_bad_host_traj.csv reports/soak_bad_client1_remote.csv
```

## Layout

One folder per subsystem (`DESIGN.md` §4): `core/` bootstrap and services, `net/` transport,
conditioner, hitscan and history, `session/` lobby and registry, `fps/` player, weapons, view,
`minigames/sdk/` the contract and `minigames/arena/` the first minigame, `bots/`, `art/`
shaders and palette, `ui/` HUD, menu, results, `tools/` harnesses and tests, `tuning/` every
gameplay number as JSON. `addons/netfox` is vendored with two documented patches
(`addons/netfox/PATCHES.md`).
