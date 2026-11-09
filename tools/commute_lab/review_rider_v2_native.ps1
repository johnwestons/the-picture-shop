$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$love = 'C:\Program Files\LOVE\lovec.exe'
$viewer = Join-Path $PSScriptRoot 'rider_v2_review'
$out = Join-Path $repo 'output\commute-rider-v2-review'
if (-not (Test-Path -LiteralPath $love)) { throw "LÖVE console runner not found: $love" }

$env:PICTURE_SHOP_RIDER_V2_VIEW = 'walk'
$env:PICTURE_SHOP_RIDER_V2_CAPTURE = Join-Path $out 'native-walk.png'
& $love $viewer
if ($LASTEXITCODE -ne 0) { throw "Native walk review exited with $LASTEXITCODE" }

$env:PICTURE_SHOP_RIDER_V2_VIEW = 'idle'
$env:PICTURE_SHOP_RIDER_V2_CAPTURE = Join-Path $out 'native-idle.png'
& $love $viewer
if ($LASTEXITCODE -ne 0) { throw "Native idle review exited with $LASTEXITCODE" }
