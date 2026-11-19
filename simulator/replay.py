"""Replay an event schedule using the two-device rollback protocol."""
import argparse
from dataclasses import dataclass, field
from pathlib import Path


class Disabled(ValueError):
    """A valid protocol action has an unsatisfied guard."""


def require(condition, reason):
    if not condition:
        raise Disabled(reason)


def target(epoch):
    return {1: 2, 2: 1}[epoch]


@dataclass
class Device:
    active: int = 1
    commit: int = 0
    image: int = 0
    fence: int = 0
    step: str = "Idle"
    received: set = field(default_factory=set)
    verified: set = field(default_factory=set)
    installed: set = field(default_factory=set)
    down: set = field(default_factory=set)
    up: set = field(default_factory=set)


class Fleet:
    def __init__(self, unsafe=False):
        self.unsafe = unsafe
        self.phase = "Staged"
        self.epoch = 1
        self.devices = {name: Device() for name in ("a", "b")}
        self.accepted = set()
        self.issued = set()

    def execute(self, line):
        tokens = line.split()
        if not tokens:
            raise ValueError("empty action")
        op = tokens[0]
        arity = {"begin": 0, "finalize": 0, "issue": 1, "image": 2, "apply": 2,
                 "verify": 1, "install": 1, "commit": 1, "fault": 1, "report": 2}
        if op not in arity or len(tokens) != arity[op] + 1:
            raise ValueError(f"invalid action or argument count: {line}")
        if op == "begin":
            require(self.phase == "Staged", "rollout already started")
            self.phase = "RollingOut"
            return "candidate v2 approved"
        require(self.phase in {"RollingOut", "RollingBack"}, "rollout is inactive")
        if op == "finalize":
            require(self.accepted == set(self.devices), "waiting for " +
                    ", ".join(sorted(self.devices.keys() - self.accepted)))
            self.phase = "Completed" if self.epoch == 1 else "RolledBack"
            return self.phase
        name = tokens[1]
        if name not in self.devices:
            raise ValueError(f"unknown device {name}")
        d = self.devices[name]
        e = int(tokens[2]) if len(tokens) == 3 else self.epoch
        if e not in {1, 2}:
            raise ValueError(f"unknown epoch {e}")
        if op == "issue":
            require(name not in self.issued and not d.down, "already issued or busy")
            self.issued.add(name)
            d.down.update({("apply", e), ("image", e)})
            return f"sent Image and Apply for e{e}/v{target(e)}"
        if op in {"image", "apply"}:
            require((op, e) in d.down, "packet absent")
            d.down.remove((op, e))
            if op == "image":
                d.received.add((e, target(e)))
                if e >= d.fence and e > d.commit and d.image != e:
                    d.image, d.step = e, "Idle"
            elif e > d.fence:
                d.fence, d.step = e, "Idle"
                if d.image != e:
                    d.image = 0
            return f"delivered {op} for e{e}/v{target(e)}"
        if op == "verify":
            require(d.step == "Idle" and d.image and d.image == d.fence,
                    "matching image and approval required")
            d.verified.add((d.image, target(d.image)))
            d.step = "Verified"
            return "signature valid for approved image"
        if op == "install":
            require(d.step == "Verified", "verification required")
            d.step = "Installing"
            return "installation started"
        if op in {"commit", "fault"}:
            require(d.step == "Installing", "installation required")
            fails = name == "b" and d.fence == 1
            require(fails == (op == "fault"), "wrong installation outcome")
            if fails:
                d.step = "Fault"
                d.up.add(("Fault", d.fence, target(d.fence)))
                return "install failed; fault report queued"
            d.active, d.commit, d.step = target(d.image), d.fence, "Active"
            d.installed.add((d.commit, d.active))
            d.up.add(("Installed", d.commit, d.active))
            return f"activated v{d.active}; Installed report queued"
        packet = next((p for p in d.up if p[1] == e), None)
        require(packet is not None, "report absent")
        d.up.remove(packet)
        kind, _, version = packet
        if kind == "Fault" and e == self.epoch:
            self.phase, self.epoch = "RollingBack", 2
            self.accepted.clear()
            self.issued.clear()
            return "opened rollback e2/v1"
        if kind == "Installed" and (self.unsafe or (e, version) == (self.epoch, target(self.epoch))):
            self.accepted.add(name)
            return f"counted Installed(e{e},v{version}) toward e{self.epoch}"
        return f"discarded stale {kind}(e{e},v{version})"

    def sound(self):
        return self.phase not in {"RolledBack", "Completed"} or all(
            d.active == target(self.epoch) and d.commit == self.epoch and d.step == "Active"
            for d in self.devices.values())


def events(path):
    return [line for raw in path.read_text().splitlines()
            if (line := raw.partition("#")[0].strip())]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace", type=Path)
    parser.add_argument("--unsafe", action="store_true")
    args = parser.parse_args()
    fleet = Fleet(args.unsafe)
    print("01  initial         Staged     a=v1 b=v1")
    for state, line in enumerate(events(args.trace), 2):
        try:
            effect = fleet.execute(line)
        except Disabled as error:
            print(f"{state:02}  {line:<14} BLOCKED   {error}")
            return 2
        except ValueError as error:
            parser.exit(2, f"state {state}: {error}\n")
        versions = " ".join(f"{k}=v{v.active}" for k, v in fleet.devices.items())
        print(f"{state:02}  {line:<14} {fleet.phase:<12} {versions}  {effect}")
        if not fleet.sound():
            print("SoundFinalization violated")
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
