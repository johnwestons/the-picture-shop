param([switch]$Smoke)
$ErrorActionPreference='Stop'
$labRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$labNode=(Get-Command node.exe -ErrorAction SilentlyContinue).Source
if (-not $labNode) {
    foreach ($labPackage in (Get-AppxPackage '*CodexPrimaryRuntime*' | Sort-Object Version -Descending)) {
        $labCandidate=Join-Path $labPackage.InstallLocation 'dependencies/node/bin/node.exe'
        if (Test-Path -LiteralPath $labCandidate) { $labNode=$labCandidate; break }
    }
}
if (-not $labNode) { throw 'Node.js is required to prepare the selected audio snapshot.' }
$labLove=(Get-Command love.exe -ErrorAction SilentlyContinue).Source
if (-not $labLove) { $labLove=Join-Path $env:ProgramFiles 'LOVE/love.exe' }
if (-not (Test-Path -LiteralPath $labLove)) { throw 'LOVE 11.x was not found.' }
# Only this standalone lab's disposable identity is reset, never main-game saves.
$labSaveRoot=[IO.Path]::GetFullPath((Join-Path $env:APPDATA 'LOVE'))
$labSave=[IO.Path]::GetFullPath((Join-Path $labSaveRoot 'the-picture-shop-dialogue-lab'))
if ((Split-Path $labSave -Parent) -ne $labSaveRoot -or (Split-Path $labSave -Leaf) -ne 'the-picture-shop-dialogue-lab') { throw 'Unexpected lab save path.' }
if (Test-Path -LiteralPath $labSave) { Remove-Item -LiteralPath $labSave -Recurse -Force }
& $labNode (Join-Path $PSScriptRoot 'prepare.mjs')
if ($LASTEXITCODE -ne 0) { throw 'Could not prepare the dialogue snapshot.' }
$labStage=Join-Path $labRoot 'output/dialogue-lab'
if ($Smoke) {
    $env:PICTURE_SHOP_DIALOGUE_SMOKE='1'
    $labReport=Join-Path $labStage 'smoke-report.txt'
    if (Test-Path -LiteralPath $labReport) { Remove-Item -LiteralPath $labReport }
    try {
        $labProcess=Start-Process -FilePath $labLove -ArgumentList ('"'+$labStage+'"') -PassThru -WindowStyle Hidden
        if (-not $labProcess.WaitForExit(30000)) { $labProcess.Kill(); throw 'Dialogue smoke timed out.' }
        if (-not (Test-Path -LiteralPath $labReport)) { throw 'Smoke did not produce a report.' }
        Get-Content -LiteralPath $labReport
        if ($labProcess.ExitCode -ne 0 -or -not (Select-String -LiteralPath $labReport -Pattern 'DIALOGUE_SMOKE_OK' -Quiet)) { throw 'Dialogue smoke failed.' }
    } finally { Remove-Item Env:PICTURE_SHOP_DIALOGUE_SMOKE -ErrorAction SilentlyContinue }
} else {
    Remove-Item Env:PICTURE_SHOP_DIALOGUE_SMOKE -ErrorAction SilentlyContinue
    Start-Process -FilePath $labLove -ArgumentList ('"'+$labStage+'"')
}
