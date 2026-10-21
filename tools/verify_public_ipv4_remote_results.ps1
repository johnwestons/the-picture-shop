[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$HostResult,

    [Parameter(Mandatory = $true)]
    [string]$GuestResult,

    [string]$KitZip,
    [string]$BuildReport,
    [string]$ReportPath,
    [ValidatePattern('^[0-9a-fA-F]{64}$')]
    [string]$ExpectedZipSha256,
    [ValidatePattern('^[0-9a-f]{40}$')]
    [string]$ExpectedSourceCommit,
    [ValidateSet('True','False')]
    [string]$ExpectedSourceDirty,
    [switch]$FirewallCleanupConfirmed,
    [switch]$SameAttemptConfirmed
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$validator = Join-Path $PSScriptRoot 'verify_public_ipv4_remote_results.py'
$profileOptions = @('ExpectedZipSha256','ExpectedSourceCommit','ExpectedSourceDirty')
$providedProfileOptions = @($profileOptions | Where-Object { $PSBoundParameters.ContainsKey($_) })
if ($providedProfileOptions.Count -ne 0 -and $providedProfileOptions.Count -ne 3) {
    throw 'ExpectedZipSha256, ExpectedSourceCommit, and ExpectedSourceDirty must be supplied together.'
}

function Find-ValidationPython {
    $candidates = @(
        (Join-Path $env:USERPROFILE `
            '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe')
    )
    foreach ($name in @('python.exe','python','py.exe','py')) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($command) { $candidates += $command.Source }
    }
    foreach ($candidate in @($candidates | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
        & $candidate -c `
            'import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)' `
            *> $null
        if ($LASTEXITCODE -eq 0) { return $candidate }
    }
    throw 'Python 3.10+ was not found. Install it or use the bundled Codex workspace runtime.'
}

if (-not (Test-Path -LiteralPath $validator -PathType Leaf)) {
    throw 'The public IPv4 result validator is missing.'
}

$arguments = @(
    $validator,
    '--host-result', [IO.Path]::GetFullPath($HostResult),
    '--guest-result', [IO.Path]::GetFullPath($GuestResult)
)
if ($KitZip) {
    $arguments += @('--kit-zip', [IO.Path]::GetFullPath($KitZip))
}
if ($BuildReport) {
    $arguments += @('--build-report', [IO.Path]::GetFullPath($BuildReport))
}
if ($ReportPath) {
    $arguments += @('--report', [IO.Path]::GetFullPath($ReportPath))
}
if ($providedProfileOptions.Count -eq 3) {
    $arguments += @('--expected-zip-sha256', $ExpectedZipSha256,
        '--expected-source-commit', $ExpectedSourceCommit,
        '--expected-source-dirty', $ExpectedSourceDirty)
}
if ($FirewallCleanupConfirmed) {
    $arguments += '--firewall-cleanup-confirmed'
}
if ($SameAttemptConfirmed) {
    $arguments += '--same-attempt-confirmed'
}

$python = Find-ValidationPython
& $python @arguments
exit $LASTEXITCODE
