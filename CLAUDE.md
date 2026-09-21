# BOMBA — notes for Claude Code (read this first on any machine)

BOMBA is Sean's 2–6 player online party game: a third-person board game that drops players into
first-person minigames. Godot 4.7, GDScript, netfox (vendored in `addons/`). Bomb Rush Cyberfunk
look, FLCL-style robot characters. Built with Claude Code across sessions; this file is the memory
that travels with the repo.

## Read order
1. `DESIGN.md` (the contract; its §8 rules are in force), `STYLE.md` (the look, measured).
2. `STATUS.md` (what exists, with numbers) and `DECISIONS.md` (every decision and why; newest at the
   bottom). Skim the last 40 entries of DECISIONS before changing anything visual.
3. `README.md` for how to run, flags and controls. `NETPLAN.md`, `BOARDPLAN.md` for the netcode and board.

## How Sean works (follow this)
- Terse notes, often numbered, sometimes while he is playing. Do exactly the listed items. A note about
  one object (the sniper, the AR sight, the markers) is scoped to that object: never extend it to its
  siblings. He stopped an unasked AR change with "i didnt say change the AR".
- "Keep working" / "add details" is an invitation to improve things, still within his settled verdicts.
- Report numbers and screenshots, never adjectives. Never claim something runs until it has been run
  headless or screenshotted. Never score feel: his verdict is the verdict.
- Every gameplay number lives in `tuning/*.json`. Append one line per decision to `DECISIONS.md`.
- Commit each verified piece with a clear message (trailer: `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`).
- Do not ask questions mid-task; make the call, log it, and say what you assumed.

## Settled verdicts (do not redo without a new note)
- Menu: the marbled swirl background is "the exact vibe"; never touch it. Logo: drawn wordmark,
  upright, no tagline, no orange (his BRC-vibe verdict is still pending).
- Characters: built to his FLCL references (`reference/char1.webp`, `char2.jpg.webp`, Canti).
- Sniper: the ORIGINAL hip pose (he rejected every re-angle), cream body, black scope, glass on the
  eyepiece only, one-round-at-a-time reload with a heavy sound. AR: the old boxy sight, red dot ON its
  screen (a translucent pane at ADS), crisp snap sound, untouched otherwise.
- Board: one board (BOMBA BAY, `tools/gen_board.py`), pink sky kept, moon-base theme under it, floating
  spinning markers (flat stamps were "ugly"), close Pummel-Party camera, eight-sided die, no water.
  The vending machine lives on the two annexes only (his "original two spots", the bridges to the
  egg domes); never add machine pads or more spots.
- Hitmarker: low woody click, not high-pitched. Music: off (`Audio.MUSIC_ENABLED`).

## Verify before claiming
- `tools/check_all.sh`: tests + compile-all, determinism, a headless board match. `SOAK=1` adds the
  netcode soak. Scripts are shell scripts; on Windows run them from Git Bash with
  `GODOT=/c/Users/Shoon/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe` (Sean's desktop: RTX 5090,
  no Python, so the report tools are GDScript, `tools/report.gd`). `.gitattributes` keeps every text
  file LF; if a script dies on `\r`, strip them: `git ls-files --eol | grep w/crlf`, `sed -i 's/\r$//'`.
- `tools/test.sh` re-imports first; REQUIRED after adding any `class_name` script.
- Screenshots: `-- --screenshot=out.png --screenshot_at=N --screenshot_quit`, with
  `--screenshot_event=minigame|reward|myturn|mychoose|finished|out|results|shield|roll|move` to arm on an
  event. Handy flags: `--board_overview`, `--board_map`, `--board_cam=x,y,z:tx,ty,tz`, `--hover_fork=left`,
  `--social_test`, `--show_scoreboard`, `--figure_test`, `--ads_progress=0..1`, `--force_weapon=0|1`,
  `--force_ads`, `--give_item=ID`, `--minigame=ID`, `--render_scale=N`, `--port=N`, `--no_warmup`,
  `--perf` (GPU/CPU ms summary at soak end), `--vsync=0|1`, `--window=fullscreen|windowed`, and
  Godot's own `--resolution 1920x1080` (the friends' resolution: judge looks and cost there, not at
  Sean's 5120×2160; his monitor "doesn't matter"). `tools/report.gd -- frame_stats IMAGE...` prints the
  STYLE.md appendix numbers (saturated, grey, dark, v95) for a frame; judge a visual pass by them.
- Windowed runs: wrap them in `timeout 90` so a broken build cannot sit at a window forever; grep
  the output for `Frame hitch` (any frame over 150 ms, with what it did), `Minigame build` and
  `PERF` (with `--perf`). An `override.cfg` in the project root overrides project settings for an
  experiment (shadow size, MSAA); delete it afterwards, it is not tracked.
- Harness runs must not use port 27015 while his own game is open; pass `--port=27077`.
- Never run two soaks, or a soak and a windowed run, at once (contention ruins the numbers).

## Where things are
`core/` boot, game flow, settings · `board/` graph, rules, director, view, dice, pawns · `fps/` player,
weapons, view (viewmodel, figure, spectator), `fps/match/` the shared FPS match · `minigames/` SDK plus
`arena/`, `snipers/`, `last_stand/` · `bots/` · `audio/` synthesised sounds · `art/` shaders, cel material,
post stack, palette · `ui/` menu, HUD, board HUD, results, settings · `tuning/` every number · `tools/`
harnesses and tests · `docs/screenshots/` the verified frames.
