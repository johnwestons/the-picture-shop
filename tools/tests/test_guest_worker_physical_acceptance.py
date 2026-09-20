from __future__ import annotations

import hashlib
import sys
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path


TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))

from verify_guest_worker_physical_acceptance import (
    AcceptanceError,
    REQUIRED_CHECKS,
    load_json,
    verify,
)


COMMIT = "a" * 40


def reports(root: Path):
    apk = root / "candidate.apk"
    apk.write_bytes(b"normal-game-apk")
    digest = hashlib.sha256(apk.read_bytes()).hexdigest()
    build = {
        "sourceCommit": COMMIT,
        "sourceDirty": False,
        "versionName": "0.1.0-android.25",
        "versionCode": 25,
        "sha256": "b" * 64,
    }
    apk_report = {
        "artifactKind": "game-debug",
        "engineeringProbe": False,
        "applicationId": "com.thepictureshop.game",
        "versionName": build["versionName"],
        "versionCode": build["versionCode"],
        "apkBytes": apk.stat().st_size,
        "sha256": digest,
        "signed": True,
        "internetPermission": True,
        "accessNetworkStatePermission": True,
        "sixteenKbCompatible": True,
        "embeddedLove": {"sha256": build["sha256"]},
    }
    acceptance = {
        "schemaVersion": 1,
        "status": "passed",
        "completedAtUtc": datetime.now(timezone.utc).isoformat(),
        "sourceCommit": COMMIT,
        "apk": {
            "applicationId": apk_report["applicationId"],
            "versionName": apk_report["versionName"],
            "versionCode": apk_report["versionCode"],
            "bytes": apk_report["apkBytes"],
            "sha256": apk_report["sha256"],
        },
        "devices": [
            {"label": "phone-a", "model": "Model A", "androidVersion": "16", "abi": "arm64-v8a", "roles": ["host", "guest"]},
            {"label": "phone-b", "model": "Model B", "androidVersion": "15", "abi": "arm64-v8a", "roles": ["guest"]},
            {"label": "phone-c", "model": "Model C", "androidVersion": "8.1", "abi": "armeabi-v7a", "roles": ["guest"]},
        ],
        "checks": {
            check_id: {"passed": True, "evidence": f"Recorded physical evidence for {check_id}."}
            for check_id in REQUIRED_CHECKS
        },
        "operatorConfirmation": {
            "confirmed": True,
            "operator": "Test Operator",
            "notes": "All observations were made on the exact reported APK.",
        },
    }
    return apk, apk_report, build, acceptance


class GuestWorkerPhysicalAcceptanceTests(unittest.TestCase):
    def test_release_gate_and_standalone_assembler_require_physical_verifier(self) -> None:
        gate = (TOOLS / "release_gate.ps1").read_text(encoding="utf-8")
        assembler = (TOOLS / "assemble_tester_release.ps1").read_text(encoding="utf-8")
        verifier = "verify_guest_worker_physical_acceptance.py"
        report = "guest-worker-physical-acceptance.json"
        self.assertIn(verifier, gate)
        self.assertIn(report, gate)
        self.assertLess(gate.index("Verify three-phone Guest Worker acceptance"), gate.index("Assemble separate tester downloads"))
        self.assertIn(verifier, assembler)
        self.assertIn(report, assembler)
        self.assertLess(assembler.index(verifier), assembler.index("New-Item -ItemType Directory"))

    def test_complete_exact_three_phone_report_passes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            apk, apk_report, build, acceptance = reports(Path(temporary))
            result = verify(acceptance, apk_report, build, apk)
            self.assertEqual("passed", result["status"])
            self.assertEqual(3, result["phones"])
            self.assertEqual(len(REQUIRED_CHECKS), result["checks"])

    def test_two_phones_cannot_satisfy_three_phone_acceptance(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            apk, apk_report, build, acceptance = reports(Path(temporary))
            acceptance["devices"].pop()
            with self.assertRaisesRegex(AcceptanceError, "three or four phone"):
                verify(acceptance, apk_report, build, apk)

    def test_android_host_and_two_phone_guests_are_required(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            apk, apk_report, build, acceptance = reports(Path(temporary))
            acceptance["devices"][0]["roles"] = ["guest"]
            with self.assertRaisesRegex(AcceptanceError, "Android host"):
                verify(acceptance, apk_report, build, apk)

    def test_every_named_physical_check_must_pass_with_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            apk, apk_report, build, acceptance = reports(Path(temporary))
            del acceptance["checks"][REQUIRED_CHECKS[0]]
            with self.assertRaisesRegex(AcceptanceError, "physical check set differs"):
                verify(acceptance, apk_report, build, apk)
            _, _, _, acceptance = reports(Path(temporary))
            acceptance["checks"][REQUIRED_CHECKS[1]]["passed"] = False
            with self.assertRaisesRegex(AcceptanceError, "has not passed"):
                verify(acceptance, apk_report, build, apk)

    def test_report_is_bound_to_clean_exact_source_commit(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            apk, apk_report, build, acceptance = reports(Path(temporary))
            build["sourceDirty"] = True
            with self.assertRaisesRegex(AcceptanceError, "clean source"):
                verify(acceptance, apk_report, build, apk)
            build["sourceDirty"] = False
            acceptance["sourceCommit"] = "c" * 40
            with self.assertRaisesRegex(AcceptanceError, "source commit"):
                verify(acceptance, apk_report, build, apk)

    def test_report_is_bound_to_exact_verified_normal_apk(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            apk, apk_report, build, acceptance = reports(Path(temporary))
            acceptance["apk"]["sha256"] = "c" * 64
            with self.assertRaisesRegex(AcceptanceError, "exact Android APK"):
                verify(acceptance, apk_report, build, apk)
            acceptance["apk"]["sha256"] = apk_report["sha256"]
            apk_report["engineeringProbe"] = True
            with self.assertRaisesRegex(AcceptanceError, "normal game APK"):
                verify(acceptance, apk_report, build, apk)

    def test_apk_file_tampering_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            apk, apk_report, build, acceptance = reports(Path(temporary))
            apk.write_bytes(b"tampered-normal-game-apk")
            with self.assertRaisesRegex(AcceptanceError, "byte length"):
                verify(acceptance, apk_report, build, apk)

    def test_duplicate_json_fields_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "duplicate.json"
            path.write_text('{"schemaVersion":1,"schemaVersion":1}', encoding="utf-8")
            with self.assertRaisesRegex(AcceptanceError, "duplicate JSON field"):
                load_json(path, "report")

    def test_malformed_schema_and_role_types_fail_closed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            apk, apk_report, build, acceptance = reports(Path(temporary))
            acceptance["schemaVersion"] = True
            with self.assertRaisesRegex(AcceptanceError, "schema 1"):
                verify(acceptance, apk_report, build, apk)
            _, _, _, acceptance = reports(Path(temporary))
            acceptance["devices"][0]["roles"] = [{"host": True}]
            with self.assertRaisesRegex(AcceptanceError, "unique nonempty list"):
                verify(acceptance, apk_report, build, apk)


if __name__ == "__main__":
    unittest.main()
