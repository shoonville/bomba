# BOMBA — BOARDPLAN.md

The board design, written before the board code (DESIGN.md §8). This is v0: enough board to
close the loop lobby → board → minigame → items → winner (DESIGN.md §7 step 4), built so that
spaces, items and boards are data and the rules are plain classes with tests.

Reference: Pummel Party for the turn structure and the joy of ruining a friend's turn. Not a copy
of its board or its item list.

## 1. The loop

A match is `rounds` rounds (tuning `board.rounds`, 5 for now). A round is:

1. **Turns.** Each player in turn order: use an item (optional, before rolling) → roll a d6 →
   move that many spaces, choosing at forks → the landing space fires its effect.
2. **Minigame.** Everyone plays one minigame (the arena, shortened to
   `board.minigame_round_seconds`). Placement pays coins (`board.rewards.coins_by_rank`), the
   winner also draws an item.
3. Back to the board for the next round.

The board has one live **vending machine** spot (a space flagged `goal` in the board file; two of
them, the spaces at the two annexes' bridges, Sean's "original two spots"). Passing through or landing on it with at least
`board.toy_price` coins pays, awards a **toy**, and moves the machine to the candidate farthest on
average from every player, never the one just used (with two spots, the other annex). The first player to
`board.toys_to_win` toys wins on the spot; otherwise, after the round cap, most toys wins and
coins break ties. The host sets toys to win, turn time, round cap and price in the lobby.

## 2. State and authority

`board/board_state.gd` is a plain class: players (space, coins, bombas, items, is_bot), turn
order, round, phase (`TURNS`, `CHOOSING`, `MINIGAME`, `FINISHED`), active player, pending
choice, dice value, goal space, and the seeded RNG stream name. `board/board_rules.gd` is pure:
`roll(state, rng)`, `path_options(state)`, `step(state, edge)`, `land(state, rng)`,
`use_item(state, item, target)`, `apply_minigame_result(state, ranking)`, `advance(state)`.
Every rule returns a list of **events** (`roll`, `move`, `coins`, `goal`, `item`, `turn`,
`minigame`, `finished`) that presentation animates. Rules never touch nodes.

`board/board_director.gd` (a Node under Game, one per match, lives across the minigames) runs it:

- **Server**: owns the state, applies intents, broadcasts `_rpc_state(dict)` reliably after every
  rule and `_rpc_events(list)` for the animation queue. Bots roll after `board.bot_think_seconds`,
  humans get `board.turn_timeout_seconds` then are auto-rolled. Fork choices: humans get
  `board.choice_timeout_seconds`, bots choose the branch nearest the goal.
- **Clients**: render the last state, play the event queue, send intents (`roll`,
  `choose(edge_index)`, `use_item(item, target)`) as RPCs to the server. Intents from the wrong
  player or wrong phase are ignored on the server.
- Turn-based, so no netfox rollback: reliable RPCs with the whole state (a few hundred bytes).

## 3. The board data

`board/boards/<id>.json`: `spaces` (id, position `[x, y, z]`, type, `next: [ids]`) and `start`.
Types: `start`, `blank`, `coin` (+3), `lose` (−3), `item` (draw one), `event` (v0: teleport to
a random space), `goal` (the moving goal's spawn candidates carry `"goal": true`). A fork is any
space with two or more `next` entries. The first board is a hand-made loop of ~28 spaces with two
forks and a shortcut, positions in metres on a 24×18 m field, some spaces raised.

## 4. Items

| Item | Effect | Counter |
|---|---|---|
| BOMB | Pick a player: they lose 5 coins and are knocked back 3 spaces | Spend coins early; stay behind the leader; a SHIELD eats it |
| TURBO | Next roll +3 | None; it is a race item |
| SWAP | Trade places with a player | Stand somewhere nobody wants |
| SHIELD | Passive: eats the next bomb, damage space or laser hit | It is spent by the first hit |
| LASER | Aimed with the mouse on your turn: a straight beam 3 spaces long; everyone in it loses HP by distance (all 30 within a space, 10 at the end); at 0 HP they drop half their coins to the shooter and respawn at the other annex | Keep your distance; a SHIELD eats the hit |

Players carry **HP** (`board.hp`, 30) as well as coins. HP only matters to the laser for now: a
downed player comes back at the machine spot that is not the live machine with full HP, and a
player under `board.bleed_below_hp` (10) bleeds until then. Items are strings in
`tuning/board.json`; the effect table lives in the rules. A new item is data + a rule branch, no
new nodes. The HUD shows the inventory as a hotbar: Q opens it on your turn, 1–9 or the wheel
pick a slot, E (or a click on the slot) uses it; the laser then aims with the mouse and fires on
a click, right click puts it away.

## 5. Presentation (STYLE.md)

- Spaces are six-sided floating tiles (cel material by type: blank in the field colour, coin
  in LEMON, lose in the danger red, item in LAGOON, event in GRAPE, goal in paper with a ring),
  ink outlines from the post pass, the swirl sky. The board palette is its own map entry.
- Pawns are the same capsule-and-head silhouette as the arena, in identity colours, hopping
  space to space (`board.hop_seconds` per step) with a small burst on landing.
- Camera: third person behind and above the active pawn, easing between pawns on turn change,
  pulling back at forks so both branches are visible.
- HUD in the menu language: a turn strip of player cards (coins, Bombas, items), the dice as a
  slammed numeral, the ROLL prompt, fork arrows (A/D or click), item buttons (1/2), round
  counter. Board music is the menu loop for now.
- Transitions: wipe into the minigame, slam back to the board.

## 6. What v0 does not do

No board camera control by the player, no shop, no more than two items, one board, no
mid-match join. Space effects are instant (no mini-events with UI). Bots use BOMB on the leader
with a coin lead, TURBO whenever they have it.
