# BOMBA — BOARDPLAN.md

The board design, written before the board code (DESIGN.md §8). This is v0: enough board to
close the loop lobby → board → minigame → items → winner (DESIGN.md §7 step 4), built so that
spaces, items and boards are data and the rules are plain classes with tests.

Reference: Pummel Party for the turn structure and the joy of ruining a friend's turn. Not a copy
of its board or its item list.

## 1. The loop

A match is `rounds` rounds (tuning `board.rounds`, 5 for now). A round is:

1. **Turns.** Each player in turn order (the last minigame's ranking, winner first; the lobby order in round 1): use an item (optional, before rolling) → roll a d6 →
   move that many spaces, choosing at forks → the landing space fires its effect.
2. **Minigame.** Everyone plays one minigame (the arena, shortened to
   `board.minigame_round_seconds`). Placement pays tickets (`board.rewards.tickets_by_rank`), the
   winner also draws an item.
3. Back to the board for the next round.

The board has one live **vending machine** spot (a space flagged `goal` in the board file; two of
them, the spaces at the two annexes' bridges, Sean's "original two spots"). Passing through or landing on it with at least
`board.toy_price` tickets pays, awards a **toy**, and moves the machine to the candidate farthest on
average from every player, never the one just used (with two spots, the other annex). The first player to
`board.toys_to_win` toys wins on the spot; otherwise, after the round cap, most toys wins and
tickets break ties. The host sets toys to win, turn time, round cap and price in the lobby.

The board has one **rocket** (Sean's drawing, 2026-09-24), on a pad by one space (the file's
`shuttle`: `from`, `to`, `price`). Reaching that space, landing there or passing through, with the
fare in hand pauses the move with an offer (`pending_kind` "shuttle": stay, or fly): flying pays
the fare, moves the pawn to the landing spot on the far side without spending a step, and the
rest of the roll goes on from there; the view flies the rocket over with the rider in it and
brings it home empty. Bots fly when it brings the machine 8 hops nearer.

## 2. State and authority

`board/board_state.gd` is a plain class: players (space, tickets, bombas, items, is_bot), turn
order, round, phase (`TURNS`, `CHOOSING`, `MINIGAME`, `FINISHED`), active player, pending
choice, dice value, goal space, and the seeded RNG stream name. `board/board_rules.gd` is pure:
`roll(state, rng)`, `path_options(state)`, `step(state, edge)`, `land(state, rng)`,
`use_item(state, item, target)`, `apply_minigame_result(state, ranking)`, `advance(state)`.
Every rule returns a list of **events** (`roll`, `move`, `tickets`, `goal`, `item`, `turn`,
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
Types: `start`, `blank`, `ticket` (+3), `lose` (−3), `heal` (+6 HP, never over the full bar),
`item` (draw one; the event space that teleported is gone, 2026-09-24), `goal` (the moving goal's spawn candidates carry `"goal": true`). A fork is any
space with two or more `next` entries. BOMBA BAY (`tools/gen_board.gd`, 2026-09-24) is Sean's drawing: the blue lines traced as
polylines in the drawing's pixels (0.115 m each), spaces every 3.7 m, every junction a shared
space, the arrows as the one-way directions (0.115 m a pixel): 127 spaces, 4 forks (the start, the F3 junction,
F2, F4), every space reaching every other. The file also carries the look's data: `slab` (the
moon chunk, a rounded hull of the spaces, `MoonSlab`), `annexes` (the rim angles of the two
domes), `shuttle` (the rocket) and `zones` (the blocks between the streets and a few spots in the
margin, a disc each with a kind and a yaw; the dressing builds a set-piece in each). Regenerate
with `tools/gen_board.gd`, then `tools/mark_spots.gd` flags the machine spots. Before it, the
same day, the board was a street district; before that (2026-09-23) a loop of 86 with four
short branches; the v0 board a hand-made loop of ~28 spaces.

## 4. Items

| Item | Effect | Counter |
|---|---|---|
| BOMB | Thrown: a ring of range (3 spaces) round you, a reticle where it lands; everyone within a space of the landing, you included, takes 20 HP at the centre falling to 8 at the edge and is shoved 3 spaces back; at 0 HP they drop half their tickets to you and respawn | Keep a space away; a SHIELD eats the hit |
| PORTAL | Pick a player: a portal opens ahead of you, you go through it to them and push them back through it to your space (the two of you swap) | Stand somewhere nobody wants |
| SHIELD | Passive, a glowing aura: eats the next bomb hit, damage space, laser hit or claw grab | It is spent by the first hit |
| CLAW | Aimed like the laser: the claw extends 3 spaces along its line and grabs one item at random from the first player in its path, or 3 tickets when their bar is empty; nothing in the path and it comes back empty, spent | Stay out of the line; a SHIELD eats the grab |
| LASER | Aimed with the mouse on your turn: a straight beam 3 spaces long; everyone in it loses HP by distance (all 30 within a space, 10 at the end); at 0 HP they drop half their tickets to the shooter and respawn at the other annex | Keep your distance; a SHIELD eats the hit |

Players carry **HP** (`board.hp`, 30) as well as tickets. HP is what the laser and the bomb take: a
downed player comes back at the machine spot that is not the live machine with full HP, and a
player under `board.bleed_below_hp` (10) bleeds until then. Items are strings in
`tuning/board.json`; the effect table lives in the rules. A new item is data + a rule branch + an
icon + a playback in the view, no new nodes. The HUD shows the inventory as a hotbar: Q opens it on your turn, 1–9 or the wheel
pick a slot, E (or a click on the slot) uses it; the laser then aims with the mouse and fires on
a click, the claw the same way and grabs, the bomb shows its ring of range and throws on a click,
right click puts any of them away; the portal picks a player.

## 5. Presentation (STYLE.md)

- Spaces are six-sided floating tiles (cel material by type: blank in the field colour, ticket
  in LEMON, lose in the danger red, item in LAGOON, goal in paper with a ring), ink outlines
  from the post pass, the swirl sky. Each special space's emblem is painted on the tile
  (2026-09-24): one pink ticket with a small golden maple leaf, a star for an item, a mine for
  damage, a med bag for the health spot; the safe spot keeps its dome, the start its flag. The board palette is its own map entry.
- Pawns are the same capsule-and-head silhouette as the arena, in identity colours, hopping
  space to space (`board.hop_seconds` per step) with a small burst on landing.
- Camera: third person behind and above the active pawn, easing between pawns on turn change,
  pulling back at forks so both branches are visible.
- HUD in the menu language: a turn strip of player cards (tickets, Bombas, items), the dice as a
  slammed numeral, the ROLL prompt, fork arrows (A/D or click), item buttons (1/2), round
  counter. Board music is the menu loop for now.
- Transitions: wipe into the minigame, slam back to the board. The view's first build of a match is chunked over
  frames under the held wipe (`BoardView.build_visuals`, 2026-09-23), like a minigame's look; it sleeps through
  the minigames and wakes after them.

## 6. What v0 does not do

No board camera control by the player, no shop, no more than two items, one board, no
mid-match join. Space effects are instant (no mini-events with UI). Bots use BOMB on the leader
with a ticket lead, TURBO whenever they have it.
