# BOMBA — notes for Claude Code (read this first on any machine)

BOMBA is Sean's 2–6 player online party game: a third-person board game that drops players into
first-person minigames. Godot 4.7, GDScript, netfox (vendored in `addons/`). Bomb Rush Cyberfunk
look, FLCL-style robot characters. Built with Claude Code across sessions; this file is the memory
that travels with the repo.

## Read order
1. `DESIGN.md` (the contract; its §8 rules are in force), `STYLE.md` (the look, measured).
2. `STATUS.md` (what exists, with numbers) and `DECISIONS.md` (every decision and why; newest at the
   bottom). Skim the last 40 entries of DECISIONS before changing anything visual.
3. `README.md` for how to run, flags and controls. `NETPLAN.md`, `BOARDPLAN.md`, `MINIGAMES.md` for the
   netcode, the board and the minigames (the SDK contract and each minigame's rules).

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
- Characters: rebuilt to his Canti reference (`reference/canti.webp`, FLCL, the late-90s mecha look he
  asked for on 2026-09-22): monitor head, visor slit, armoured chest, pauldrons, red pelvis and toe caps.
  The head is ONE piece (an iMac G3 profile as a single mesh, `Figure.head_mesh`): a bezel on a dome
  read as "a mask on a normal circle head".
- Sniper: the ORIGINAL hip pose (he rejected every re-angle), cream body, black scope, glass on the
  eyepiece only, one-round-at-a-time reload with a heavy sound. The eyepiece and its reflective glass
  are "the best feature": NEVER remove or change them (removed once by mistake on 2026-09-22, reverted
  on his word within the hour). No bolt handle (the tan bolt and its knob sat in the bottom-right
  corner of the hip view; that was the part he wanted gone). AR: the old boxy sight on a 3.5 cm base
  (30 % lower than it was), red dot ON its screen (a translucent pane at ADS; the dot is 30 % smaller
  twice over, radius 0.001715), crisp snap sound, the purple body untouched.
- Board: one board (BOMBA BAY, `tools/gen_board.py`), pink sky kept, moon-base theme under it, floating
  spinning markers (flat stamps were "ugly"), close Pummel-Party camera, eight-sided die, no water.
  The vending machine lives on the two annexes only (his "original two spots", the bridges to the
  egg domes); never add machine pads or more spots.
- Hitmarker: a dice tick, "similar to the sound the dice makes" (two takes before it were too
  high-pitched). Muzzle flash: NONE (the red-orange puff was "distracting"; before it the cyan star
  was "tacky"); impact stars small and never red; nothing red on screen when shooting.
  Sniper sound: the ORIGINAL crack-boom-tail (the Halo-shaped take "sounds like a bazooka"; do not
  redo it). No match start or end sound (2026-09-22). Board pawns rollerskate (no hopping), facing
  their travel; no BOMBA BAY sign. Music: off (`Audio.MUSIC_ENABLED`).
- Minigames: ARENA, SNIPERS, LAST STAND. KING OF THE HILL was removed on his word (2026-09-22); the
  FpsMatch hooks it added stay for the next objective minigame. Every minigame opens with the
  briefing (name, live map, rules, controls, READY / FORCE START) and ends with the hold: ROUND OVER,
  the final-kill cam from the killer's eyes, then the board. Hands hold the weapons in the
  character's colour (a colour choice comes with his customisation screen later).
- Effects share meshes and materials (`Burst`, `Tracer`): a new mesh or material per shot compiled a
  GPU pipeline on the shot's frame and was the arena "skipping frames". Never build per-shot resources.
- Scene switches: a minigame's `setup()` builds the simulation on the RPC's frame (never spread it:
  a player spawned a tick late broke determinism) and `build_visuals()` builds the look one chunk
  per frame under `Wipe.hold()`; the board's first build of a match does the same (`BoardView.build_visuals()`
  through `BoardDirector.build_view()`, 2026-09-23); the board view sleeps through minigames
  (`BoardView.sleep/wake`), never freed and rebuilt. A held cover survives `Game.transition`'s
  callback and `slam()` reveals it (the wipe never drew before 2026-09-23: anchors alone size a
  control under a CanvasLayer to 0 × 0; set anchors AND offsets). A StandardMaterial3D's shader dies with its last user: keep shared
  instances (the viewmodel's, the warm-up's `_keep`), never a fresh one per match.

## Verify before claiming
- `tools/check_all.sh`: tests + compile-all, determinism, a headless board match. `SOAK=1` adds the
  netcode soak. Scripts are shell scripts; on Windows run them from Git Bash with
  `GODOT=/c/Users/Shoon/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe` (Sean's desktop: RTX 5090,
  no Python, so the report tools are GDScript, `tools/report.gd`). `.gitattributes` keeps every text
  file LF; if a script dies on `\r`, strip them: `git ls-files --eol | grep w/crlf`, `sed -i 's/\r$//'`.
- `tools/test.sh` re-imports first; REQUIRED after adding any `class_name` script.
- Screenshots: `-- --screenshot=out.png --screenshot_at=N --screenshot_quit`, with
  `--screenshot_event=minigame|reward|myturn|mychoose|finished|out|results|shield|roll|move|laser` to arm
  on an event (`--screenshot_event_index=N` for its Nth occurrence; a `myturn` frame needs
  `--screenshot_at=5` or more, the view is still playing the previous turn's hops before that).
  Handy flags: `--board_overview`, `--board_map`, `--spawn_index=N`, `--board_cam=x,y,z:tx,ty,tz`, `--hover_fork=left`,
  `--social_test`, `--show_scoreboard`, `--figure_test`, `--ads_progress=0..1`, `--force_weapon=0|1`,
  `--force_ads`, `--give_item=ID`, `--give_bots_item=ID`, `--hotbar_test`, `--target_test`, `--pop_test=ITEM`, `--aim_test=DEG`,
  `--machine_at=ID`, `--minigame=ID`, `--render_scale=N`, `--port=N`, `--no_warmup`,
  `--briefing` (show the pre-minigame briefing in a harness run; `--no_briefing` never; `--auto_ready=N`
  readies the seat N s in), `--round_seconds=N` (a short round to reach ROUND OVER and the kill cam;
  `--screenshot_event=results --screenshot_at=0.8` is the hold, `3.6` the kill cam),
  `--perf` (GPU/CPU ms summary at soak end plus a PACING line: median frame, frames over 1.5× and 2×
  the median, pipelines compiled while playing), `--hitch_ms=N` (log every frame over N ms with what
  it did; 150 by default), `--motion_log[=path]` (a MOTION line: how even the camera's step from frame to
  frame is; the CSV at path), `--vsync=0|1`, `--window=fullscreen|windowed|exclusive`, and
  Godot's own `--resolution 1920x1080` (the friends' resolution: judge looks and cost there, not at
  Sean's own display (5120×2160 at 165 Hz through 2026-09-22, 2560×1440 at 240 Hz since; his monitor "doesn't matter"). `tools/report.gd -- frame_stats IMAGE...` prints the
  STYLE.md appendix numbers (saturated, grey, dark, v95) for a frame; judge a visual pass by them.
- WINDOW defaults to fullscreen (2026-09-22): a frame at a set size needs `--window=windowed` with
  `--resolution`, or the run takes the whole screen.
- Windowed runs: wrap them in `timeout 90` so a broken build cannot sit at a window forever; grep
  the output for `Frame hitch` (any frame over 150 ms, with what it did), `Minigame build` and
  `PERF` (with `--perf`). A hitch line's phases (process → pre-draw, the draw, post-draw → next
  process) tell the game's work from the display's: a long process → pre-draw with a short draw is the
  render thread waiting on the present: the display and driver, not the game (2026-09-23: his NVIDIA
  panel forces vertical sync on, so `--vsync=0` is not off there, and the new 240 Hz monitor ran the
  board at 60 fps with the window in the foreground; his refresh-rate and vsync settings come first). An `override.cfg` in the project root overrides project settings for an
  experiment (shadow size, MSAA); delete it afterwards, it is not tracked.
- Harness runs must not use port 27015 while his own game is open; pass `--port=27077`.
- Never run two soaks, or a soak and a windowed run, at once (contention ruins the numbers).

## Where things are
`core/` boot, game flow, settings · `board/` graph, rules, director, view, dice, pawns · `fps/` player,
weapons, view (viewmodel, figure, spectator), `fps/match/` the shared FPS match · `minigames/` SDK plus
`arena/`, `snipers/`, `last_stand/` · `bots/` · `audio/` synthesised sounds · `art/` shaders, cel material,
post stack, palette · `ui/` menu, HUD, board HUD, results, settings · `tuning/` every number · `tools/`
harnesses and tests · `docs/screenshots/` the verified frames.
