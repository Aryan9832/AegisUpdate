# Protocol architecture

The coordinator owns one deployment and a fixed required fleet. Epoch 1 approves the candidate. Epoch 2 revokes future epoch-1 work at each device as that device accepts the rollback command. A device can legitimately activate v2 before learning that the coordinator has begun rollback. Rollback completion therefore requires positive evidence from every device.

## State ownership

| Owner | Variables | Meaning |
|---|---|---|
| Coordinator | `phase, epoch, issued, accepted, tries` | The staged manifest becomes eligible for distribution at begin. Each epoch has its own issued/acknowledged devices and retry budget. The phase selects the permitted control actions. |
| Device | `active, commit, fence` | Durable active version, its activation epoch, and highest accepted Apply epoch. Epoch zero denotes the trusted initial image. |
| Device | `image, step` | Staged image epoch and volatile work state. Receipt and authorization can arrive in either order. Receiving an image alone leaves the device Idle. |
| Checker | `received, verified, installed` | Monotone histories of epoch/version pairs in each device record. Protocol decisions never consult them. They let properties compare a report with earlier device events. |
| Transport | `down[d], up[d]` | Independent unordered sets of immutable message tuples. The mailbox identifies the device. The tuple contains kind, epoch, and version. |
| Environment | `online, pausedOnce, duplicated, rebooted, disconnected` | Connectivity and scenario budgets. These flags bound nondeterminism and support reachability queries. |

`Version(e)` fixes each epoch's target. The model represents the image by that identity and abstracts successful cryptographic verification as membership in `Signed`. All distributed images in the supplied runs are signed. Separating delivery, verification, approval, and activation still allows TLC to check their ordering.

## Atomic actions

Read the PlusCal above the generated translation. The single `Tick` label executes **one** nondeterministically chosen enabled event. The inner `with d` chooses one device. TLC can interleave two devices at each receive, verify, install, or commit boundary. In the translation, `Tick` is a disjunction of guarded updates with explicit `UNCHANGED` clauses. `Init` creates the fleet, `Next` adds terminal stuttering, and `Spec` supplies fairness. The dispatcher is a compact representation of interleaving concurrency. It gives no participant a global lock that spans an entire installation.

- **Distribution.** The coordinator enqueues Image and Apply as one batch for one device. Delivery order is independent. A device retains a newer staged image for a matching approval and ignores obsolete work once fenced. A second copy of Apply has no effect on a previously accepted epoch. The network scenario retains one delivered Apply for redelivery before or after other packets.
- **Installation.** Verification needs matching image and fence. Installation can then begin. Successful commit atomically switches the active version, records the epoch, and makes the Installed report available for asynchronous delivery. This abstracts a durable outbox. The model omits a crash between activation and recording the report.
- **Pause.** A pause stops fresh dispatch, retries, and finalization. Work in flight can continue. Resume reopens dispatch. A fault report can take a paused rollout directly into rollback.
- **Reboot and timeout.** Reboot interrupts the victim while Installing, clears its image and enters Recovering. The earlier committed version and fence survive. A timeout can reissue the current batch, and receipt of its image permits verification again. A second timeout can exhaust the budget before recovery, explicitly failing the deployment.
- **Connectivity.** A disconnect stalls delivery to that device and its local work. Already emitted reports remain deliverable. The environment may reconnect the device or allow the coordinator to time out. Timeout eligibility uses an environmental restriction to stalled devices. A real coordinator observes silence and can also time out a healthy but slow device.
- **Rollback.** In the rollback configuration, device b fails its epoch-1 install. Its Fault report opens epoch 2 and clears the accepted and issued sets. Messages already in the network survive the transition. Every required device, even one already on v1, must confirm the new epoch. A queued old report can arrive before the new dispatch.
- **Finalization.** The coordinator tests `accepted = Devices`. The checker independently checks each active version, durable commit epoch, and device work state. A disconnected device can be safe if it already committed the target and its report is in flight.

## Bounds and extensions

A single batch occupies at most two downward slots per device. Equal packets coalesce in the set. The designated duplicate delivery retains an existing packet once. Upward packets may contain a report from each epoch. The network preserves buffered messages except that timeout reissue replaces the pending downward batch. The model has no arbitrary packet-loss action. A single pause, reboot, duplicate, or offline interval keeps the graph small. Fault classes are selected per run. Compound fault schedules and repeated upgrades would require new configurations and new verification results.

A larger fleet can be explored by editing `Devices` while keeping `Victim` a member. Preserving safety with arbitrarily many devices would require a separate proof. An implementation with durable flash metadata would also need a refinement argument connecting its writes to this model's atomic commit.
