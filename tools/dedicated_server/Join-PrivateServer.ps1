param(
    [Parameter(Mandatory = $true)]
    [string]$InviteFile,
    [string]$LovePath = (Join-Path $env:ProgramFiles 'LOVE\love.exe'),
    [string]$PlayerName = 'Private Server Worker',
    [string]$ClientIdentity = 'the-picture-shop-server-client-private',
    [ValidateRange(0, 3600)]
    [int]$RunForSeconds = 0
)

$ErrorActionPreference = 'Stop'
$workspace = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$invitePath = [IO.Path]::GetFullPath($InviteFile)
if (-not (Test-Path -LiteralPath $LovePath -PathType Leaf)) {
    throw "LÖVE runtime not found: $LovePath"
}
if (-not (Test-Path -LiteralPath $invitePath -PathType Leaf)) {
    throw "Private invite file not found: $invitePath"
}
if ($ClientIdentity -notmatch '^the-picture-shop-server-client-[a-z0-9-]+$') {
    throw 'ClientIdentity must use the-picture-shop-server-client- prefix.'
}
$invite = (Get-Content -LiteralPath $invitePath -Raw).Trim()
if ($invite -notmatch '^TPS1\|[^|]+\|[0-9a-f]{64}$') {
    throw 'Invite file is malformed. Keep it private and copy the invite exactly.'
}

$environmentNames = @(
    'PICTURE_SHOP_PRIVATE_SERVER_JOIN', 'PICTURE_SHOP_SERVER_INVITE',
    'PICTURE_SHOP_SERVER_PLAYER_NAME', 'PICTURE_SHOP_PRIVATE_SERVER_CLIENT_IDENTITY',
    'PICTURE_SHOP_SERVER_CLIENT_RUN_SECONDS'
)
$previous = @{}
foreach ($name in $environmentNames) { $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
try {
    $env:PICTURE_SHOP_PRIVATE_SERVER_JOIN = '1'
    $env:PICTURE_SHOP_SERVER_INVITE = $invite
    $env:PICTURE_SHOP_SERVER_PLAYER_NAME = $PlayerName
    $env:PICTURE_SHOP_PRIVATE_SERVER_CLIENT_IDENTITY = $ClientIdentity
    $env:PICTURE_SHOP_SERVER_CLIENT_RUN_SECONDS = [string]$RunForSeconds
    & $LovePath $workspace
    $clientExitCode = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
} finally {
    foreach ($name in $environmentNames) {
        if ($null -eq $previous[$name]) {
            Remove-Item -LiteralPath "Env:\$name" -ErrorAction SilentlyContinue
        } else {
            [Environment]::SetEnvironmentVariable($name, $previous[$name], 'Process')
        }
    }
    Remove-Variable invite -ErrorAction SilentlyContinue
}
exit $clientExitCode
