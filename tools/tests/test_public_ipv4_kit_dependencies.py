from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
BUILD_SCRIPT = REPO_ROOT / "tools" / "build_public_ipv4_mapping_probe.ps1"


def ps_quote(value: Path | str) -> str:
    return "'" + str(value).replace("'", "''") + "'"


class PublicIpv4KitDependencyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.powershell = shutil.which("powershell.exe")
        if not cls.powershell:
            raise unittest.SkipTest("Windows PowerShell is unavailable.")

    def run_builder_functions(self, body: str) -> subprocess.CompletedProcess[str]:
        # Load only function definitions and, when requested, the source map.
        # The real builder is never executed: the frozen kit stays untouched.
        command = f"""
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile(
    {ps_quote(BUILD_SCRIPT)}, [ref]$tokens, [ref]$errors)
if ($errors.Count -ne 0) {{ throw 'Builder syntax is invalid.' }}
$wanted = @('Assert-File','Add-LuaSourceDependencies','Assert-NoExternalServicePaths')
$functions = $ast.FindAll({{
    param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -in $wanted
}}, $true)
foreach ($function in $functions) {{ Invoke-Expression $function.Extent.Text }}
{body}
"""
        return subprocess.run(
            [self.powershell, "-NoProfile", "-NonInteractive", "-Command", command],
            check=False,
            capture_output=True,
            text=True,
            timeout=30,
        )

    def test_current_probe_modules_load_from_isolated_dependency_package(self) -> None:
        completed = self.run_builder_functions(f"""
$repoRoot = {ps_quote(REPO_ROOT)}
$probeSourceRoot = Join-Path $repoRoot 'tools/probes/public_ipv4_mapping'
$assignment = $ast.Find({{
    param($node)
    $node -is [Management.Automation.Language.AssignmentStatementAst] -and
        $node.Left.Extent.Text -eq '$appFiles'
}}, $true)
Invoke-Expression $assignment.Extent.Text
Add-LuaSourceDependencies $appFiles $repoRoot
foreach ($relative in $appFiles.Keys) {{
    Assert-NoExternalServicePaths $relative (Get-Content -Raw -LiteralPath $appFiles[$relative])
}}
$appFiles | ConvertTo-Json -Compress
""")
        self.assertEqual(0, completed.returncode, completed.stderr)
        files = json.loads(completed.stdout)
        self.assertIn("src/net/interface_addresses.lua", files)
        for directory in ("transport_direct", "upnp_igd"):
            for source in (REPO_ROOT / "src" / "net" / directory).glob("*.lua"):
                self.assertIn(source.relative_to(REPO_ROOT).as_posix(), files)

        runtime = shutil.which("lovec.exe") or str(Path(os.environ.get(
            "ProgramFiles", "C:/Program Files"
        )) / "LOVE" / "lovec.exe")
        if not Path(runtime).is_file():
            self.skipTest("LÖVE console runtime is unavailable for isolated module loading.")
        with tempfile.TemporaryDirectory() as temporary:
            stage = Path(temporary)
            modules = []
            for relative, source in files.items():
                destination = stage / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, destination)
                if relative.startswith("src/"):
                    modules.append(relative[:-4].replace("/", "."))
            lua_modules = ",".join(json.dumps(module) for module in modules)
            (stage / "main.lua").write_text(
                'package.path = ""\n'
                'function love.load()\n'
                f'  for _, module in ipairs({{{lua_modules}}}) do require(module) end\n'
                '  print("TPS_ISOLATED_MODULE_LOAD=PASS")\n'
                '  love.event.quit(0)\n'
                'end\n', encoding="utf-8"
            )
            (stage / "conf.lua").write_text(
                'function love.conf(t)\n'
                '  t.window = false\n'
                '  t.modules.audio = false\n'
                '  t.modules.graphics = false\n'
                '  t.modules.joystick = false\n'
                '  t.modules.physics = false\n'
                '  t.modules.sound = false\n'
                'end\n', encoding="utf-8"
            )
            loaded = subprocess.run(
                [runtime, str(stage)], cwd=stage, check=False,
                capture_output=True, text=True, timeout=30,
                creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
            )
            self.assertEqual(0, loaded.returncode, loaded.stderr + loaded.stdout)
            self.assertIn("TPS_ISOLATED_MODULE_LOAD=PASS", loaded.stdout)

    def test_transitive_and_optional_requires_are_included_without_cycles(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "src").mkdir()
            (root / "main.lua").write_text('require("src.first")', encoding="utf-8")
            (root / "src/first.lua").write_text(
                'pcall(require, "src.second")', encoding="utf-8"
            )
            (root / "src/second.lua").write_text(
                "require 'src.first'", encoding="utf-8"
            )
            completed = self.run_builder_functions(f"""
$root = {ps_quote(root)}
$files = [ordered]@{{ 'main.lua' = Join-Path $root 'main.lua' }}
Add-LuaSourceDependencies $files $root
@($files.Keys) | ConvertTo-Json -Compress
""")
            self.assertEqual(0, completed.returncode, completed.stderr)
            self.assertEqual(
                {"main.lua", "src/first.lua", "src/second.lua"},
                set(json.loads(completed.stdout)),
            )

    def test_missing_transitive_source_stops_packaging(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "main.lua").write_text('require("src.missing")', encoding="utf-8")
            completed = self.run_builder_functions(f"""
$root = {ps_quote(root)}
$files = [ordered]@{{ 'main.lua' = Join-Path $root 'main.lua' }}
Add-LuaSourceDependencies $files $root
""")
            self.assertNotEqual(0, completed.returncode)
            self.assertIn("Required Lua dependency of main.lua is missing", completed.stderr)

    def test_service_scan_exceptions_do_not_admit_remote_urls(self) -> None:
        for relative in ("src/net/upnp_igd/urls.lua", "src/net/other/urls.lua"):
            with self.subTest(relative=relative):
                completed = self.run_builder_functions(
                    "Assert-NoExternalServicePaths " + ps_quote(relative)
                    + " " + ps_quote('return "https://example.invalid/service"')
                )
                self.assertNotEqual(0, completed.returncode)
                self.assertIn("external-service path", completed.stderr)
        completed = self.run_builder_functions(
            "Assert-NoExternalServicePaths 'src/net/other/urls.lua' "
            + ps_quote('return "http://" .. host')
        )
        self.assertNotEqual(0, completed.returncode)


if __name__ == "__main__":
    unittest.main()
