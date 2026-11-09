param(
    [string]$LovePath = (Join-Path $env:ProgramFiles 'LOVE\lovec.exe'),
    [string]$BindAddress = '127.0.0.1',
    [string]$PublicHost = '127.0.0.1',
    [int]$Port = 22122,
    [string]$SaveIdentity = 'the-picture-shop-server-private',
    [int]$Slot = 1,
    [ValidateRange(0, 3600)]
    [int]$RunForSeconds = 0
)

$ErrorActionPreference = 'Stop'
$workspace = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
if (-not (Test-Path -LiteralPath $LovePath -PathType Leaf)) {
    throw "LÖVE console runtime not found: $LovePath"
}
if ($Port -lt 1 -or $Port -gt 65535) { throw 'Port must be between 1 and 65535.' }
if ($Slot -lt 1 -or $Slot -gt 3) { throw 'Slot must be 1, 2, or 3.' }
if ($SaveIdentity -notmatch '^the-picture-shop-server-[a-z0-9-]+$') {
    throw 'SaveIdentity must use the-picture-shop-server- prefix.'
}

$environmentNames = @(
    'PICTURE_SHOP_PRIVATE_SERVER', 'PICTURE_SHOP_SERVER_BIND',
    'PICTURE_SHOP_SERVER_PUBLIC_HOST', 'PICTURE_SHOP_SERVER_PORT',
    'PICTURE_SHOP_SERVER_IDENTITY', 'PICTURE_SHOP_SERVER_SLOT',
    'PICTURE_SHOP_SERVER_RUN_SECONDS'
)
$previous = @{}
foreach ($name in $environmentNames) { $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
try {
    $env:PICTURE_SHOP_PRIVATE_SERVER = '1'
    $env:PICTURE_SHOP_SERVER_BIND = $BindAddress
    $env:PICTURE_SHOP_SERVER_PUBLIC_HOST = $PublicHost
    $env:PICTURE_SHOP_SERVER_PORT = [string]$Port
    $env:PICTURE_SHOP_SERVER_IDENTITY = $SaveIdentity
    $env:PICTURE_SHOP_SERVER_SLOT = [string]$Slot
    $env:PICTURE_SHOP_SERVER_RUN_SECONDS = [string]$RunForSeconds
    & $LovePath $workspace
    $serverExitCode = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
} finally {
    foreach ($name in $environmentNames) {
        if ($null -eq $previous[$name]) {
            Remove-Item -LiteralPath "Env:\$name" -ErrorAction SilentlyContinue
        } else {
            [Environment]::SetEnvironmentVariable($name, $previous[$name], 'Process')
        }
    }
}
exit $serverExitCode
