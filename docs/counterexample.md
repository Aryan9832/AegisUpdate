# A truthful stale report completes the wrong deployment

Run `make unsafe` to ask TLC for a violating behavior. Then run `make demo` to replay the captured schedule with each acceptance rule. The unsafe CFG differs from the corrected rollback CFG in exactly one Boolean. Both use the same model, fault injection, constants, and checked properties.

| TLC states | Coordinator and devices |
|---|---|
| 1–8 | The coordinator opens epoch 1. Device a receives v2, verifies it, installs it, and queues Installed(a,1,v2). Its report remains in transit. |
| 9–14 | Device b receives the candidate and fails while installing. Its active image is still v1. |
| 15 | The coordinator receives b's Fault report and opens rollback epoch 2. Accepted and issued sets are empty. |
| 16 | The delayed report from a arrives. The unsafe handler adds a to the current accepted set. At this point a has received no rollback command. |
| 17–23 | Device b receives and commits the epoch-2 target and sends its matching Installed report. Both devices now appear in the coordinator's accepted set. |
| 24 | Finalization is enabled. The coordinator declares RolledBack, but a is Active at v2 with commit epoch 1. TLC reports a SoundFinalization violation. |

The bug is in **consumption** of a report. Its signature, sender, and historical installation evidence can all be valid. Clearing the accepted set on rollback cannot remove a stale report that is still in transit.

The corrected handler takes the sender from its authenticated mailbox and requires both `p[2] = epoch` and `p[3] = Version(epoch)` before adding that sender. Under the same schedule, it discards a's stale report at state 16. At the attempted final step the coordinator is still waiting for a. The unit test continues by sending epoch 2 to a, committing v1 there, and consuming its fresh report. Only then can rollback complete.

[Captured TLC states and search footer](../examples/stale-report.tlc.txt) · [Replay schedule](../examples/stale-report.trace) · [Corrected scenario](../model/scenarios/rollback.cfg)

## Reproduction details

The captured text is the TLC invariant diagnostic through the end of its output, with the machine-specific startup banner omitted. The trace file lists its 23 events in order. The replay test compares both devices' active versions, commit epochs, fences, staged image epochs, and work states, plus coordinator phase, epoch, and accepted set, at each of the 24 states. Different TLC versions or traversal orders can select another valid witness.

The replay command returns 1 when the safety check fails, 2 when the fixed protocol blocks the scheduled action, and 0 after a fully enabled safe schedule. The demo expects the first two outcomes. For new exhaustive evidence, run the CFGs through TLC.
