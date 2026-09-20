from __future__ import annotations

import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
RUNNER = (
    REPO_ROOT
    / "tools"
    / "probes"
    / "public_ipv4_mapping"
    / "windows"
    / "run_host.ps1"
)
TRAFFIC_RUNNER = RUNNER.with_name("run_mapping_traffic_check.ps1")
PROBE_MAIN = RUNNER.parents[1] / "main.lua"
BUILD_SCRIPT = REPO_ROOT / "tools" / "build_public_ipv4_mapping_probe.ps1"
IPV6_READINESS = RUNNER.with_name("run_ipv6_readiness.ps1")


class PublicIpv4HostLauncherTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.script = RUNNER.read_text(encoding="utf-8")

    def test_empty_owned_rule_queries_are_forced_to_arrays(self) -> None:
        self.assertNotIn("(Get-OwnedRule).Count", self.script)
        self.assertEqual(3, self.script.count("(@(Get-OwnedRule)).Count"))

    def test_packaged_app_rules_are_not_treated_as_global(self) -> None:
        self.assertIn("PackageFamilyName", self.script)
        self.assertIn("PolicyAppId", self.script)
        self.assertIn("Store/AppContainer", self.script)

    def test_broad_rule_check_is_scoped_to_active_network(self) -> None:
        self.assertIn("Test-RuleProfileApplies", self.script)
        self.assertIn("Test-RuleInterfaceApplies", self.script)
        self.assertIn("Test-RuleAllowsInternet", self.script)
        self.assertIn("Assert-NoBroadExistingRule $Context", self.script)

    def test_preflight_defers_privileged_firewall_query(self) -> None:
        self.assertIn("choose Cancel if Windows asks", self.script)
        preflight = self.script.split("if ($Action -eq 'Preflight') {", 1)[1]
        preflight = preflight.split("$wan = Read-Host", 1)[0]
        self.assertNotIn("Get-ActiveRouteContext", preflight)
        self.assertNotIn("Assert-NoBroadExistingRule", preflight)

    def test_mapping_reports_successful_broad_rule_audit(self) -> None:
        self.assertIn("BROAD_PROBE_FIREWALL_RULE_ABSENT=True", self.script)

    def test_older_windows_appcontainer_marker_is_checked(self) -> None:
        self.assertIn("applicationPackage", self.script)
        self.assertIn("$application[0].Package", self.script)
        self.assertIn("Older Windows versions expose", self.script)

    def test_elevated_window_preserves_results(self) -> None:
        self.assertIn("'-NoExit -NoProfile", self.script)

    def test_cleanup_uses_old_windows_compatible_parameter_set(self) -> None:
        self.assertNotIn(
            "$rule | Remove-NetFirewallRule -PolicyStore", self.script
        )
        self.assertNotIn(
            "$rules[0] | Remove-NetFirewallRule -PolicyStore", self.script
        )
        self.assertIn(
            "Remove-NetFirewallRule -Name $ruleName -PolicyStore", self.script
        )

    def test_accidental_rule_cleanup_is_narrow_and_guarded(self) -> None:
        self.assertIn("Get-AccidentalProbeRules", self.script)
        self.assertIn("Remove-AccidentalProbeRules", self.script)
        self.assertIn("\\The Picture Shop Public IPv4 Remote Test", self.script)
        self.assertIn("^(TCP|UDP) Query User", self.script)
        self.assertIn("REMOVE ACCIDENTAL TEST RULES", self.script)
        self.assertIn("ACCIDENTAL_TEST_FIREWALL_RULES_ABSENT=True", self.script)

    def test_mapping_traffic_role_uses_the_same_guarded_launcher(self) -> None:
        self.assertIn("'Map','Traffic','Cleanup'", self.script)
        self.assertIn("$Action -eq 'Traffic'", self.script)
        self.assertIn("Invoke-Probe -Role $probeRole", self.script)


class PublicIpv4MappingTrafficCheckTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.script = TRAFFIC_RUNNER.read_text(encoding="utf-8")
        cls.main = PROBE_MAIN.read_text(encoding="utf-8")
        cls.builder = BUILD_SCRIPT.read_text(encoding="utf-8")

    def test_uses_udp_5351_nic_counters_without_packet_logging(self) -> None:
        self.assertIn("'filter','add',$filterName,'-d','IPv4'", self.script)
        self.assertIn("'-t','UDP','-p',[string]$mappingPort", self.script)
        self.assertIn("'--capture','--counters-only'", self.script)
        self.assertIn("'--comp','nics','--type','all'", self.script)
        self.assertNotIn("'--file-name'", self.script)
        self.assertNotIn("'--pkt-size'", self.script)
        self.assertNotIn("etl2", self.script.lower())

    def test_refuses_preexisting_global_pktmon_state(self) -> None:
        self.assertIn("Another Windows Packet Monitor session", self.script)
        self.assertIn("already has filters; they were not changed", self.script)
        self.assertIn("Test-EmptyFilterList", self.script)
        self.assertIn("Test-ExactOwnedFilterList", self.script)

    def test_cleanup_stops_before_removing_the_only_verified_filter(self) -> None:
        stop = self.script.index("$stopped = Invoke-PktMon @('stop')")
        remove = self.script.index("$removed = Invoke-PktMon @('filter','remove')")
        self.assertLess(stop, remove)
        self.assertIn("Packet Monitor filters changed; no filters were removed", self.script)
        self.assertIn("-Action Cleanup", (
            TRAFFIC_RUNNER.with_name("Cleanup Mapping Traffic Check.bat")
        ).read_text(encoding="utf-8"))

    def test_result_retains_only_boolean_and_safe_outcome_markers(self) -> None:
        self.assertIn("UDP_5351_NIC_TX_OBSERVED=", self.script)
        self.assertIn("UDP_5351_NIC_RX_OBSERVED=", self.script)
        self.assertIn("PACKET_CONTENTS_RETAINED=False", self.script)
        self.assertIn("NETWORK_DETAILS_RETAINED=False", self.script)
        self.assertIn("TEMPORARY_FIREWALL_RULE_REMOVED=", self.script)
        self.assertNotIn("sourceAddress", self.script)
        self.assertNotIn("$lines += @(", self.script)
        self.assertIn("$safeLines = [string[]]$lines", self.script)

    def test_windows_powershell_51_writes_one_marker_per_line(self) -> None:
        powershell = shutil.which("powershell.exe")
        if not powershell:
            self.skipTest("Windows PowerShell is unavailable.")
        with tempfile.TemporaryDirectory() as temporary:
            result = Path(temporary) / "traffic-result.txt"
            script_path = str(TRAFFIC_RUNNER).replace("'", "''")
            result_path = str(result).replace("'", "''")
            command = f"""
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile(
    '{script_path}', [ref]$tokens, [ref]$errors)
if ($errors.Count -ne 0) {{ exit 20 }}
$wanted = @('Get-BooleanMarker','Write-SafeResult')
$functions = $ast.FindAll({{
    param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -in $wanted
}}, $true)
foreach ($function in $functions) {{ Invoke-Expression $function.Extent.Text }}
$resultPath = '{result_path}'
$hostOutcome = 'mapping_timeout'
$txObserved = $true
$rxObserved = $false
$counterSchemaRecognized = $true
$captureStopped = $true
$filterRemoved = $true
$firewallRuleRemoved = $true
Write-SafeResult $false 'traffic_probe_failed' | Out-Null
"""
            completed = subprocess.run(
                [powershell, "-NoProfile", "-Command", command],
                check=False,
                capture_output=True,
                text=True,
                timeout=30,
            )
            self.assertEqual(0, completed.returncode, completed.stderr)
            self.assertEqual(
                [
                    "TPS_MAPPING_TRAFFIC_CHECK=FAIL",
                    "REASON=traffic_probe_failed",
                    "HOST_MAPPING_OUTCOME=mapping_timeout",
                    "COUNTERS_ONLY=True",
                    "PACKET_LOGGING=False",
                    "UDP_5351_NIC_TX_OBSERVED=True",
                    "UDP_5351_NIC_RX_OBSERVED=False",
                    "COUNTER_SCHEMA_RECOGNIZED=True",
                    "PKTMON_STOPPED=True",
                    "PKTMON_FILTER_REMOVED=True",
                    "TEMPORARY_FIREWALL_RULE_REMOVED=True",
                    "PACKET_CONTENTS_RETAINED=False",
                    "NETWORK_DETAILS_RETAINED=False",
                ],
                result.read_text(encoding="utf-8").splitlines(),
            )

    def test_windows_powershell_51_parses_numeric_pktmon_direction_tags(self) -> None:
        powershell = shutil.which("powershell.exe")
        if not powershell:
            self.skipTest("Windows PowerShell is unavailable.")
        script_path = str(TRAFFIC_RUNNER).replace("'", "''")
        command = f"""
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile(
    '{script_path}', [ref]$tokens, [ref]$errors)
if ($errors.Count -ne 0) {{ exit 20 }}
$wanted = @(
    'Get-DirectionToken','Get-NumericDirectionToken','Test-MetricName',
    'Test-NumericValue','Test-PositiveMetricValue','Visit-CounterJson',
    'Get-CounterSummary'
)
$functions = $ast.FindAll({{
    param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -in $wanted
}}, $true)
foreach ($function in $functions) {{ Invoke-Expression $function.Extent.Text }}
$json = '{{"Counters":[{{"ComponentId":7,"DirectionTag":4,"Packets":5,"Bytes":300}},{{"ComponentId":7,"DirectionTag":3,"Packets":0,"Bytes":0}}]}}'
$summary = Get-CounterSummary $json
if (-not $summary.Recognized -or -not $summary.Tx -or $summary.Rx) {{ exit 21 }}
"""
        completed = subprocess.run(
            [powershell, "-NoProfile", "-Command", command],
            check=False,
            capture_output=True,
            text=True,
            timeout=30,
        )
        self.assertEqual(0, completed.returncode, completed.stderr)

    def test_traffic_probe_cleans_up_immediately_if_mapping_succeeds(self) -> None:
        self.assertIn('local trafficOnly = role == "traffic"', self.main)
        self.assertIn('if trafficOnly then\n                beginHostCleanup(true)', self.main)
        self.assertIn('"TPS_PUBLIC_IPV4_TRAFFIC"', self.main)
        self.assertIn("Start-Sleep -Milliseconds 3000", self.script)

    def test_builder_packages_and_parses_the_traffic_launcher(self) -> None:
        self.assertIn("run_mapping_traffic_check.ps1", self.builder)
        self.assertIn("Start Host Mapping Traffic Check.bat", self.builder)
        self.assertIn("Cleanup Mapping Traffic Check.bat", self.builder)
        self.assertIn("The counters-only traffic check unexpectedly", self.builder)


class Ipv6ReadinessCheckTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.script = IPV6_READINESS.read_text(encoding="utf-8")
        cls.builder = BUILD_SCRIPT.read_text(encoding="utf-8")

    def test_is_read_only_and_retains_no_address(self) -> None:
        self.assertIn("TPS_IPV6_LOCAL_READINESS=", self.script)
        self.assertIn("INBOUND_REACHABILITY_PROVEN=False", self.script)
        self.assertIn("NETWORK_TRAFFIC_SENT=False", self.script)
        self.assertIn("NETWORK_DETAILS_RETAINED=False", self.script)
        self.assertNotIn("Invoke-WebRequest", self.script)
        self.assertNotIn("Test-NetConnection", self.script)
        self.assertNotIn("Write-Output $address", self.script)

    def test_both_package_roles_receive_the_same_checker(self) -> None:
        self.assertIn("foreach ($destinationRoot in @($hostRoot,$guestRoot))", self.builder)
        self.assertIn("'run_ipv6_readiness.ps1'", self.builder)
        self.assertIn("'Check IPv6 Readiness.bat'", self.builder)


if __name__ == "__main__":
    unittest.main()
