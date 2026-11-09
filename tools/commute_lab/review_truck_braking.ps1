$ErrorActionPreference='Stop'
$brakingRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$brakingOutput=Join-Path $brakingRoot 'output/truck-braking-review'
$brakingStage=Join-Path $brakingOutput 'runtime'
$brakingSave=Join-Path $env:APPDATA 'LOVE/the-picture-shop-test-truck-braking'
if (Test-Path -LiteralPath $brakingSave) {
    $resolved=[IO.Path]::GetFullPath($brakingSave)
    $expected=[IO.Path]::GetFullPath((Join-Path $env:APPDATA 'LOVE/the-picture-shop-test-truck-braking'))
    if ($resolved -ne $expected) { throw 'Unexpected truck braking test save path' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
New-Item -ItemType Directory -Force $brakingStage | Out-Null
Copy-Item -LiteralPath (Join-Path $brakingRoot 'src') -Destination $brakingStage -Recurse -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'truck_braking_review.lua') -Destination (Join-Path $brakingStage 'main.lua') -Force
@'
function love.conf(t)
    t.identity='the-picture-shop-test-truck-braking';t.version='11.5'
    t.window=nil;t.modules.window=false;t.modules.graphics=false;t.modules.audio=false
end
'@ | Set-Content -LiteralPath (Join-Path $brakingStage 'conf.lua') -Encoding utf8NoBOM
$env:TRUCK_BRAKING_REVIEW_ROOT=$brakingRoot.Replace('\','/')
try {
    $brakingProcess=Start-Process -FilePath 'C:\Program Files\LOVE\lovec.exe' -ArgumentList ('"'+$brakingStage+'"') -WorkingDirectory $brakingRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $brakingOutput 'review.log') -RedirectStandardError (Join-Path $brakingOutput 'errors.log')
    if (-not $brakingProcess.WaitForExit(60000)) { Stop-Process -Id $brakingProcess.Id -Force;throw 'Truck braking review timed out' }
    Get-Content (Join-Path $brakingOutput 'review.log')
    Get-Content (Join-Path $brakingOutput 'errors.log')
    if ($brakingProcess.ExitCode -ne 0) { throw 'Truck braking review failed' }
} finally { Remove-Item Env:TRUCK_BRAKING_REVIEW_ROOT -ErrorAction SilentlyContinue }
