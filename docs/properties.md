# Safety, progress, and evidence

The default configuration lists the operators TLC evaluates. The runner also checks the invariant list under `SafetySpec == Init /\ [][Next]_vars`. That check explores transitions without a fairness premise. The two action properties below are checked by the temporal runs.

| Operator | Interpretation |
|---|---|
| `TypeOK` | Checks core phase, identifiers, version and epoch ranges, device state tags, retry bounds, and mailbox capacity. |
| `AuthorizedActivation` | The initial record names trusted v1. Every later active record must match a locally verified epoch/version pair, the manifest target, and an accepted epoch. The persistent fence permits a device to continue running its previous commit while preparing rollback. |
| `TruthfulReport` | Each buffered Installed report must match local receipt and commit evidence from that device. TLC inspects the post-emission state even when the next event consumes the report. |
| `RollbackBound`, `RollbackFence` | An epoch-2 commit cannot exceed the approved rollback target. After local acceptance of epoch 2, any change in active version must respect that bound. |
| `Consistent`, `Durability` | Verified and Installing states require matching staged and authorized epochs and verification evidence. Active requires agreement between commit and fence. Each transition preserves fence monotonicity and entry into Recovering preserves the active record. |
| `SoundFinalization` | Both successful terminal phases imply that every required device has committed the current epoch, runs its target, and is Active. The guard used by the coordinator only inspects its acknowledgment set. |

The epoch and version fields are correlated by the two-entry manifest. Consequently these runs cannot distinguish every possible partial fix. For example, comparing only versions also rejects an old v2 report in the demonstrated v1 rollback. A third epoch targeting a previously deployed version would distinguish that rule from full epoch matching.

## Liveness

The translator emits `WF_vars(Next)` for the fair dispatcher. If a state-changing step remains enabled continuously, the system must eventually take a step. This formula allows finite delays and imposes no independent delivery deadline. Progress depends on the structure of these particular finite runs. Each competing pause, disconnection, duplicate, and retry has a bounded budget. Epochs advance once, installs advance through finite stages, and the environment cannot keep generating distracting traffic. After a pause, other enabled work can drain, leaving resume enabled. Finiteness alone would still allow an infinite cycle. TLC checks the temporal properties on the resulting graph.

- `Terminates` requires eventual entry into Completed, RolledBack, or Failed, even from the initial staged state. Terminal states are absorbing.
- `Converges` fixes a device and an epoch. If the epoch eventually stays current, the device stays online, its installation is healthy for that epoch, and the deployment remains authorized (no explicit failure), it eventually stays committed at the matching target. A locally healthy peer can lose its deployment obligation when another device causes fleet-wide cancellation. The formula intentionally excludes that case.
- `Succeeds` requires every fair normal or network behavior to reach Completed. `ReturnsToBaseline` requires every fair injected-install-failure behavior to reach RolledBack. The reboot and offline configurations admit explicit failure, so they check terminal progress and conditional convergence.

## Checking that faults actually happen

`make witnesses` adds one negated reachability invariant at a time, uses the fairness-free specification, and requires the named TLC invariant error. The network witness consumes the retained Apply while the victim still has empty receipt history. The reboot witness requires both a recorded installation reboot and Completed. The rollback witness reaches RolledBack after the only rollback trigger, the injected install fault. The offline witness reaches Failed after exhausting the retry. These are existential witnesses. A successful recovery witness alone would say nothing about other fault schedules.

## Interviewer review

| Likely question | What to explain |
|---|---|
| How can every report be truthful and the final result still be wrong? | Local evidence means the event occurred. Epoch matching determines whether that event fulfills the current deployment obligation. Replay states 15 and 16. |
| Could the model pass by never starting or by always failing? | Weak fairness rules out permanent initial stuttering. Normal and rollback configurations require specific successful outcomes. The fault witnesses independently establish reachability. |
| What would break with unbounded disconnects? | Repeated disconnects could indefinitely preempt delivery. Progress would need an eventual-reachability condition and scheduling assumptions about the individual delivery and device actions. |
| What does “signed” buy here? | The trusted predicate and manifest identify valid images. The supplied traffic contains valid signatures. Key compromise, invalid-byte handling, and cryptographic verification require different evidence. |
| Why only two devices? | One can succeed while the other fails and triggers rollback. This is enough for the demonstrated bug. Scaling the fleet and fault combinations is a separate experiment. |
| Does replay establish implementation equivalence? | Tests compare observable fields along one TLC trace. The simulator covers that rollback schedule and its corrected continuation. General refinement and hardware behavior remain open. |

A defensible résumé claim is “Modeled a two-device firmware rollout in PlusCal, checked safety and conditional liveness with TLC across five bounded scenarios, and reproduced a stale-acknowledgment counterexample.” Be prepared to derive the fairness premise and identify which assumptions make that claim possible.
