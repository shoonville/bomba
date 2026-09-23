# Local patches to netfox v1.35.3

Keep this list current. Re-apply when upgrading netfox, or drop a patch once upstream has it.

1. **Recorder: no state copies for unsimulated ticks** — `rollback/composite/rollback-history-recorder.gd`
   (`_should_record_tick`, `set_simulated_this_tick`) and `rollback/rollback-synchronizer.gd`
   (`_on_record_tick`). Unpatched, a node in pure state playback (a remote player on a client
   with `enable_input_broadcast = false`) has the last applied state re-recorded under every new
   tick; when a newer state arrives, `get_history(display_tick)` still finds the stale copy, so
   the displayed position lags by whole tick loops. Measured in BOMBA's soak as a 0.9–1.2 m mean
   error in the client's view of remote players before the patch. Candidate for upstream.

2. **Recorder: display never lags the newest known state** — `rollback/composite/rollback-history-recorder.gd`
   (`apply_display_state`). Unpatched, when a peer's clock runs behind the state owner's, received
   states are stamped with ticks greater than `display_tick`; `_HistoryBuffer.get_closest_tick`
   then returns the *earliest* entry, so a remote player freezes at the first state received after
   the clocks crossed. Measured in BOMBA's soak: a bot frozen for 300+ ticks on the client while the
   host moved it 10 m. Displaying `max(display_tick, latest_state_tick)` fixes it. Candidate for
   upstream.

3. **Diff encoder: empty diffs are stored, missing references are refused** — `encoder/diff-history-encoder.gd`
   (`apply`). Unpatched, an empty diff (state unchanged since the reference) returns true without
   storing anything, the receiver acknowledges that tick, the sender then references it, and the
   receiver — which never stored it — merges the next diff into an empty snapshot; the partial
   snapshot then shadows good history for every later tick. Measured in BOMBA's soaks as bursts of
   "Reference tick missing" warnings (38–87 per 45 s run). Now an empty diff stores a copy of the
   reference at its tick, and a diff whose reference is missing is dropped (not acknowledged) so the
   next full state resyncs. Candidate for upstream.

4. **Transmitter: state send interval** — `rollback/composite/rollback-history-transmitter.gd`
   (`transmit_state`), new project setting `netfox/rollback/state_send_interval` (default 1 =
   upstream behaviour). With 2, non-full state ticks are sent every second tick (30 Hz at a 60 Hz
   simulation), which is the snapshot rate `DESIGN.md` §3 asks for and halves host upload. Full
   states keep their own interval. Clients receive a state at most one tick older than before.
   Needed to stay under a noray relay's default 128 kB/s per-relay cap, which the public relay
   enforces by throwing inside its UDP handler (the process dies). Candidate for upstream.

5. **Transmitter: one state per node per loop, its newest simulated tick** — `rollback/composite/rollback-history-transmitter.gd`
   (`transmit_state` keeps the candidate, `conclude_tick_loop` sends it). Unpatched, every
   resimulated tick transmits its own state: with three clients at 120 ms RTT the host
   resimulated ~7 ticks a loop and sent each node's state 3–4 times per loop (measured in
   BOMBA's six-seat soak as 260 state properties per loop for six nodes and 113 KB/s of host
   upload per client, at a relay's 128 kB/s cap). A peer only needs the newest authoritative
   state to roll back to; older ticks in the same loop are superseded by it. It has to be the
   node's own newest *simulated* tick, not the loop's newest: a client's player is not
   simulated on the server at the newest ticks (its input is still in flight), and a first
   version that sent only the loop's newest tick never sent that player at all (its client
   rolled back the whole 128-tick window every loop). Patch #4's decimation now counts ticks
   since the last send instead of tick parity, so a loop that covers two ticks cannot starve a
   peer. After (six seats, `bad`): 30 KB/s per client, 263 packets/s, clients unchanged or
   better (misprediction 3–6 mm, hit confirmation 0.71–1.11, death lag ≤ 8 ticks, no outages).
   Candidate for upstream.

6. **RewindableAction: broadcast on change or every 4th loop** — `rewindable-action.gd`
   (`set_active`, `_after_loop`). Unpatched, the authority broadcasts the action's tickset every
   loop in which `set_active` was called at all, which a per-tick weapon does every tick: six
   actions × 60 loops/s × ~50 B = 18 KB/s per client. Now a real change (a tick added to or
   removed from the set) sends at once, and otherwise every 4th loop (15 Hz) keeps the peers'
   "last known tick" moving so a prediction the authority never confirmed still cancels within
   ~70 ms. Candidate for upstream.

7. **Synchronizer: no per-tick state apply for pure-playback nodes** — `rollback/rollback-synchronizer.gd`
   (`_on_prepare_tick`, `_is_playback_only`). Unpatched, every synchronizer applies its node's
   state (and input) history for every tick of the rollback loop, including nodes this peer
   owns nothing of and never simulates: on a client with input broadcast off that is every
   other player. With six seats a client applied 5 nodes × ~12 resimulated ticks × 34
   properties per loop through `set_indexed`, and its tick loop measured 11–13 ms p95 on a
   Ryzen 9800X3D. Such a node now skips the per-tick apply (and the simset gathering, which
   was empty for it anyway) and only gets the display state at the end of the loop, as before.
   A mutated node (predicted damage on the authority) is never skipped. Candidate for upstream.

8. **Transmitter: the authority's latest state tick is the newest simulated tick, not the last
   sent one** — `rollback/composite/rollback-history-transmitter.gd` (`transmit_state` advances
   `_latest_state_tick`; `_flush_state` decimates from a separate `_last_sent_state_tick`).
   Patches #4 and #5 had left `_latest_state_tick` on the last *sent* tick, so on alternate loops
   it lagged the simulation by one tick and `_notify_resim` (which starts an input owner's
   resimulation from its latest state) made the host restart every other rollback loop at a tick
   it had already simulated. In that tick only the nodes netfox considers mutated run again (every
   node whose RewindableAction has an active tick in the window, i.e. every recent shooter), the
   others are re-applied from history: a shooter re-fired into a victim's pre-hit state, the
   victim's death hook did not run, and the record for the next tick overwrote both players'
   counters with pre-death values. Measured in BOMBA's headless LAST STAND stress (five bots,
   eight rounds) as a lost kill or death in six of eight rounds, and in Sean's 2026-09-18 match as
   a kill the feed showed and the score did not. With the patch a pure host never re-simulates a
   tick; the kill and death counters were also taken out of the rollback state (BOMBA's own
   change), since a host with lagging clients still re-simulates partially. Candidate for upstream.

9. **Synchronizer: one process_settings() per spawn** — `rollback/rollback-synchronizer.gd`
   (`_settings_processed`, `_process_settings_if_pending`). Unpatched, a node's settings were
   processed three times when it entered the tree: the game's own `process_settings()` once the
   authority is set (BOMBA's player does this), then the deferred calls from `_enter_tree` and
   `_ready`, each a full rebuild of the property cache, the freshness store and the node set:
   2.9 ms per player in BOMBA, eight redundant calls per four-seat match landing on the frame
   of the switch (23 ms of a 54 ms frame, 2026-09-22). The deferred calls now skip when settings
   were processed since the node entered the tree; a node that never calls `process_settings()`
   itself behaves as before. Candidate for upstream.
