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
