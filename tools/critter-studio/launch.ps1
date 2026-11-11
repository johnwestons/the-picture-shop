param([ValidateSet('voices','soundscape')][string]$Section='voices')
$ErrorActionPreference = 'Stop'
$studioUrl = 'http://127.0.0.1:43127'
try { $studioReady = Invoke-RestMethod "$studioUrl/api/library" -TimeoutSec 2 } catch { $studioReady = $null }
if (-not $studioReady.characters) {
    $studioNode = Get-Command node.exe -ErrorAction SilentlyContinue
    $studioNodePath = if ($studioNode) { $studioNode.Source } else { $null }
    if (-not $studioNodePath) {
        foreach ($studioPackage in (Get-AppxPackage '*CodexPrimaryRuntime*' | Sort-Object Version -Descending)) {
            $studioCandidate = Join-Path $studioPackage.InstallLocation 'dependencies\node\bin\node.exe'
            if (Test-Path -LiteralPath $studioCandidate) { $studioNodePath = $studioCandidate; break }
        }
    }
    if (-not $studioNodePath) { throw 'Node.js is required. Install Node.js or launch this studio from Codex.' }
    Start-Process -FilePath $studioNodePath -ArgumentList ('"' + (Join-Path $PSScriptRoot 'server.mjs') + '"') -WorkingDirectory $PSScriptRoot -WindowStyle Hidden
    for ($studioAttempt=0; $studioAttempt -lt 30; $studioAttempt++) {
        Start-Sleep -Milliseconds 200
        try { $studioReady = Invoke-RestMethod "$studioUrl/api/library" -TimeoutSec 1; break } catch {}
    }
    if (-not $studioReady.characters) { throw 'The recording studio could not start on port 43127.' }
}
if ($Section -eq 'soundscape') { $studioUrl += '/soundscape' }
Start-Process $studioUrl
