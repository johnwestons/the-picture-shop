from __future__ import annotations

import io
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile
from contextlib import redirect_stderr, redirect_stdout
from datetime import datetime, timezone
from pathlib import Path
from unittest.mock import patch


TOOLS = Path(__file__).resolve().parents[1]
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

from verify_public_ipv4_remote_results import (  # noqa: E402
    BUILD_REPORT_CONTRACT,
    DEFAULT_BUILD_REPORT,
    DEFAULT_KIT_ZIP,
    FROZEN_KIT_SHA256,
    GUEST_PASS_CONTRACT,
    HOST_PASS_CONTRACT,
    ValidationError,
    main,
    sha256_file,
    validate_reference_kit,
    validate_result_pair,
)


def marker_bytes(contract: tuple[tuple[str, str], ...]) -> bytes:
    return ("\n".join(f"{key}={value}" for key, value in contract) + "\n").encode("ascii")


class PublicIpv4RemoteResultTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.kit = self.root / "kit.zip"
        with zipfile.ZipFile(self.kit, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            archive.writestr("fixture.txt", "frozen fixture\n")
        self.kit_hash = sha256_file(self.kit)
        self.build_report = self.root / "build-report.txt"
        self.build_report.write_bytes(
            marker_bytes(BUILD_REPORT_CONTRACT + (("ZIP_SHA256", self.kit_hash),))
        )
        self.host = self.root / "last-host-result.txt"
        self.guest = self.root / "last-guest-result.txt"
        self.host.write_bytes(marker_bytes(HOST_PASS_CONTRACT))
        self.guest.write_bytes(marker_bytes(GUEST_PASS_CONTRACT))

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def validate(self, **overrides: object) -> dict[str, object]:
        arguments: dict[str, object] = {
            "host_result": self.host,
            "guest_result": self.guest,
            "kit_zip": self.kit,
            "build_report": self.build_report,
            "expected_zip_sha256": self.kit_hash,
            "now": datetime(2026, 9, 1, 12, 0, tzinfo=timezone.utc),
        }
        arguments.update(overrides)
        return validate_result_pair(**arguments)

    def assert_validation_error(self, code: str) -> None:
        with self.assertRaises(ValidationError) as caught:
            self.validate()
        self.assertEqual(code, caught.exception.code)

    def assert_validation_error_for(self, code: str, **overrides: object) -> None:
        with self.assertRaises(ValidationError) as caught:
            self.validate(**overrides)
        self.assertEqual(code, caught.exception.code)

    def test_exact_pass_pair_is_bound_to_verified_reference_artifact(self) -> None:
        report = self.validate()
        self.assertEqual("valid", report["validationStatus"])
        self.assertEqual("pass", report["outcome"]["probeResultPair"])
        self.assertEqual("pass", report["outcome"]["routerMappingCleanup"])
        self.assertFalse(report["outcome"]["fullAcceptanceReady"])
        self.assertEqual(
            "pending_same_attempt_confirmation",
            report["outcome"]["acceptanceStatus"],
        )
        self.assertTrue(report["artifact"]["referenceKitVerified"])
        self.assertTrue(report["provenance"]["combinedReportBoundToReferenceArtifact"])
        self.assertFalse(report["provenance"]["resultOriginCryptographicallyProven"])
        self.assertFalse(report["provenance"]["sameRunPairingProven"])
        self.assertEqual(64, len(report["evidenceSetDigest"]))

    def test_checked_in_frozen_profile_matches_the_prepared_zip(self) -> None:
        if not DEFAULT_KIT_ZIP.is_file() or not DEFAULT_BUILD_REPORT.is_file():
            self.skipTest("The ignored local acceptance artifact is not present.")
        actual, _ = validate_reference_kit(
            DEFAULT_KIT_ZIP,
            DEFAULT_BUILD_REPORT,
            FROZEN_KIT_SHA256,
        )
        self.assertEqual(FROZEN_KIT_SHA256, actual)

    def test_windows_wrapper_runs_the_strict_validator(self) -> None:
        powershell = shutil.which("powershell.exe")
        wrapper = TOOLS / "verify_public_ipv4_remote_results.ps1"
        if (
            not powershell
            or not wrapper.is_file()
            or not DEFAULT_KIT_ZIP.is_file()
            or not DEFAULT_BUILD_REPORT.is_file()
        ):
            self.skipTest("The Windows wrapper or ignored local acceptance artifact is unavailable.")
        report_path = self.root / "wrapper-report.json"
        completed = subprocess.run(
            [
                powershell,
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(wrapper),
                "-HostResult",
                str(self.host),
                "-GuestResult",
                str(self.guest),
                "-KitZip",
                str(DEFAULT_KIT_ZIP),
                "-BuildReport",
                str(DEFAULT_BUILD_REPORT),
                "-ReportPath",
                str(report_path),
                "-FirewallCleanupConfirmed",
                "-SameAttemptConfirmed",
            ],
            check=False,
            capture_output=True,
            text=True,
            timeout=30,
        )
        self.assertEqual(0, completed.returncode, completed.stderr)
        self.assertIn("TPS_PUBLIC_IPV4_RESULT_VALIDATION=PASS", completed.stdout)
        self.assertIn("ACCEPTANCE_GATE=PASS", completed.stdout)
        self.assertEqual("valid", json.loads(report_path.read_text(encoding="utf-8"))["validationStatus"])

    def test_operator_confirmations_complete_acceptance(self) -> None:
        report = self.validate(
            firewall_cleanup_confirmed=True,
            same_attempt_confirmed=True,
        )
        self.assertTrue(report["outcome"]["fullAcceptanceReady"])
        self.assertEqual("operator_confirmed", report["outcome"]["firewallRuleCleanup"])
        self.assertEqual("operator_confirmed", report["outcome"]["sameAttemptFreshness"])

    def test_same_attempt_confirmation_still_requires_firewall_confirmation(self) -> None:
        report = self.validate(same_attempt_confirmed=True)
        self.assertFalse(report["outcome"]["fullAcceptanceReady"])
        self.assertEqual(
            "pending_firewall_cleanup_confirmation",
            report["outcome"]["acceptanceStatus"],
        )

    def test_safe_host_failure_produces_valid_failed_pair(self) -> None:
        self.host.write_text(
            "TPS_PUBLIC_IPV4_HOST=FAIL\n"
            "REASON=guest_timeout\n"
            "FINITE_LEASE_SECONDS=120\n"
            "LISTENER_CLOSED_BEFORE_DELETE=True\n"
            "DELETION_ACKNOWLEDGED=True\n"
            "NETWORK_DETAILS_RETAINED=False\n",
            encoding="ascii",
            newline="\n",
        )
        report = self.validate()
        self.assertEqual("fail", report["outcome"]["probeResultPair"])
        self.assertEqual("guest_timeout", report["evidence"]["host"]["reason"])
        self.assertEqual("pass", report["outcome"]["routerMappingCleanup"])
        self.assertFalse(report["outcome"]["fullAcceptanceReady"])

    def test_mixed_host_and_guest_statuses_are_reported_without_overclaiming(self) -> None:
        self.guest.write_text(
            "TPS_PUBLIC_IPV4_GUEST=FAIL\n"
            "REASON=guest_connection_failed\n"
            "NETWORK_DETAILS_RETAINED=False\n",
            encoding="ascii",
            newline="\n",
        )
        report = self.validate()
        self.assertEqual("mixed_status", report["outcome"]["roleStatusRelationship"])
        self.assertEqual("failed_mixed_role_status", report["outcome"]["acceptanceStatus"])

    def test_host_and_guest_paths_must_be_distinct(self) -> None:
        self.assert_validation_error_for(
            "result_paths_not_distinct",
            guest_result=self.host,
        )

    def test_empty_result_is_rejected(self) -> None:
        self.guest.write_bytes(b"")
        self.assert_validation_error("guest_result_size_invalid")

    def test_oversized_result_is_rejected_before_parsing(self) -> None:
        self.guest.write_bytes(b"A" * 4097)
        self.assert_validation_error("guest_result_size_invalid")

    def test_unknown_host_marker_is_rejected(self) -> None:
        self.host.write_bytes(marker_bytes(HOST_PASS_CONTRACT) + b"IP_ADDRESS=203.0.113.44\n")
        self.assert_validation_error("host_result_marker_invalid")

    def test_duplicate_marker_is_rejected(self) -> None:
        self.guest.write_bytes(
            marker_bytes(GUEST_PASS_CONTRACT)
            + b"NETWORK_DETAILS_RETAINED=False\n"
        )
        self.assert_validation_error("guest_result_duplicate_marker")

    def test_missing_success_marker_is_rejected(self) -> None:
        self.host.write_bytes(marker_bytes(HOST_PASS_CONTRACT[:-2] + HOST_PASS_CONTRACT[-1:]))
        self.assert_validation_error("host_result_contract_invalid")

    def test_role_swap_is_rejected(self) -> None:
        self.host.write_bytes(marker_bytes(GUEST_PASS_CONTRACT))
        self.assert_validation_error("host_result_role_invalid")

    def test_unlisted_failure_reason_is_rejected(self) -> None:
        self.guest.write_text(
            "TPS_PUBLIC_IPV4_GUEST=FAIL\n"
            "REASON=invalid_invitation\n"
            "NETWORK_DETAILS_RETAINED=False\n",
            encoding="ascii",
            newline="\n",
        )
        self.assert_validation_error("guest_result_reason_invalid")

    def test_failure_cannot_claim_acknowledged_cleanup_timeout(self) -> None:
        self.host.write_text(
            "TPS_PUBLIC_IPV4_HOST=FAIL\n"
            "REASON=cleanup_timeout\n"
            "FINITE_LEASE_SECONDS=120\n"
            "DELETION_ACKNOWLEDGED=True\n"
            "NETWORK_DETAILS_RETAINED=False\n",
            encoding="ascii",
            newline="\n",
        )
        self.assert_validation_error("host_result_safety_invalid")

    def test_deletion_ack_requires_listener_closed_first(self) -> None:
        self.host.write_text(
            "TPS_PUBLIC_IPV4_HOST=FAIL\n"
            "REASON=guest_timeout\n"
            "FINITE_LEASE_SECONDS=120\n"
            "LISTENER_CLOSED_BEFORE_DELETE=False\n"
            "DELETION_ACKNOWLEDGED=True\n"
            "NETWORK_DETAILS_RETAINED=False\n",
            encoding="ascii",
            newline="\n",
        )
        self.assert_validation_error("host_result_safety_invalid")

    def test_noncanonical_encoding_is_rejected(self) -> None:
        self.guest.write_bytes(b"\xef\xbb\xbf" + marker_bytes(GUEST_PASS_CONTRACT))
        self.assert_validation_error("guest_result_encoding_invalid")

    def test_missing_terminal_newline_is_rejected(self) -> None:
        self.guest.write_bytes(marker_bytes(GUEST_PASS_CONTRACT).rstrip(b"\n"))
        self.assert_validation_error("guest_result_format_invalid")

    def test_crlf_result_is_rejected_as_not_generator_exact(self) -> None:
        self.guest.write_bytes(marker_bytes(GUEST_PASS_CONTRACT).replace(b"\n", b"\r\n"))
        self.assert_validation_error("guest_result_format_invalid")

    def test_failure_reason_must_match_its_generated_shape(self) -> None:
        self.host.write_text(
            "TPS_PUBLIC_IPV4_HOST=FAIL\n"
            "REASON=guest_timeout\n"
            "FINITE_LEASE_SECONDS=120\n"
            "NETWORK_DETAILS_RETAINED=False\n",
            encoding="ascii",
            newline="\n",
        )
        self.assert_validation_error("host_result_reason_shape_invalid")

    def test_build_report_must_match_exact_contract(self) -> None:
        altered = list(BUILD_REPORT_CONTRACT)
        altered[7] = ("PRODUCTION_GATE_RETAINED", "False")
        self.build_report.write_bytes(
            marker_bytes(tuple(altered) + (("ZIP_SHA256", self.kit_hash),))
        )
        self.assert_validation_error("build_report_contract_invalid")

    def test_kit_hash_mismatch_is_rejected(self) -> None:
        with self.kit.open("ab") as handle:
            handle.write(b"altered")
        self.assert_validation_error("kit_zip_hash_mismatch")

    def test_cli_writes_only_a_safe_error_code_for_untrusted_input(self) -> None:
        secret = "203.0.113.44"
        self.guest.write_text(
            f"TPS_PUBLIC_IPV4_GUEST=FAIL\nREASON={secret}\nNETWORK_DETAILS_RETAINED=False\n",
            encoding="ascii",
            newline="\n",
        )
        report_path = self.root / "invalid.json"
        stdout = io.StringIO()
        stderr = io.StringIO()
        with redirect_stdout(stdout), redirect_stderr(stderr):
            exit_code = main(
                [
                    "--host-result",
                    str(self.host),
                    "--guest-result",
                    str(self.guest),
                    "--kit-zip",
                    str(self.kit),
                    "--build-report",
                    str(self.build_report),
                    "--report",
                    str(report_path),
                ],
                expected_zip_sha256=self.kit_hash,
            )
        self.assertEqual(2, exit_code)
        report_text = report_path.read_text(encoding="utf-8")
        self.assertNotIn(secret, report_text + stdout.getvalue() + stderr.getvalue())
        self.assertEqual("invalid", json.loads(report_text)["validationStatus"])

    def test_cli_refuses_to_overwrite_an_input(self) -> None:
        with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            exit_code = main(
                [
                    "--host-result",
                    str(self.host),
                    "--guest-result",
                    str(self.guest),
                    "--kit-zip",
                    str(self.kit),
                    "--build-report",
                    str(self.build_report),
                    "--report",
                    str(self.host),
                ],
                expected_zip_sha256=self.kit_hash,
            )
        self.assertEqual(2, exit_code)
        self.assertEqual(marker_bytes(HOST_PASS_CONTRACT), self.host.read_bytes())

    def test_failed_invalid_report_write_warns_about_stale_prior_report(self) -> None:
        self.guest.write_bytes(b"unsafe\n")
        report_path = self.root / "prior-report.json"
        prior = '{"validationStatus":"valid"}\n'
        report_path.write_text(prior, encoding="utf-8", newline="\n")
        stdout = io.StringIO()
        stderr = io.StringIO()
        forced = ValidationError("report_write_failed", "The redacted report was not updated.")
        with (
            patch("verify_public_ipv4_remote_results.write_report", side_effect=forced),
            redirect_stdout(stdout),
            redirect_stderr(stderr),
        ):
            exit_code = main(
                [
                    "--host-result",
                    str(self.host),
                    "--guest-result",
                    str(self.guest),
                    "--kit-zip",
                    str(self.kit),
                    "--build-report",
                    str(self.build_report),
                    "--report",
                    str(report_path),
                ],
                expected_zip_sha256=self.kit_hash,
            )
        self.assertEqual(2, exit_code)
        self.assertEqual(prior, report_path.read_text(encoding="utf-8"))
        self.assertIn("REPORT_UPDATED=False", stdout.getvalue())
        self.assertIn("STALE_REPORT_POSSIBLE=True", stdout.getvalue())
        self.assertIn("WARNING=report_not_updated_do_not_trust_prior_report", stdout.getvalue())


if __name__ == "__main__":
    unittest.main()
