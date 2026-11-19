import re
import unittest
from pathlib import Path

from simulator.replay import Disabled, Fleet, events

EXAMPLES = Path(__file__).resolve().parents[1] / "examples"
TRACE = events(EXAMPLES / "stale-report.trace")


class ReplayTests(unittest.TestCase):
    def test_every_snapshot_matches_tlc(self):
        text = (EXAMPLES / "stale-report.tlc.txt").read_text()
        states = re.findall(r"^State \d+:.*?\n(.*?)\n\n", text, re.S | re.M)
        self.assertEqual(len(states), len(TRACE) + 1)
        fleet = Fleet(unsafe=True)
        for i, state in enumerate(states):
            if i:
                fleet.execute(TRACE[i - 1])
            with self.subTest(state=i + 1):
                self.assertIn(f'phase = "{fleet.phase}"', state)
                self.assertIn(f'epoch = {fleet.epoch}', state)
                self.assertIn('accepted = {' + ', '.join(sorted(fleet.accepted)) + '}', state)
                for key in ("active", "commit", "fence", "image", "step"):
                    values = re.findall(rf'{key} \|-> (\d+|"\w+")', state)
                    self.assertEqual([v.strip('"') for v in values],
                                     [str(getattr(d, key)) for d in fleet.devices.values()])
                self.assertEqual(fleet.sound(), i < len(TRACE))

    def test_fix_waits_then_completes(self):
        fleet = Fleet()
        for event in TRACE[:-1]:
            fleet.execute(event)
        with self.assertRaisesRegex(Disabled, "waiting for a"):
            fleet.execute("finalize")
        for event in ["issue a", "apply a 2", "image a 2", "verify a", "install a",
                      "commit a", "report a 2", "finalize"]:
            fleet.execute(event)
        self.assertEqual(fleet.phase, "RolledBack")
        self.assertTrue(fleet.sound())

    def test_missing_image_blocks_verification_and_report(self):
        fleet = Fleet()
        for event in ["begin", "issue a", "apply a 1"]:
            fleet.execute(event)
        for event in ["verify a", "commit a", "report a 1"]:
            with self.assertRaises(Disabled):
                fleet.execute(event)
