# BOMBA — MINIGAMES.md

The minigame contract and every minigame's rules, written before the code (DESIGN.md §8). A
minigame is a folder under `minigames/` that the registry finds on its own; the board draws one
per round (never the same twice in a row when there is a choice), `--minigame=ID` pins it.

## 1. The contract

`minigames/<id>/manifest.json` declares `id`, `display_name`, `tagline` (one line under GET
READY), `min_players`, `max_players`, `camera`, `scoring`, `time_limit_seconds`, `weapons`,
`bot_profile`, `scene`, and for the briefing before the round `description` (how it plays, a few
lines) and `controls` (a list of "KEY  what it does"). The scene's root script extends `Minigame`: it receives `setup(players,
seed, config)` on every peer and returns a ranked `MinigameResult` through `finished`. It never
reaches into board, session or item state.

First-person minigames extend `FpsMatch` (`fps/match/fps_match.gd`), which builds the map from a
layout table, spawns everyone, drives the bots and runs the clock, and expose their rules through
hooks: `_layout()`, `_palette_map()`, `_respawns()`, `_score_for(player)`, `_score_label(player)`, `build_visuals()` (the look, built one chunk per frame under the held wipe after `setup()`),
`centre_text()` (what the HUD prints instead of DOWN), `hud_status()` (lines the HUD prints at the
top centre), `hud_score(player)` and `hud_score_header()` (the big number top-right and the
scoreboard column), `objective_position()` (where the bots go when nobody is in sight; `INF` for
none). A minigame with no map of its own uses the ARENA layout (`GrayboxLayout`); LAST STAND
carries `pit_layout.gd`.

## 2. The minigames

| Minigame | Rules | Clock | Scoring |
|---|---|---|---|
| ARENA | free-for-all, sniper and AR, instant respawn with protection | 180 s | kills |
| SNIPERS | bolt-action only | 150 s | kills, headshots count double |
| LAST STAND | one life each, the dusk pit, the dead spectate | 60 s | survival: the later you fell the higher; alive at the clock ties for first |
