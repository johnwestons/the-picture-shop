param([switch]$Smoke)
$ErrorActionPreference='Stop'
$shadowRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$shadowStage=Join-Path $shadowRoot 'output/shadow-lab'
$shadowSaveBase=[IO.Path]::GetFullPath((Join-Path $env:APPDATA 'LOVE'))
$shadowSave=[IO.Path]::GetFullPath((Join-Path $shadowSaveBase 'the-picture-shop-shadow-lab'))
if ((Split-Path $shadowSave -Parent) -ne $shadowSaveBase -or (Split-Path $shadowSave -Leaf) -ne 'the-picture-shop-shadow-lab') { throw 'Unexpected shadow lab save path' }
if (Test-Path -LiteralPath $shadowSave) { Remove-Item -LiteralPath $shadowSave -Recurse -Force }
New-Item -ItemType Directory -Force -Path $shadowStage | Out-Null
Copy-Item -LiteralPath (Join-Path $shadowRoot 'src') -Destination $shadowStage -Recurse -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'main.lua'),(Join-Path $PSScriptRoot 'conf.lua') -Destination $shadowStage -Force
Copy-Item -LiteralPath (Join-Path $shadowRoot 'assets/generated/warehouse-lobby-seating-v5-three-tier.png') -Destination (Join-Path $shadowStage 'warehouse.png') -Force
$shadowOutput=Join-Path $shadowRoot 'output/shadow-checks'
New-Item -ItemType Directory -Force -Path $shadowOutput | Out-Null
[IO.File]::WriteAllText((Join-Path $shadowStage 'lab_paths.lua'),('return {output=[['+$shadowOutput.Replace('\','/')+']]}'),(New-Object Text.UTF8Encoding($false)))
$shadowLove=Join-Path $env:ProgramFiles 'LOVE/love.exe'
if ($Smoke) { $env:PICTURE_SHOP_SHADOW_SMOKE='1' } else { Remove-Item Env:PICTURE_SHOP_SHADOW_SMOKE -ErrorAction SilentlyContinue }
try {
    $shadowProcess=Start-Process -FilePath $shadowLove -ArgumentList ('"'+$shadowStage+'"') -PassThru -WindowStyle Hidden
    if ($Smoke) {
        if (-not $shadowProcess.WaitForExit(30000)) { $shadowProcess.Kill();throw 'Shadow smoke timed out' }
        Get-Content -LiteralPath (Join-Path $shadowOutput 'smoke-report.txt')
        if ($shadowProcess.ExitCode -ne 0 -or -not (Select-String -LiteralPath (Join-Path $shadowOutput 'smoke-report.txt') -Pattern 'SHADOW_SMOKE_OK' -Quiet)) { throw 'Shadow smoke failed' }
    }
} finally { Remove-Item Env:PICTURE_SHOP_SHADOW_SMOKE -ErrorAction SilentlyContinue }
