from __future__ import annotations

import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
MAIN_PATH = REPO_ROOT / "tools" / "probes" / "public_ipv4_mapping" / "main.lua"
BUILD_PATH = REPO_ROOT / "tools" / "build_public_ipv4_mapping_probe.ps1"


def section(source: str, start: str, end: str) -> str:
    start_index = source.index(start)
    end_index = source.index(end, start_index + len(start))
    return source[start_index:end_index]


class PublicIpv4ProbeWatchdogIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.main = MAIN_PATH.read_text(encoding="utf-8")
        cls.build = BUILD_PATH.read_text(encoding="utf-8")

    def test_host_deadline_is_checked_before_polling_or_renewal_progress(self) -> None:
        body = section(
            self.main,
            "local function updateArmedHost(now)",
            "local function startGuestConnection()",
        )
        first_timeout = body.index("local timeoutReason = phaseWatchdog:timeout(now)")
        self.assertLess(first_timeout, body.index("transport:poll()"))
        self.assertLess(first_timeout, body.index('if state == "waiting_renewal" then'))
        self.assertIn("beginHostCleanup(false, timeoutReason)", body)

    def test_guest_deadline_is_checked_before_polling_phase_progress(self) -> None:
        body = section(
            self.main,
            "local function updateGuest(now)",
            "function love.load()",
        )
        first_timeout = body.index("local timeoutReason = phaseWatchdog:timeout(now)")
        self.assertLess(first_timeout, body.index("transport:poll()"))
        self.assertIn("pcall(transport.close, transport, 0, true)", body)
        self.assertIn("finish(false, timeoutReason)", body)

    def test_every_phase_transition_uses_a_fail_closed_helper(self) -> None:
        self.assertEqual(2, self.main.count("phaseWatchdog:transition("))
        host_helper = section(
            self.main,
            "local function transitionHostWatchdog",
            "local function runPreflight()",
        )
        guest_helper = section(
            self.main,
            "local function transitionGuestWatchdog",
            "local function processGuestEvent",
        )
        self.assertIn("if phaseWatchdog:transition(nextState, now) then return true end", host_helper)
        self.assertIn("beginHostCleanup(false", host_helper)
        self.assertIn("if phaseWatchdog:transition(nextState, now) then return true end", guest_helper)
        self.assertIn("finish(false, reason)", guest_helper)

    def test_duplicate_and_out_of_phase_events_cannot_rearm_or_skip_renewal(self) -> None:
        host_events = section(
            self.main,
            "local function processHostEvent(event, now)",
            "local function updateArmedHost(now)",
        )
        guest_events = section(
            self.main,
            "local function processGuestEvent(event, now)",
            "local function updateGuest(now)",
        )
        self.assertIn("if peer then", host_events)
        self.assertIn("phaseStarted[2] ~= true", host_events)
        self.assertIn('state ~= "renewed_exchange"', host_events)
        self.assertIn("if guestConnected then return end", guest_events)
        self.assertIn('state ~= "guest_waiting_close"', guest_events)
        self.assertLess(host_events.index("Protocol.parse"), host_events.index("phaseAcks[parsed.phase]"))
        self.assertLess(guest_events.index("Protocol.parse"), guest_events.index("guestSeen[parsed.phase]"))

    def test_cancel_cleanup_and_future_build_retain_watchdog_guards(self) -> None:
        host_cleanup = section(
            self.main,
            "local function beginHostCleanup",
            "local function transitionHostWatchdog",
        )
        self.assertLess(host_cleanup.index("phaseWatchdog:clear()"), host_cleanup.index("ipv4Host.stop"))
        self.assertIn('finish(false, "cleanup_timeout"', self.main)
        self.assertIn('"DELETION_ACKNOWLEDGED=False"', self.main)
        self.assertIn('beginHostCleanup(false, "cancelled")', self.main)
        self.assertIn('finish(false, "cancelled")', self.main)
        self.assertIn("'src/net/public_ipv4_probe_watchdog.lua'", self.build)

    def test_cleanup_markers_use_canonical_boolean_case(self) -> None:
        cleanup = section(
            self.main,
            "local function completeHostCleanup()",
            "local function beginHostCleanup",
        )
        self.assertIn("booleanMarker(status.listenerClosedBeforeCleanup == true)", cleanup)
        self.assertIn("booleanMarker(deletionAcknowledged)", cleanup)
        self.assertNotIn("tostring(status.listenerClosedBeforeCleanup == true)", cleanup)
        self.assertNotIn("tostring(deletionAcknowledged)", cleanup)


if __name__ == "__main__":
    unittest.main()
