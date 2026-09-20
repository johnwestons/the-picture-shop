from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import tempfile
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Mapping, Sequence


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_KIT_ZIP = (
    REPO_ROOT
    / "output"
    / "public-ipv4-probe"
    / "ThePictureShop-PublicIPv4-Remote-Test.zip"
)
DEFAULT_BUILD_REPORT = REPO_ROOT / "output" / "public-ipv4-probe" / "build-report.txt"
DEFAULT_REPORT = (
    REPO_ROOT
    / "output"
    / "public-ipv4-results"
    / "verified-remote-result.json"
)

FROZEN_KIT_SHA256 = "e56d5386610870082f75ca6b7c6d53d1d3ee56386f0f3402831ed9dca40a4583"
FROZEN_BUILD_REPORT_SHA256 = "0795ff2cf1f1bf488be629ebef65c147f3b0ecaf4067f821bbcdb8d13196802f"
FROZEN_KIT_BYTES = 9_710_985
MAX_RESULT_BYTES = 4096
MAX_BUILD_REPORT_BYTES = 8192
MARKER_LINE = re.compile(
    r"^[A-Z0-9_]+=(?:PASS|FAIL|True|False|[a-z_]+|[0-9]+|[0-9a-f]{64})$"
)
SHA256_TEXT = re.compile(r"^[0-9a-f]{64}$")

BUILD_REPORT_CONTRACT = (
    ("TPS_PUBLIC_IPV4_KIT_BUILD", "PASS"),
    ("HOST_MANIFEST_VERIFIED", "True"),
    ("GUEST_MANIFEST_VERIFIED", "True"),
    ("NATIVE_CRYPTO_ABI", "3"),
    ("NATIVE_ROUTE_ABI", "2"),
    ("FINITE_LEASE_SECONDS", "120"),
    ("PROBE_PORT", "59281"),
    ("PRODUCTION_GATE_RETAINED", "True"),
    ("NETWORK_TRAFFIC_SENT", "False"),
)

HOST_PASS_CONTRACT = (
    ("TPS_PUBLIC_IPV4_HOST", "PASS"),
    ("MAPPING_CREATED", "True"),
    ("REMOTE_AUTHENTICATED", "True"),
    ("THREE_CHANNELS_BEFORE_RENEW", "True"),
    ("LEASE_RENEWED", "True"),
    ("THREE_CHANNELS_AFTER_RENEW", "True"),
    ("FINITE_LEASE_SECONDS", "120"),
    ("LISTENER_CLOSED_BEFORE_DELETE", "True"),
    ("DELETION_ACKNOWLEDGED", "True"),
    ("NETWORK_DETAILS_RETAINED", "False"),
)

GUEST_PASS_CONTRACT = (
    ("TPS_PUBLIC_IPV4_GUEST", "PASS"),
    ("REMOTE_AUTHENTICATED", "True"),
    ("THREE_CHANNELS_BEFORE_RENEW", "True"),
    ("THREE_CHANNELS_AFTER_RENEW", "True"),
    ("NETWORK_DETAILS_RETAINED", "False"),
)

HOST_FAILURE_REASONS = frozenset(
    {
        "cancelled",
        "crypto_unavailable",
        "route_unavailable",
        "listener_unavailable",
        "mapping_unavailable",
        "mapping_timeout",
        "mapped_endpoint_changed",
        "transport_unavailable",
        "guest_timeout",
        "transport_failed",
        "authentication_failed",
        "challenge_failed",
        "renewal_failed",
        "cleanup_timeout",
        "deletion_not_acknowledged",
        "preflight_failed",
    }
)

GUEST_FAILURE_REASONS = frozenset(
    {
        "cancelled",
        "crypto_unavailable",
        "transport_failed",
        "challenge_failed",
        "guest_connection_failed",
        "guest_disconnected_early",
    }
)

HOST_FAILURE_KEY_ORDERS = frozenset(
    {
        (
            "TPS_PUBLIC_IPV4_HOST",
            "REASON",
            "FINITE_LEASE_SECONDS",
            "NETWORK_DETAILS_RETAINED",
        ),
        (
            "TPS_PUBLIC_IPV4_HOST",
            "REASON",
            "FINITE_LEASE_SECONDS",
            "DELETION_ACKNOWLEDGED",
            "NETWORK_DETAILS_RETAINED",
        ),
        (
            "TPS_PUBLIC_IPV4_HOST",
            "REASON",
            "FINITE_LEASE_SECONDS",
            "LISTENER_CLOSED_BEFORE_DELETE",
            "DELETION_ACKNOWLEDGED",
            "NETWORK_DETAILS_RETAINED",
        ),
    }
)

HOST_EARLY_FAILURE_REASONS = frozenset(
    {"preflight_failed", "crypto_unavailable", "route_unavailable", "listener_unavailable"}
)
HOST_CLEANUP_FAILURE_REASONS = frozenset(
    {
        "cancelled",
        "crypto_unavailable",
        "listener_unavailable",
        "mapping_unavailable",
        "mapping_timeout",
        "mapped_endpoint_changed",
        "transport_unavailable",
        "guest_timeout",
        "transport_failed",
        "authentication_failed",
        "challenge_failed",
        "renewal_failed",
        "deletion_not_acknowledged",
    }
)
HOST_ABBREVIATED_FAILURE_REASONS = frozenset(
    {"cleanup_timeout", "deletion_not_acknowledged"}
)


class ValidationError(Exception):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code


@dataclass(frozen=True)
class MarkerFile:
    ordered: tuple[tuple[str, str], ...]
    values: Mapping[str, str]
    sha256: str


@dataclass(frozen=True)
class ResultEvidence:
    role: str
    status: str
    reason: str | None
    markers: Mapping[str, object]
    sha256: str


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as handle:
            for block in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(block)
    except OSError as exc:
        raise ValidationError("evidence_unreadable", "A required evidence file could not be read.") from exc
    return digest.hexdigest()


def read_marker_file(
    path: Path,
    *,
    label: str,
    max_bytes: int,
    allow_crlf: bool = False,
) -> MarkerFile:
    try:
        if not path.is_file():
            raise ValidationError(f"{label}_missing", f"The {label.replace('_', ' ')} is missing.")
        with path.open("rb") as handle:
            data = handle.read(max_bytes + 1)
    except ValidationError:
        raise
    except OSError as exc:
        raise ValidationError(f"{label}_unreadable", f"The {label.replace('_', ' ')} could not be read.") from exc

    if not data or len(data) > max_bytes:
        raise ValidationError(f"{label}_size_invalid", f"The {label.replace('_', ' ')} has an invalid size.")
    if data.startswith((b"\xef\xbb\xbf", b"\xff\xfe", b"\xfe\xff")):
        raise ValidationError(f"{label}_encoding_invalid", f"The {label.replace('_', ' ')} has an unexpected encoding.")
    try:
        text = data.decode("ascii")
    except UnicodeDecodeError as exc:
        raise ValidationError(f"{label}_encoding_invalid", f"The {label.replace('_', ' ')} is not canonical ASCII.") from exc

    if "\r" in text and not allow_crlf:
        raise ValidationError(f"{label}_format_invalid", f"The {label.replace('_', ' ')} is not in the generated LF format.")
    normalized = text.replace("\r\n", "\n")
    if "\r" in normalized or not normalized.endswith("\n"):
        raise ValidationError(f"{label}_format_invalid", f"The {label.replace('_', ' ')} has invalid line endings.")
    lines = normalized[:-1].split("\n")
    if not lines or any(not line for line in lines):
        raise ValidationError(f"{label}_format_invalid", f"The {label.replace('_', ' ')} contains a blank line.")

    ordered: list[tuple[str, str]] = []
    values: dict[str, str] = {}
    for line in lines:
        if not MARKER_LINE.fullmatch(line):
            raise ValidationError(f"{label}_marker_invalid", f"The {label.replace('_', ' ')} contains an unexpected marker.")
        key, value = line.split("=", 1)
        if key in values:
            raise ValidationError(f"{label}_duplicate_marker", f"The {label.replace('_', ' ')} repeats a marker.")
        ordered.append((key, value))
        values[key] = value

    return MarkerFile(tuple(ordered), values, hashlib.sha256(data).hexdigest())


def require_contract(markers: MarkerFile, contract: Sequence[tuple[str, str]], *, code: str) -> None:
    if markers.ordered != tuple(contract):
        raise ValidationError(code, "A marker file does not match the frozen acceptance contract.")


def typed_marker(value: str) -> object:
    if value == "True":
        return True
    if value == "False":
        return False
    if value.isdigit():
        return int(value)
    return value


def validate_host_result(path: Path) -> ResultEvidence:
    result = read_marker_file(path, label="host_result", max_bytes=MAX_RESULT_BYTES)
    status = result.values.get("TPS_PUBLIC_IPV4_HOST")
    if status == "PASS":
        require_contract(result, HOST_PASS_CONTRACT, code="host_result_contract_invalid")
        return ResultEvidence(
            role="host",
            status="pass",
            reason=None,
            markers={key: typed_marker(value) for key, value in result.ordered[1:]},
            sha256=result.sha256,
        )
    if status != "FAIL":
        raise ValidationError("host_result_role_invalid", "The host result does not identify a host pass or failure.")

    keys = tuple(key for key, _ in result.ordered)
    if keys not in HOST_FAILURE_KEY_ORDERS:
        raise ValidationError("host_result_contract_invalid", "The host failure result has unexpected or missing markers.")
    reason = result.values.get("REASON")
    if reason not in HOST_FAILURE_REASONS:
        raise ValidationError("host_result_reason_invalid", "The host failure reason is not allowed by the frozen probe.")
    if len(keys) == 4 and reason not in HOST_EARLY_FAILURE_REASONS:
        raise ValidationError("host_result_reason_shape_invalid", "The host failure reason cannot produce the reported marker shape.")
    if len(keys) == 6 and reason not in HOST_CLEANUP_FAILURE_REASONS:
        raise ValidationError("host_result_reason_shape_invalid", "The host failure reason cannot produce the reported marker shape.")
    if len(keys) == 5 and reason not in HOST_ABBREVIATED_FAILURE_REASONS:
        raise ValidationError("host_result_reason_shape_invalid", "The host failure reason cannot produce the reported marker shape.")
    if result.values.get("FINITE_LEASE_SECONDS") != "120" or result.values.get("NETWORK_DETAILS_RETAINED") != "False":
        raise ValidationError("host_result_safety_invalid", "The host failure result lost a required safety marker.")
    for key in ("LISTENER_CLOSED_BEFORE_DELETE", "DELETION_ACKNOWLEDGED"):
        if key in result.values and result.values[key] not in {"True", "False"}:
            raise ValidationError("host_result_safety_invalid", "The host cleanup marker is invalid.")
    if (
        result.values.get("DELETION_ACKNOWLEDGED") == "True"
        and result.values.get("LISTENER_CLOSED_BEFORE_DELETE") != "True"
    ):
        raise ValidationError(
            "host_result_safety_invalid",
            "The host result acknowledges deletion without proving listener closure first.",
        )
    if reason in {"cleanup_timeout", "deletion_not_acknowledged"} and result.values.get("DELETION_ACKNOWLEDGED") != "False":
        raise ValidationError("host_result_safety_invalid", "The host cleanup failure is internally inconsistent.")

    return ResultEvidence(
        role="host",
        status="fail",
        reason=reason,
        markers={
            key: typed_marker(value)
            for key, value in result.ordered
            if key not in {"TPS_PUBLIC_IPV4_HOST", "REASON"}
        },
        sha256=result.sha256,
    )


def validate_guest_result(path: Path) -> ResultEvidence:
    result = read_marker_file(path, label="guest_result", max_bytes=MAX_RESULT_BYTES)
    status = result.values.get("TPS_PUBLIC_IPV4_GUEST")
    if status == "PASS":
        require_contract(result, GUEST_PASS_CONTRACT, code="guest_result_contract_invalid")
        return ResultEvidence(
            role="guest",
            status="pass",
            reason=None,
            markers={key: typed_marker(value) for key, value in result.ordered[1:]},
            sha256=result.sha256,
        )
    if status != "FAIL":
        raise ValidationError("guest_result_role_invalid", "The guest result does not identify a guest pass or failure.")

    expected_keys = ("TPS_PUBLIC_IPV4_GUEST", "REASON", "NETWORK_DETAILS_RETAINED")
    if tuple(key for key, _ in result.ordered) != expected_keys:
        raise ValidationError("guest_result_contract_invalid", "The guest failure result has unexpected or missing markers.")
    reason = result.values.get("REASON")
    if reason not in GUEST_FAILURE_REASONS:
        raise ValidationError("guest_result_reason_invalid", "The guest failure reason is not allowed by the frozen probe.")
    if result.values.get("NETWORK_DETAILS_RETAINED") != "False":
        raise ValidationError("guest_result_safety_invalid", "The guest failure result retained network details.")

    return ResultEvidence(
        role="guest",
        status="fail",
        reason=reason,
        markers={"NETWORK_DETAILS_RETAINED": False},
        sha256=result.sha256,
    )


def validate_reference_kit(
    kit_zip: Path,
    build_report_path: Path,
    expected_zip_sha256: str,
) -> tuple[str, str]:
    expected = expected_zip_sha256.lower()
    if not SHA256_TEXT.fullmatch(expected):
        raise ValidationError("expected_zip_hash_invalid", "The expected kit hash is not a SHA-256 value.")

    build = read_marker_file(
        build_report_path,
        label="build_report",
        max_bytes=MAX_BUILD_REPORT_BYTES,
        allow_crlf=True,
    )
    expected_build = BUILD_REPORT_CONTRACT + (("ZIP_SHA256", expected),)
    require_contract(build, expected_build, code="build_report_contract_invalid")
    if expected == FROZEN_KIT_SHA256 and build.sha256 != FROZEN_BUILD_REPORT_SHA256:
        raise ValidationError(
            "build_report_hash_mismatch",
            "The build report does not match the frozen acceptance profile.",
        )

    try:
        if not kit_zip.is_file():
            raise ValidationError("kit_zip_missing", "The reference acceptance ZIP is missing.")
        if expected == FROZEN_KIT_SHA256 and kit_zip.stat().st_size != FROZEN_KIT_BYTES:
            raise ValidationError(
                "kit_zip_size_mismatch",
                "The reference acceptance ZIP does not match the frozen byte count.",
            )
    except OSError as exc:
        raise ValidationError("kit_zip_unreadable", "The reference acceptance ZIP could not be inspected.") from exc
    actual = sha256_file(kit_zip)
    if actual != expected:
        raise ValidationError("kit_zip_hash_mismatch", "The reference acceptance ZIP does not match its frozen SHA-256.")
    return actual, build.sha256


def evidence_set_digest(kit_sha256: str, host_sha256: str, guest_sha256: str) -> str:
    digest = hashlib.sha256()
    for value in (
        "tps-public-ipv4-result-pair-v1",
        kit_sha256,
        host_sha256,
        guest_sha256,
    ):
        digest.update(value.encode("ascii"))
        digest.update(b"\0")
    return digest.hexdigest()


def evidence_json(evidence: ResultEvidence) -> dict[str, object]:
    return {
        "role": evidence.role,
        "status": evidence.status,
        "reason": evidence.reason,
        "sha256": evidence.sha256,
        "markers": dict(evidence.markers),
    }


def validate_result_pair(
    *,
    host_result: Path,
    guest_result: Path,
    kit_zip: Path,
    build_report: Path,
    expected_zip_sha256: str = FROZEN_KIT_SHA256,
    firewall_cleanup_confirmed: bool = False,
    same_attempt_confirmed: bool = False,
    now: datetime | None = None,
) -> dict[str, object]:
    if host_result.resolve(strict=False) == guest_result.resolve(strict=False):
        raise ValidationError("result_paths_not_distinct", "Host and guest evidence must be separate files.")
    kit_sha256, build_report_sha256 = validate_reference_kit(
        kit_zip,
        build_report,
        expected_zip_sha256,
    )
    host = validate_host_result(host_result)
    guest = validate_guest_result(guest_result)
    pair_passed = host.status == "pass" and guest.status == "pass"
    role_status_relationship = "same_status" if host.status == guest.status else "mixed_status"
    if (
        host.markers.get("LISTENER_CLOSED_BEFORE_DELETE") is True
        and host.markers.get("DELETION_ACKNOWLEDGED") is True
    ):
        router_cleanup_status = "pass"
    elif "DELETION_ACKNOWLEDGED" not in host.markers:
        router_cleanup_status = "not_required_before_mapping"
    else:
        router_cleanup_status = "fail"
    full_acceptance_ready = (
        pair_passed and firewall_cleanup_confirmed and same_attempt_confirmed
    )
    checked_at = now or datetime.now(timezone.utc)

    if full_acceptance_ready:
        acceptance_status = "pass_with_operator_confirmations"
        next_action = "retain_redacted_report"
    elif pair_passed and not same_attempt_confirmed:
        acceptance_status = "pending_same_attempt_confirmation"
        next_action = "confirm_fresh_extraction_and_same_attempt_results"
    elif pair_passed:
        acceptance_status = "pending_firewall_cleanup_confirmation"
        next_action = "confirm_temporary_firewall_rule_removed_marker"
    elif role_status_relationship == "mixed_status":
        acceptance_status = "failed_mixed_role_status"
        next_action = "review_both_role_outcomes"
    else:
        acceptance_status = "fail"
        next_action = "review_safe_failure_reasons"

    return {
        "schemaVersion": 1,
        "reportKind": "tps-public-ipv4-remote-result-intake",
        "checkedAtUtc": checked_at.astimezone(timezone.utc).isoformat().replace("+00:00", "Z"),
        "validationStatus": "valid",
        "artifact": {
            "artifactId": f"tps-public-ipv4-{kit_sha256[:16]}",
            "expectedZipSha256": expected_zip_sha256.lower(),
            "actualZipSha256": kit_sha256,
            "buildReportSha256": build_report_sha256,
            "referenceKitVerified": True,
        },
        "evidenceSetDigest": evidence_set_digest(kit_sha256, host.sha256, guest.sha256),
        "evidence": {
            "host": evidence_json(host),
            "guest": evidence_json(guest),
            "strictSchemaVerified": True,
            "networkDetailsRetained": False,
        },
        "outcome": {
            "probeResultPair": "pass" if pair_passed else "fail",
            "roleStatusRelationship": role_status_relationship,
            "routerMappingCleanup": router_cleanup_status,
            "firewallRuleCleanup": (
                "operator_confirmed" if firewall_cleanup_confirmed else "manual_confirmation_required"
            ),
            "sameAttemptFreshness": (
                "operator_confirmed" if same_attempt_confirmed else "manual_confirmation_required"
            ),
            "fullAcceptanceReady": full_acceptance_ready,
            "acceptanceStatus": acceptance_status,
            "nextAction": next_action,
        },
        "provenance": {
            "combinedReportBoundToReferenceArtifact": True,
            "resultFilesContainKitIdentifier": False,
            "resultOriginCryptographicallyProven": False,
            "sameRunIdentifierPresent": False,
            "sameRunPairingProven": False,
            "staleResultDetectionAvailable": False,
            "sameAttemptOperatorConfirmed": same_attempt_confirmed,
            "limitationCode": "frozen_result_schema_has_no_kit_identifier",
        },
        "privacy": {
            "rawPathsIncluded": False,
            "networkAddressesIncluded": False,
            "invitationsIncluded": False,
            "playerNamesIncluded": False,
            "rawLogsIncluded": False,
        },
    }


def paths_collide(report_path: Path, inputs: Sequence[Path]) -> bool:
    report_resolved = report_path.resolve(strict=False)
    return any(report_resolved == item.resolve(strict=False) for item in inputs)


def safe_file_exists(path: Path) -> bool:
    try:
        return path.is_file()
    except (OSError, RuntimeError):
        return False


def write_report(report_path: Path, report: Mapping[str, object]) -> None:
    temporary: Path | None = None
    descriptor: int | None = None
    try:
        report_path.parent.mkdir(parents=True, exist_ok=True)
        descriptor, temporary_name = tempfile.mkstemp(
            dir=report_path.parent,
            prefix=f".{report_path.name}.",
            suffix=".tmp",
        )
        temporary = Path(temporary_name)
        handle = os.fdopen(descriptor, "w", encoding="utf-8", newline="\n")
        descriptor = None
        with handle:
            handle.write(json.dumps(report, indent=2, sort_keys=True) + "\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, report_path)
    except OSError as exc:
        raise ValidationError("report_write_failed", "The redacted result report could not be written.") from exc
    finally:
        if descriptor is not None:
            try:
                os.close(descriptor)
            except OSError:
                pass
        if temporary is not None and temporary.exists():
            try:
                temporary.unlink()
            except OSError:
                pass


def invalid_report(code: str, *, now: datetime | None = None) -> dict[str, object]:
    checked_at = now or datetime.now(timezone.utc)
    return {
        "schemaVersion": 1,
        "reportKind": "tps-public-ipv4-remote-result-intake",
        "checkedAtUtc": checked_at.astimezone(timezone.utc).isoformat().replace("+00:00", "Z"),
        "validationStatus": "invalid",
        "reasonCode": code,
        "outcome": {"fullAcceptanceReady": False},
        "privacy": {
            "untrustedInputCopiedToReport": False,
            "rawPathsIncluded": False,
            "networkAddressesIncluded": False,
            "invitationsIncluded": False,
        },
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Strictly validate the frozen public-IPv4 host and guest result files.",
    )
    parser.add_argument("--host-result", type=Path, required=True)
    parser.add_argument("--guest-result", type=Path, required=True)
    parser.add_argument("--kit-zip", type=Path, default=DEFAULT_KIT_ZIP)
    parser.add_argument("--build-report", type=Path, default=DEFAULT_BUILD_REPORT)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    parser.add_argument(
        "--firewall-cleanup-confirmed",
        action="store_true",
        help=(
            "Use only after the Host terminal showed "
            "TEMPORARY_FIREWALL_RULE_REMOVED=True. This is recorded as an operator confirmation."
        ),
    )
    parser.add_argument(
        "--same-attempt-confirmed",
        action="store_true",
        help=(
            "Use only when both files were collected immediately from one attempt "
            "that began with a fresh extraction. This is an operator confirmation."
        ),
    )
    return parser


def main(
    argv: Sequence[str] | None = None,
    *,
    expected_zip_sha256: str = FROZEN_KIT_SHA256,
) -> int:
    args = build_parser().parse_args(argv)
    input_paths = (args.host_result, args.guest_result, args.kit_zip, args.build_report)
    try:
        collision = paths_collide(args.report, input_paths)
    except (OSError, RuntimeError):
        print("TPS_PUBLIC_IPV4_RESULT_VALIDATION=FAIL")
        print("REASON=report_path_invalid")
        print("REPORT_UPDATED=False")
        print("STALE_REPORT_POSSIBLE=False")
        print("The output report path could not be resolved safely.", file=sys.stderr)
        return 2
    if collision:
        error = ValidationError("report_path_collides_with_input", "The output report path would overwrite evidence.")
        print("TPS_PUBLIC_IPV4_RESULT_VALIDATION=FAIL")
        print(f"REASON={error.code}")
        print("REPORT_UPDATED=False")
        print(
            "STALE_REPORT_POSSIBLE="
            + ("True" if safe_file_exists(args.report) else "False")
        )
        print(str(error), file=sys.stderr)
        return 2

    try:
        report = validate_result_pair(
            host_result=args.host_result,
            guest_result=args.guest_result,
            kit_zip=args.kit_zip,
            build_report=args.build_report,
            expected_zip_sha256=expected_zip_sha256,
            firewall_cleanup_confirmed=args.firewall_cleanup_confirmed,
            same_attempt_confirmed=args.same_attempt_confirmed,
        )
        write_report(args.report, report)
    except ValidationError as error:
        report_updated = False
        try:
            write_report(args.report, invalid_report(error.code))
            report_updated = True
        except ValidationError as report_error:
            print(str(report_error), file=sys.stderr)
        print("TPS_PUBLIC_IPV4_RESULT_VALIDATION=FAIL")
        print(f"REASON={error.code}")
        print("REPORT_UPDATED=" + ("True" if report_updated else "False"))
        print(
            "STALE_REPORT_POSSIBLE="
            + (
                "True"
                if not report_updated and safe_file_exists(args.report)
                else "False"
            )
        )
        if not report_updated:
            print("WARNING=report_not_updated_do_not_trust_prior_report")
        print(str(error), file=sys.stderr)
        return 2

    pair_status = report["outcome"]["probeResultPair"]
    print("TPS_PUBLIC_IPV4_RESULT_VALIDATION=PASS")
    print("REPORT_UPDATED=True")
    print("REFERENCE_KIT_VERIFIED=True")
    print(f"RESULT_PAIR={str(pair_status).upper()}")
    print(
        "FULL_ACCEPTANCE_READY="
        + ("True" if report["outcome"]["fullAcceptanceReady"] else "False")
    )
    print(
        "FIREWALL_CONFIRMATION_REQUIRED="
        + ("False" if args.firewall_cleanup_confirmed else "True")
    )
    print(
        "SAME_ATTEMPT_CONFIRMATION_REQUIRED="
        + ("False" if args.same_attempt_confirmed else "True")
    )
    print(
        "ACCEPTANCE_GATE="
        + (
            "PASS"
            if report["outcome"]["fullAcceptanceReady"]
            else "PENDING_OPERATOR_CONFIRMATIONS"
            if pair_status == "pass"
            else "FAIL"
        )
    )
    print(f"REPORT={args.report.resolve(strict=False)}")
    return 0 if pair_status == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
