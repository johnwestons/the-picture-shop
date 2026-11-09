$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$love = 'C:\Program Files\LOVE\lovec.exe'
$viewer = Join-Path $PSScriptRoot 'rider_v2_east_candidate_review'
$out = Join-Path $repo 'output\commute-rider-v2-review\east-candidates'
if (-not (Test-Path -LiteralPath $love)) { throw "LÖVE console runner not found: $love" }

$env:PICTURE_SHOP_EAST_CANDIDATE_VIEW = 'strips'
$env:PICTURE_SHOP_EAST_CANDIDATE_CAPTURE = Join-Path $out 'native-full-strips.png'
& $love $viewer
if ($LASTEXITCODE -ne 0) { throw "Native east candidate review exited with $LASTEXITCODE" }

$env:PICTURE_SHOP_EAST_CANDIDATE_VIEW = 'contacts'
$env:PICTURE_SHOP_EAST_CANDIDATE_CAPTURE = Join-Path $out 'native-contact-pair.png'
& $love $viewer
if ($LASTEXITCODE -ne 0) { throw "Native east contact review exited with $LASTEXITCODE" }
