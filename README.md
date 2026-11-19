# AegisUpdate: Distributed Firmware Update Protocol Verifier

A device can truthfully report “I installed v2” after the fleet coordinator has already ordered a rollback to v1. Counting that report can leave a device on the bad version while the dashboard says rollback succeeded. AegisUpdate uses PlusCal and TLC to check the acknowledgment rule across the message orderings, installation steps, and faults allowed by a bounded fleet model.

```text
                      Image + Apply(epoch, version)
Coordinator  ---------------------------------------------->  device a, device b
             <----------------------------------------------
                      Installed or Fault(epoch, version)
                  independent, unordered device mailboxes

Staged -> RollingOut <-> Paused              trusted v1
             |              |                    |
             +----------+---+           receive Image and Apply in either order
             |          |                        |
         Completed  RollingBack              verify -> install -> atomic commit
                        |                                 |            |
                    RolledBack                      reboot / fault   report
An exhausted timeout retry can also move a running deployment to Failed.
```

## Run it

From the repository root, use Java 17, Python 3.8+, Make, and curl. The Python simulator uses the standard library. Install a Java 17 runtime if needed and confirm that `java -version` works, or set `JAVA` to the executable. The first setup downloads the pinned tools JAR and checks its SHA-256. [Java distributions](https://adoptium.net/temurin/releases/?version=17) · [TLA+ tools release](https://github.com/tlaplus/tlaplus/releases/tag/v1.7.4)

```sh
make setup
make translate                  # regenerate TLA+ from the embedded PlusCal
make check                      # all five corrected scenarios, one TLC worker
make safety                     # repeat invariants without fairness
make witnesses                  # require four named fault paths to be reachable
make unsafe                     # require TLC to violate SoundFinalization
make test
make demo                       # replay the same schedule under both rules
```

Select one configuration with `make check SCENARIO=normal`, `network`, `reboot`, `rollback`, or `offline` as the scenario value. To retain full logs, run `python3 tools/check.py verify --logs run-logs` after setup. For a direct default run, use `java -cp .tools/tla2tools.jar tlc2.TLC -workers 1 model/AegisUpdate.tla`. The four witness queries intentionally ask TLC to refute a “never reached” predicate. The runner distinguishes the expected named violation from a tool failure.

**Toolbox.** Download the archive for your OS, extract it, and launch the Toolbox. Create a specification with `model/AegisUpdate.tla` as its root module. Create a TLC model, select the temporal behavior formula `Spec`, and copy the constants, invariants, and properties from the desired scenario CFG into Model Overview. Enter `Devices` as a set of model values and `Victim` as the matching model value. Use one worker and leave deadlock checking enabled. The Make targets run the checked-in CFG files directly. [Toolbox installation](https://lamport.azurewebsites.net/tla/toolbox.html)

## Verification results

Observed with TLA+ tools v1.7.4, TLC 2.19, Java 17, breadth-first search, one worker, and no state constraints or symmetry reduction. Each corrected row passed all configured invariants and temporal properties. Each also passed a separate fairness-free invariant run with the same state count.

| Configuration | Distinct states | Search depth | Observed result |
|---|---:|---:|---|
| Normal | 248 | 20 | Every fair rollout completed |
| Duplicate / out-of-order | 580 | 21 | Every fair rollout completed, including duplicate Apply delivery before Image |
| Installation reboot | 679 | 26 | Terminal progress passed. A reboot followed by successful completion was reachable |
| Installation failure / rollback | 1,137 | 33 | Every fair rollout reached RolledBack |
| Offline / retry | 1,851 | 23 | Terminal progress passed. Retry exhaustion reached Failed |
| Unsafe acknowledgment rule | 1,087 at cutoff | 24 | TLC stopped at a SoundFinalization violation, with 79 states still queued |

Three simulator tests check early action rejection, recovery of the corrected schedule, and the correspondence of selected fields at every state of the saved counterexample. The simulator implements the rollback trace vocabulary. TLC explores the full specification. [Captured behavior](examples/stale-report.tlc.txt) · [Replay tests](tests/test_replay.py)

## Scope

All devices are required. Each starts on trusted v1. One coordinator can issue v2 and then authorize v1 in a fresh epoch. Mailboxes hold at most two distinct packets per direction **per device**. Scenarios isolate fault classes and allow one pause, a bounded disruption, and one retry per device per epoch. Weak fairness applies to the combined next-state action. These bounds limit how long other events can postpone an enabled operation. Explicit failure ends the rollout and cancels outstanding progress obligations.

The signature predicate abstracts a trusted mapping from version to image. The model assumes authenticated participants, a durable activation record, and an atomic image switch. It omits real clocks, flash writes, key management, coordinator crashes, and faults after termination. State counts apply to the supplied constants. This independent educational protocol uses no proprietary firmware or NVMe material. [Architecture](docs/architecture.md) · [Property definitions and assumptions](docs/properties.md)

## Interview walkthrough

1. Draw the two mailboxes. Explain how a correct report can arrive after its rollout epoch ends.
2. Show `Good(d)` and `SoundFinalization`. The coordinator finalizes from its reports. The checker inspects durable device state independently.
3. Run `make demo`. At state 16 the unsafe handler counts an epoch-1 report toward epoch 2. At state 24 device a still runs v2. The fix matches sender, epoch, and target before counting the report. [Trace walkthrough](docs/counterexample.md)
4. Explain why termination alone is weak. An implementation that immediately fails every rollout could satisfy it. The normal model separately requires successful completion, and the rollback model requires a return to baseline.
5. Discuss what changes with unbounded retries or a second rollout of the same version. The former reopens the fairness argument. The latter makes epoch identity essential even when versions match. [Interviewer questions](docs/properties.md#interviewer-review)
