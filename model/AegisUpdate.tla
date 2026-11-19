---------------------------- MODULE AegisUpdate ----------------------------
EXTENDS Naturals, FiniteSets, TLC
CONSTANTS Devices, Victim, Scenario, Unsafe, Signed, MaxRetries
ASSUME /\ Devices # {} /\ Victim \in Devices /\ MaxRetries \in Nat
       /\ Scenario \in {"normal","network","reboot","rollback","offline"}
       /\ Unsafe \in BOOLEAN /\ Signed \subseteq {1,2} /\ 1 \in Signed
Epochs == {1,2}
Version(e) == IF e = 1 THEN 2 ELSE 1
Terminal == {"Completed","RolledBack","Failed"}
Packet(kind,e) == <<kind,e,Version(e)>>
Batch(e) == {Packet("Image",e),Packet("Apply",e)}
InitialDevice == [active |-> 1, commit |-> 0, fence |-> 0, image |-> 0,
                  step |-> "Idle", received |-> {}, verified |-> {}, installed |-> {}]

(* --fair algorithm Fleet
variables phase = "Staged", epoch = 1,
  device = [d \in Devices |-> InitialDevice],
  down = [d \in Devices |-> {}], up = [d \in Devices |-> {}],
  issued = {}, accepted = {}, tries = [d \in Devices |-> 0],
  online = Devices, pausedOnce = FALSE, rebooted = FALSE, duplicated = FALSE, disconnected = FALSE;

define
  Running == phase \in {"RollingOut","RollingBack"}
  Good(d) == /\ device[d].active = Version(epoch)
             /\ device[d].commit = epoch /\ device[d].step = "Active"
end define;

begin
Tick:
  while phase \notin Terminal do
    either
      await phase = "Staged";
      phase := "RollingOut";
    or
      await Running /\ accepted = Devices;
      phase := IF epoch = 1 THEN "Completed" ELSE "RolledBack";
    or
      await phase = "RollingOut" /\ ~pausedOnce;
      phase := "Paused"; pausedOnce := TRUE;
    or
      await phase = "Paused";
      phase := "RollingOut";
    or
      with d \in Devices do
        either
          await Running /\ d \notin issued /\ down[d] = {};
          issued := issued \cup {d}; down[d] := Batch(epoch);
        or
          with p \in down[d] do
            await d \in online;
            either
              down[d] := down[d] \ {p};
            or
              await Scenario = "network" /\ ~duplicated /\ d = Victim
                    /\ p[1] = "Apply" /\ device[d].received = {};
              duplicated := TRUE;
            end either;
            if p[1] = "Image" then
              with old = device[d], replace = p[2] >= device[d].fence /\ p[2] > device[d].commit do
                device[d] := [old EXCEPT !.received = @ \cup {<<p[2],p[3]>>},
                  !.image = IF replace THEN p[2] ELSE @,
                  !.step = IF replace /\ old.image # p[2] THEN "Idle" ELSE @];
              end with;
            elsif p[2] > device[d].fence then
              device[d] := [device[d] EXCEPT !.fence = p[2], !.step = "Idle",
                !.image = IF @ = p[2] THEN @ ELSE 0];
            end if;
          end with;
        or
          await d \in online /\ device[d].step = "Idle"
                /\ device[d].image # 0 /\ device[d].image = device[d].fence
                /\ Version(device[d].image) \in Signed;
          device[d] := [device[d] EXCEPT !.verified = @ \cup {<<device[d].image,Version(device[d].image)>>},
            !.step = "Verified"];
        or
          await d \in online /\ device[d].step = "Verified";
          device[d].step := "Installing";
        or
          await d \in online /\ device[d].step = "Installing";
          if Scenario = "rollback" /\ d = Victim /\ device[d].fence = 1 then
            device[d].step := "Fault";
            up[d] := up[d] \cup {Packet("Fault",1)};
          else
            with e = device[d].fence, v = Version(device[d].image) do
              device[d] := [device[d] EXCEPT !.active = v, !.commit = e,
                !.installed = @ \cup {<<e,v>>}, !.step = "Active"];
              up[d] := up[d] \cup {<<"Installed",e,v>>};
            end with;
          end if;
        or
          with p \in up[d] do
            up[d] := up[d] \ {p};
            if p[1] = "Installed" then
              if Unsafe \/ (p[2] = epoch /\ p[3] = Version(epoch)) then
                accepted := accepted \cup {d};
              end if;
            elsif p[2] = epoch then
              phase := "RollingBack"; epoch := 2; accepted := {}; issued := {};
              tries := [i \in Devices |-> 0];
            end if;
          end with;
        or
          await Scenario = "reboot" /\ d = Victim /\ ~rebooted
                /\ device[d].step = "Installing";
          device[d] := [device[d] EXCEPT !.step = "Recovering", !.image = 0];
          rebooted := TRUE;
        or
          await Scenario = "offline" /\ d = Victim /\ ~disconnected /\ d \in issued;
          online := online \ {d}; disconnected := TRUE;
        or
          await d \notin online;
          online := online \cup {d};
        or
          \* Environment supplies a timeout while a required device is stalled.
          await Running /\ d \in issued \ accepted
                /\ (d \notin online \/ device[d].step = "Recovering");
          if tries[d] < MaxRetries then
            tries[d] := tries[d] + 1; down[d] := Batch(epoch);
          else
            phase := "Failed";
          end if;
        end either;
      end with;
    end either;
  end while;
end algorithm; *)
\* BEGIN TRANSLATION (chksum(pcal) = "e5f8448a" /\ chksum(tla) = "1ffc5500")
VARIABLES phase, epoch, device, down, up, issued, accepted, tries, online, 
          pausedOnce, rebooted, duplicated, disconnected, pc

(* define statement *)
Running == phase \in {"RollingOut","RollingBack"}
Good(d) == /\ device[d].active = Version(epoch)
           /\ device[d].commit = epoch /\ device[d].step = "Active"


vars == << phase, epoch, device, down, up, issued, accepted, tries, online, 
           pausedOnce, rebooted, duplicated, disconnected, pc >>

Init == (* Global variables *)
        /\ phase = "Staged"
        /\ epoch = 1
        /\ device = [d \in Devices |-> InitialDevice]
        /\ down = [d \in Devices |-> {}]
        /\ up = [d \in Devices |-> {}]
        /\ issued = {}
        /\ accepted = {}
        /\ tries = [d \in Devices |-> 0]
        /\ online = Devices
        /\ pausedOnce = FALSE
        /\ rebooted = FALSE
        /\ duplicated = FALSE
        /\ disconnected = FALSE
        /\ pc = "Tick"

Tick == /\ pc = "Tick"
        /\ IF phase \notin Terminal
              THEN /\ \/ /\ phase = "Staged"
                         /\ phase' = "RollingOut"
                         /\ UNCHANGED <<epoch, device, down, up, issued, accepted, tries, online, pausedOnce, rebooted, duplicated, disconnected>>
                      \/ /\ Running /\ accepted = Devices
                         /\ phase' = (IF epoch = 1 THEN "Completed" ELSE "RolledBack")
                         /\ UNCHANGED <<epoch, device, down, up, issued, accepted, tries, online, pausedOnce, rebooted, duplicated, disconnected>>
                      \/ /\ phase = "RollingOut" /\ ~pausedOnce
                         /\ phase' = "Paused"
                         /\ pausedOnce' = TRUE
                         /\ UNCHANGED <<epoch, device, down, up, issued, accepted, tries, online, rebooted, duplicated, disconnected>>
                      \/ /\ phase = "Paused"
                         /\ phase' = "RollingOut"
                         /\ UNCHANGED <<epoch, device, down, up, issued, accepted, tries, online, pausedOnce, rebooted, duplicated, disconnected>>
                      \/ /\ \E d \in Devices:
                              \/ /\ Running /\ d \notin issued /\ down[d] = {}
                                 /\ issued' = (issued \cup {d})
                                 /\ down' = [down EXCEPT ![d] = Batch(epoch)]
                                 /\ UNCHANGED <<phase, epoch, device, up, accepted, tries, online, rebooted, duplicated, disconnected>>
                              \/ /\ \E p \in down[d]:
                                      /\ d \in online
                                      /\ \/ /\ down' = [down EXCEPT ![d] = down[d] \ {p}]
                                            /\ UNCHANGED duplicated
                                         \/ /\ Scenario = "network" /\ ~duplicated /\ d = Victim
                                               /\ p[1] = "Apply" /\ device[d].received = {}
                                            /\ duplicated' = TRUE
                                            /\ down' = down
                                      /\ IF p[1] = "Image"
                                            THEN /\ LET old == device[d] IN
                                                      LET replace == p[2] >= device[d].fence /\ p[2] > device[d].commit IN
                                                        device' = [device EXCEPT ![d] =            [old EXCEPT !.received = @ \cup {<<p[2],p[3]>>},
                                                                                        !.image = IF replace THEN p[2] ELSE @,
                                                                                        !.step = IF replace /\ old.image # p[2] THEN "Idle" ELSE @]]
                                            ELSE /\ IF p[2] > device[d].fence
                                                       THEN /\ device' = [device EXCEPT ![d] =            [device[d] EXCEPT !.fence = p[2], !.step = "Idle",
                                                                                               !.image = IF @ = p[2] THEN @ ELSE 0]]
                                                       ELSE /\ TRUE
                                                            /\ UNCHANGED device
                                 /\ UNCHANGED <<phase, epoch, up, issued, accepted, tries, online, rebooted, disconnected>>
                              \/ /\ d \in online /\ device[d].step = "Idle"
                                    /\ device[d].image # 0 /\ device[d].image = device[d].fence
                                    /\ Version(device[d].image) \in Signed
                                 /\ device' = [device EXCEPT ![d] =            [device[d] EXCEPT !.verified = @ \cup {<<device[d].image,Version(device[d].image)>>},
                                                                    !.step = "Verified"]]
                                 /\ UNCHANGED <<phase, epoch, down, up, issued, accepted, tries, online, rebooted, duplicated, disconnected>>
                              \/ /\ d \in online /\ device[d].step = "Verified"
                                 /\ device' = [device EXCEPT ![d].step = "Installing"]
                                 /\ UNCHANGED <<phase, epoch, down, up, issued, accepted, tries, online, rebooted, duplicated, disconnected>>
                              \/ /\ d \in online /\ device[d].step = "Installing"
                                 /\ IF Scenario = "rollback" /\ d = Victim /\ device[d].fence = 1
                                       THEN /\ device' = [device EXCEPT ![d].step = "Fault"]
                                            /\ up' = [up EXCEPT ![d] = up[d] \cup {Packet("Fault",1)}]
                                       ELSE /\ LET e == device[d].fence IN
                                                 LET v == Version(device[d].image) IN
                                                   /\ device' = [device EXCEPT ![d] =            [device[d] EXCEPT !.active = v, !.commit = e,
                                                                                      !.installed = @ \cup {<<e,v>>}, !.step = "Active"]]
                                                   /\ up' = [up EXCEPT ![d] = up[d] \cup {<<"Installed",e,v>>}]
                                 /\ UNCHANGED <<phase, epoch, down, issued, accepted, tries, online, rebooted, duplicated, disconnected>>
                              \/ /\ \E p \in up[d]:
                                      /\ up' = [up EXCEPT ![d] = up[d] \ {p}]
                                      /\ IF p[1] = "Installed"
                                            THEN /\ IF Unsafe \/ (p[2] = epoch /\ p[3] = Version(epoch))
                                                       THEN /\ accepted' = (accepted \cup {d})
                                                       ELSE /\ TRUE
                                                            /\ UNCHANGED accepted
                                                 /\ UNCHANGED << phase, epoch, 
                                                                 issued, tries >>
                                            ELSE /\ IF p[2] = epoch
                                                       THEN /\ phase' = "RollingBack"
                                                            /\ epoch' = 2
                                                            /\ accepted' = {}
                                                            /\ issued' = {}
                                                            /\ tries' = [i \in Devices |-> 0]
                                                       ELSE /\ TRUE
                                                            /\ UNCHANGED << phase, 
                                                                            epoch, 
                                                                            issued, 
                                                                            accepted, 
                                                                            tries >>
                                 /\ UNCHANGED <<device, down, online, rebooted, duplicated, disconnected>>
                              \/ /\ Scenario = "reboot" /\ d = Victim /\ ~rebooted
                                    /\ device[d].step = "Installing"
                                 /\ device' = [device EXCEPT ![d] = [device[d] EXCEPT !.step = "Recovering", !.image = 0]]
                                 /\ rebooted' = TRUE
                                 /\ UNCHANGED <<phase, epoch, down, up, issued, accepted, tries, online, duplicated, disconnected>>
                              \/ /\ Scenario = "offline" /\ d = Victim /\ ~disconnected /\ d \in issued
                                 /\ online' = online \ {d}
                                 /\ disconnected' = TRUE
                                 /\ UNCHANGED <<phase, epoch, device, down, up, issued, accepted, tries, rebooted, duplicated>>
                              \/ /\ d \notin online
                                 /\ online' = (online \cup {d})
                                 /\ UNCHANGED <<phase, epoch, device, down, up, issued, accepted, tries, rebooted, duplicated, disconnected>>
                              \/ /\ Running /\ d \in issued \ accepted
                                    /\ (d \notin online \/ device[d].step = "Recovering")
                                 /\ IF tries[d] < MaxRetries
                                       THEN /\ tries' = [tries EXCEPT ![d] = tries[d] + 1]
                                            /\ down' = [down EXCEPT ![d] = Batch(epoch)]
                                            /\ phase' = phase
                                       ELSE /\ phase' = "Failed"
                                            /\ UNCHANGED << down, tries >>
                                 /\ UNCHANGED <<epoch, device, up, issued, accepted, online, rebooted, duplicated, disconnected>>
                         /\ UNCHANGED pausedOnce
                   /\ pc' = "Tick"
              ELSE /\ pc' = "Done"
                   /\ UNCHANGED << phase, epoch, device, down, up, issued, 
                                   accepted, tries, online, pausedOnce, 
                                   rebooted, duplicated, disconnected >>

(* Allow infinite stuttering to prevent deadlock on termination. *)
Terminating == pc = "Done" /\ UNCHANGED vars

Next == Tick
           \/ Terminating

Spec == /\ Init /\ [][Next]_vars
        /\ WF_vars(Next)

Termination == <>(pc = "Done")

\* END TRANSLATION 
TypeOK ==
  /\ phase \in Terminal \cup {"Staged","RollingOut","Paused","RollingBack"}
  /\ epoch \in Epochs /\ accepted \subseteq Devices /\ issued \subseteq Devices
  /\ online \subseteq Devices /\ tries \in [Devices -> 0..MaxRetries]
  /\ \A d \in Devices:
       /\ device[d].active \in {1,2} /\ device[d].fence \in 0..2
       /\ device[d].image \in 0..2 /\ device[d].commit \in 0..2
       /\ device[d].step \in {"Idle","Verified","Installing","Fault","Active","Recovering"}
       /\ Cardinality(down[d]) <= 2 /\ Cardinality(up[d]) <= 2
AuthorizedActivation == \A d \in Devices:
  IF device[d].commit = 0 THEN device[d].active = 1
  ELSE /\ <<device[d].commit,device[d].active>> \in device[d].verified
       /\ device[d].active = Version(device[d].commit)
       /\ device[d].commit <= device[d].fence
TruthfulReport == \A d \in Devices: \A p \in up[d]: p[1] = "Installed" =>
  /\ <<p[2],p[3]>> \in device[d].received /\ <<p[2],p[3]>> \in device[d].installed
RollbackBound == \A d \in Devices: device[d].commit = 2 => device[d].active <= Version(2)
Consistent == \A d \in Devices:
  /\ (device[d].step \in {"Verified","Installing"} =>
      /\ device[d].image = device[d].fence
      /\ <<device[d].image, Version(device[d].image)>> \in device[d].verified)
  /\ (device[d].step = "Active" => device[d].commit = device[d].fence)
SoundFinalization == phase \in {"Completed","RolledBack"} => \A d \in Devices: Good(d)
Terminates == <>(phase \in Terminal)
Succeeds == <>(phase = "Completed")
Converges == \A d \in Devices: \A e \in Epochs:
  (<>[](epoch = e /\ d \in online /\ phase # "Failed"
        /\ ~(Scenario = "rollback" /\ d = Victim /\ e = 1)))
  => <>[](device[d].commit = e /\ device[d].active = Version(e))
RollbackFence == [][\A d \in Devices:
  device[d].fence = 2 /\ device'[d].active # device[d].active =>
  device'[d].active <= Version(2)]_vars
Durability == [][\A d \in Devices:
  /\ device'[d].fence >= device[d].fence
  /\ (device'[d].step = "Recovering" =>
      /\ device'[d].commit = device[d].commit /\ device'[d].active = device[d].active)]_vars
ReturnsToBaseline == <>(phase = "RolledBack")
\* Negative reachability queries. TLC violations provide existential witnesses.
NoRebootRecovery == ~(rebooted /\ phase = "Completed")
NoReorderedDuplicate == ~(duplicated /\ device[Victim].received = {}
  /\ Packet("Apply",1) \notin down[Victim] /\ device[Victim].fence = 1)
SafetySpec == Init /\ [][Next]_vars
NoRollback == phase # "RolledBack"
NoFailure == phase # "Failed"
=============================================================================
