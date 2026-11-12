$ErrorActionPreference='Stop'
$labRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$labLove=(Get-Command love.exe -ErrorAction SilentlyContinue).Source
if (-not $labLove) { $labLove=Join-Path $env:ProgramFiles 'LOVE/love.exe' }
if (-not (Test-Path -LiteralPath $labLove)) { $labLove=Join-Path ${env:ProgramFiles(x86)} 'LOVE/love.exe' }
if (-not (Test-Path -LiteralPath $labLove)) { throw 'LOVE 11.x was not found.' }
New-Item -ItemType Directory -Force -Path (Join-Path $labRoot 'assets/source/cutscene-studio') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $labRoot 'assets/generated/cutscenes') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $labRoot 'output/cutscene-studio/recordings') | Out-Null
$env:PICTURE_SHOP_CUTSCENE_STUDIO='1'
Start-Process -FilePath $labLove -ArgumentList '"."' -WorkingDirectory $labRoot
