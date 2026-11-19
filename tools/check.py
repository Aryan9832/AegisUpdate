"""Run TLC scenarios, distinguishing exhaustive checks from witness searches."""
import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SCENARIOS = ("normal", "network", "reboot", "rollback", "offline")
WITNESSES = {"network": "NoReorderedDuplicate", "reboot": "NoRebootRecovery",
             "rollback": "NoRollback", "offline": "NoFailure"}


def check(name, mode, save):
    cfg = (ROOT / "model/scenarios" / (name + ".cfg")).read_text()
    expected = None
    if mode in {"safety", "witness"}:
        cfg = cfg.replace("SPECIFICATION Spec", "SPECIFICATION SafetySpec")
        cfg = re.sub(r"^PROPERTIES .*\n", "", cfg, flags=re.MULTILINE)
    if mode == "witness":
        expected = WITNESSES[name]
        cfg += f"INVARIANT {expected}\n"
    if name == "unsafe":
        expected = "SoundFinalization"

    jar = Path(os.environ.get("TLA_JAR", ROOT / ".tools/tla2tools.jar")).resolve()
    with tempfile.TemporaryDirectory() as tmp:
        config = Path(tmp) / "Run.cfg"
        config.write_text(cfg)
        shutil.copyfile(ROOT / "model/AegisUpdate.tla", Path(tmp) / "AegisUpdate.tla")
        cmd = [os.environ.get("JAVA", "java"), "-XX:+UseParallelGC", "-cp", str(jar),
               "tlc2.TLC", "-workers", "1", "-config", config.name, "AegisUpdate.tla"]
        run = subprocess.run(cmd, cwd=tmp, text=True, stdout=subprocess.PIPE,
                             stderr=subprocess.STDOUT)
    output = run.stdout
    if save:
        save.mkdir(parents=True, exist_ok=True)
        (save / f"{name}-{mode}.log").write_text(output)
    if expected:
        passed = run.returncode == 12 and f"Invariant {expected} is violated." in output
    else:
        passed = run.returncode == 0 and "No error has been found" in output
    if not passed:
        raise SystemExit(output)
    stats = re.findall(r"^\d+ states generated, .*", output, re.MULTILINE)
    print(f"{name:8} {mode:8} {expected or 'passed':21} {stats[-1]}", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["verify", "safety", "witness", "unsafe"])
    parser.add_argument("scenario", nargs="?", choices=SCENARIOS)
    parser.add_argument("--logs", type=Path)
    args = parser.parse_args()
    names = [args.scenario] if args.scenario else SCENARIOS
    if args.mode == "unsafe":
        names = ["unsafe"]
    for name in names:
        if args.mode != "witness" or name in WITNESSES:
            check(name, args.mode, args.logs)
