$ErrorActionPreference='Stop'
$keiRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$keiOutput=Join-Path $keiRoot 'output/kei-scale-repair'
$keiStage=Join-Path $keiOutput 'runtime'
$keiSave=Join-Path $env:APPDATA 'LOVE/the-picture-shop-test-kei-rotation'
if (Test-Path -LiteralPath $keiSave) {
    $resolved=[IO.Path]::GetFullPath($keiSave)
    $expected=[IO.Path]::GetFullPath((Join-Path $env:APPDATA 'LOVE/the-picture-shop-test-kei-rotation'))
    if ($resolved -ne $expected) { throw 'Unexpected kei review save path' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
New-Item -ItemType Directory -Force $keiStage | Out-Null
Copy-Item -LiteralPath (Join-Path $keiRoot 'src') -Destination $keiStage -Recurse -Force
$keiAssets=Join-Path $keiStage 'assets/commute/truck'
$keiReference=Join-Path $keiStage 'output/kei-scale-repair/before'
New-Item -ItemType Directory -Force $keiAssets,$keiReference | Out-Null
foreach ($folder in @('kei-turntables','decals')) {
    Copy-Item -LiteralPath (Join-Path $keiRoot "assets/commute/truck/$folder") -Destination $keiAssets -Recurse -Force
}
$keiBaseline=Join-Path $keiOutput 'before'
if (-not (Test-Path -LiteralPath $keiBaseline)) { $keiBaseline=Join-Path $keiRoot 'assets/commute/truck/kei-turntables' }
Copy-Item -Path (Join-Path $keiBaseline '*.png') -Destination $keiReference -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'kei_turntable_review.lua') -Destination (Join-Path $keiStage 'main.lua') -Force
@'
function love.conf(t)
    t.identity='the-picture-shop-test-kei-rotation'
    t.version='11.5';t.window.visible=false;t.window.vsync=0
    t.window.width=840;t.window.height=680;t.modules.audio=false
end
'@ | Set-Content -LiteralPath (Join-Path $keiStage 'conf.lua') -Encoding utf8NoBOM
$env:KEI_REVIEW_ROOT=$keiRoot.Replace('\','/')
try {
    $keiProcess=Start-Process -FilePath 'C:\Program Files\LOVE\lovec.exe' -ArgumentList ('"'+$keiStage+'"') -WorkingDirectory $keiRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $keiOutput 'review.log') -RedirectStandardError (Join-Path $keiOutput 'review-errors.log')
    if (-not $keiProcess.WaitForExit(60000)) { Stop-Process -Id $keiProcess.Id -Force;throw 'Kei rotation review timed out' }
    Get-Content (Join-Path $keiOutput 'review.log')
    Get-Content (Join-Path $keiOutput 'review-errors.log')
    if ($keiProcess.ExitCode -ne 0) { throw 'Kei rotation review failed' }
} finally { Remove-Item Env:KEI_REVIEW_ROOT -ErrorAction SilentlyContinue }
