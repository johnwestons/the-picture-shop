from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any


MAX_REPORT_BYTES = 64 * 1024
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
COMMIT_RE = re.compile(r"^[0-9a-f]{40}$")
SAFE_ABIS = {"armeabi-v7a", "arm64-v8a", "x86_64"}
SAFE_ROLES = {"host", "guest"}

REQUIRED_CHECKS = (
    "three_phone_roster_movement_sync",
    "host_authoritative_state_sync",
    "windows_host_topology",
    "android_host_topology",
    "vendor_purchasing",
    "truck_delivery_and_pickup",
    "cutter_maintenance",
    "wrapper_maintenance",
    "machine_relocation_all_three",
    "guest_multiplayer_ux",
    "lan_discovery_router",
    "lan_discovery_hotspot",
    "reconnect_fresh_session",
    "contention_and_disconnect_recovery",
    "fifteen_minute_soak",
    "offline_host_save_reload",
    "guest_save_absence",
)

TOP_LEVEL_FIELDS = {
    "schemaVersion",
    "status",
    "completedAtUtc",
    "sourceCommit",
    "apk",
    "devices",
    "checks",
    "operatorConfirmation",
}
APK_FIELDS = {"applicationId", "versionName", "versionCode", "bytes", "sha256"}
DEVICE_FIELDS = {"label", "model", "androidVersion", "abi", "roles"}
CHECK_FIELDS = {"passed", "evidence"}
CONFIRMATION_FIELDS = {"confirmed", "operator", "notes"}


class AcceptanceError(ValueError):
    pass


def _object_without_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise AcceptanceError(f"duplicate JSON field: {key}")
        result[key] = value
    return result


def load_json(path: Path, label: str, max_bytes: int = MAX_REPORT_BYTES) -> dict[str, Any]:
    if not path.is_file() or path.is_symlink():
        raise AcceptanceError(f"{label} must be a regular file")
    size = path.stat().st_size
    if size < 2 or size > max_bytes:
        raise AcceptanceError(f"{label} has an invalid size")
    try:
        value = json.loads(
            path.read_text(encoding="utf-8"),
            object_pairs_hook=_object_without_duplicates,
        )
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise AcceptanceError(f"{label} is not canonical UTF-8 JSON") from exc
    if not isinstance(value, dict):
        raise AcceptanceError(f"{label} must contain one JSON object")
    return value


def _exact_fields(value: dict[str, Any], expected: set[str], label: str) -> None:
    actual = set(value)
    if actual != expected:
        missing = sorted(expected - actual)
        extra = sorted(actual - expected)
        raise AcceptanceError(f"{label} fields differ: missing={missing} extra={extra}")


def _safe_text(value: Any, label: str, minimum: int = 1, maximum: int = 1000) -> str:
    if not isinstance(value, str):
        raise AcceptanceError(f"{label} must be text")
    stripped = value.strip()
    if len(stripped) < minimum or len(stripped) > maximum:
        raise AcceptanceError(f"{label} has an invalid length")
    if any(ord(character) < 32 and character not in "\t\n" for character in stripped):
        raise AcceptanceError(f"{label} contains control characters")
    return stripped


def _positive_integer(value: Any, label: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < 1:
        raise AcceptanceError(f"{label} must be a positive integer")
    return value


def _completed_timestamp(value: Any) -> str:
    text = _safe_text(value, "completedAtUtc", 20, 40)
    try:
        parsed = datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError as exc:
        raise AcceptanceError("completedAtUtc must be an ISO-8601 timestamp") from exc
    if parsed.tzinfo is None or parsed.utcoffset() != timezone.utc.utcoffset(parsed):
        raise AcceptanceError("completedAtUtc must be in UTC")
    if parsed > datetime.now(timezone.utc) + timedelta(minutes=5):
        raise AcceptanceError("completedAtUtc cannot be in the future")
    return text


def _hash_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verify(
    report: dict[str, Any],
    apk_report: dict[str, Any],
    build_report: dict[str, Any],
    apk_path: Path,
) -> dict[str, Any]:
    _exact_fields(report, TOP_LEVEL_FIELDS, "acceptance report")
    if (
        isinstance(report["schemaVersion"], bool)
        or report["schemaVersion"] != 1
        or report["status"] != "passed"
    ):
        raise AcceptanceError("acceptance report must be schema 1 with passed status")
    _completed_timestamp(report["completedAtUtc"])

    source_commit = report["sourceCommit"]
    if not isinstance(source_commit, str) or not COMMIT_RE.fullmatch(source_commit):
        raise AcceptanceError("sourceCommit must be a lowercase full Git commit")
    if build_report.get("sourceDirty") is not False:
        raise AcceptanceError("the physically tested mobile package must report clean source")
    if source_commit != build_report.get("sourceCommit"):
        raise AcceptanceError("physical acceptance does not match the mobile source commit")

    physical_apk = report["apk"]
    if not isinstance(physical_apk, dict):
        raise AcceptanceError("apk must be an object")
    _exact_fields(physical_apk, APK_FIELDS, "acceptance apk")
    _safe_text(physical_apk["applicationId"], "acceptance applicationId", 3, 200)
    _safe_text(physical_apk["versionName"], "acceptance versionName", 1, 100)
    _positive_integer(physical_apk["versionCode"], "acceptance versionCode")
    _positive_integer(physical_apk["bytes"], "acceptance APK bytes")
    if not isinstance(physical_apk["sha256"], str) or not SHA256_RE.fullmatch(
        physical_apk["sha256"]
    ):
        raise AcceptanceError("acceptance APK SHA-256 is invalid")
    expected_apk = {
        "applicationId": apk_report.get("applicationId"),
        "versionName": apk_report.get("versionName"),
        "versionCode": apk_report.get("versionCode"),
        "bytes": apk_report.get("apkBytes"),
        "sha256": apk_report.get("sha256"),
    }
    if physical_apk != expected_apk:
        raise AcceptanceError("physical acceptance does not match the exact Android APK report")
    if apk_report.get("artifactKind") != "game-debug" or apk_report.get("engineeringProbe") is not False:
        raise AcceptanceError("physical acceptance requires the normal game APK")
    for field in ("signed", "internetPermission", "accessNetworkStatePermission", "sixteenKbCompatible"):
        if apk_report.get(field) is not True:
            raise AcceptanceError(f"Android APK report is missing required {field} verification")
    if not SHA256_RE.fullmatch(str(apk_report.get("sha256", ""))):
        raise AcceptanceError("Android APK report SHA-256 is invalid")
    if not apk_path.is_file() or apk_path.is_symlink():
        raise AcceptanceError("Android APK must be a regular file")
    if apk_path.stat().st_size != apk_report.get("apkBytes"):
        raise AcceptanceError("Android APK byte length does not match its report")
    if _hash_file(apk_path) != apk_report.get("sha256"):
        raise AcceptanceError("Android APK SHA-256 does not match its report")

    embedded = apk_report.get("embeddedLove")
    if not isinstance(embedded, dict) or embedded.get("sha256") != build_report.get("sha256"):
        raise AcceptanceError("Android APK is not bound to the clean mobile package report")
    if apk_report.get("versionName") != build_report.get("versionName") or (
        apk_report.get("versionCode") != build_report.get("versionCode")
    ):
        raise AcceptanceError("Android APK and mobile package versions differ")

    devices = report["devices"]
    if not isinstance(devices, list) or not 3 <= len(devices) <= 4:
        raise AcceptanceError("physical acceptance requires three or four phone records")
    labels: set[str] = set()
    host_count = 0
    guest_count = 0
    for index, device in enumerate(devices, 1):
        if not isinstance(device, dict):
            raise AcceptanceError(f"device {index} must be an object")
        _exact_fields(device, DEVICE_FIELDS, f"device {index}")
        label = _safe_text(device["label"], f"device {index} label", 2, 40)
        if label in labels:
            raise AcceptanceError("phone labels must be unique")
        labels.add(label)
        _safe_text(device["model"], f"device {index} model", 2, 100)
        _safe_text(device["androidVersion"], f"device {index} Android version", 1, 40)
        if device["abi"] not in SAFE_ABIS:
            raise AcceptanceError(f"device {index} ABI is unsupported")
        roles = device["roles"]
        if (
            not isinstance(roles, list)
            or not roles
            or any(not isinstance(role, str) for role in roles)
            or len(set(roles)) != len(roles)
        ):
            raise AcceptanceError(f"device {index} roles must be a unique nonempty list")
        if any(role not in SAFE_ROLES for role in roles):
            raise AcceptanceError(f"device {index} has an invalid role")
        host_count += int("host" in roles)
        guest_count += int("guest" in roles)
    if host_count < 1 or guest_count < 2:
        raise AcceptanceError("phone evidence must include an Android host and at least two phone guests")

    checks = report["checks"]
    if not isinstance(checks, dict) or set(checks) != set(REQUIRED_CHECKS):
        missing = sorted(set(REQUIRED_CHECKS) - set(checks) if isinstance(checks, dict) else REQUIRED_CHECKS)
        extra = sorted(set(checks) - set(REQUIRED_CHECKS) if isinstance(checks, dict) else ())
        raise AcceptanceError(f"physical check set differs: missing={missing} extra={extra}")
    for check_id in REQUIRED_CHECKS:
        result = checks[check_id]
        if not isinstance(result, dict):
            raise AcceptanceError(f"{check_id} must be an object")
        _exact_fields(result, CHECK_FIELDS, check_id)
        if result["passed"] is not True:
            raise AcceptanceError(f"{check_id} has not passed")
        _safe_text(result["evidence"], f"{check_id} evidence", 12, 1000)

    confirmation = report["operatorConfirmation"]
    if not isinstance(confirmation, dict):
        raise AcceptanceError("operatorConfirmation must be an object")
    _exact_fields(confirmation, CONFIRMATION_FIELDS, "operator confirmation")
    if confirmation["confirmed"] is not True:
        raise AcceptanceError("the physical-test operator must confirm the result")
    _safe_text(confirmation["operator"], "operator", 2, 100)
    _safe_text(confirmation["notes"], "operator notes", 12, 2000)

    return {
        "status": "passed",
        "phones": len(devices),
        "checks": len(REQUIRED_CHECKS),
        "sourceCommit": source_commit,
        "apkSha256": apk_report["sha256"],
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Verify final Guest Worker phone acceptance evidence.")
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--apk-report", required=True, type=Path)
    parser.add_argument("--build-report", required=True, type=Path)
    arguments = parser.parse_args(argv)
    try:
        report = load_json(arguments.report, "physical acceptance report")
        apk_report = load_json(arguments.apk_report, "Android APK report", 256 * 1024)
        build_report = load_json(arguments.build_report, "mobile package report", 256 * 1024)
        apk_value = apk_report.get("apk")
        if not isinstance(apk_value, str) or not apk_value:
            raise AcceptanceError("Android APK report does not name an artifact")
        result = verify(report, apk_report, build_report, Path(apk_value).resolve())
    except AcceptanceError as exc:
        print(f"GUEST_WORKER_PHYSICAL_ACCEPTANCE=FAIL reason={exc}", file=sys.stderr)
        return 1
    print(
        "GUEST_WORKER_PHYSICAL_ACCEPTANCE=PASS "
        f"phones={result['phones']} checks={result['checks']} "
        f"apk_sha256={result['apkSha256']}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
