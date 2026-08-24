$ErrorActionPreference = 'Stop'
$workspacePath = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$reportPath = Join-Path $PSScriptRoot 'sprite-motion-report.rpt'
$candidates = @(
    (Join-Path $workspacePath 'runtime\love.exe'),
    (Join-Path $env:ProgramFiles 'LOVE\love.exe')
)
if (${env:ProgramFiles(x86)}) {
    $candidates += (Join-Path ${env:ProgramFiles(x86)} 'LOVE\love.exe')
}
$lovePath = $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
if (-not $lovePath) {
    $command = Get-Command love.exe -ErrorAction SilentlyContinue
    if ($command) { $lovePath = $command.Source }
}
if (-not $lovePath) { throw 'LÖVE 11.x was not found.' }

$previousSmoke = $env:PICTURE_SHOP_SMOKE
$previousLab = $env:PICTURE_SHOP_SPRITE_LAB
$previousReport = $env:PICTURE_SHOP_SMOKE_REPORT
try {
    $env:PICTURE_SHOP_SMOKE = '1'
    $env:PICTURE_SHOP_SPRITE_LAB = '1'
    $env:PICTURE_SHOP_SMOKE_REPORT = $reportPath
    Start-Process -FilePath $lovePath -ArgumentList ('"' + $workspacePath + '"') `
        -WorkingDirectory $workspacePath -WindowStyle Normal
}
finally {
    if ($null -eq $previousSmoke) { Remove-Item Env:PICTURE_SHOP_SMOKE -ErrorAction SilentlyContinue } else { $env:PICTURE_SHOP_SMOKE = $previousSmoke }
    if ($null -eq $previousLab) { Remove-Item Env:PICTURE_SHOP_SPRITE_LAB -ErrorAction SilentlyContinue } else { $env:PICTURE_SHOP_SPRITE_LAB = $previousLab }
    if ($null -eq $previousReport) { Remove-Item Env:PICTURE_SHOP_SMOKE_REPORT -ErrorAction SilentlyContinue } else { $env:PICTURE_SHOP_SMOKE_REPORT = $previousReport }
}
