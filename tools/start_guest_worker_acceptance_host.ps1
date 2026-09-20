[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $FixturePath,
    [ValidateRange(1, 3)]
    [int] $Slot = 1,
    [string] $LoveRoot = 'C:\Program Files\LOVE'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$fixtureRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot 'tmp\physical-acceptance'))
$fixture = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $FixturePath).Path)
$fixturePrefix = $fixtureRoot.TrimEnd('\') + '\'
if (-not $fixture.StartsWith($fixturePrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The acceptance fixture must be inside tmp\physical-acceptance.'
}
$fixtureItem = Get-Item -LiteralPath $fixture -Force
if ($fixtureItem.PSIsContainer -or
        ($fixtureItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
        $fixtureItem.Extension -cne '.lua') {
    throw 'The acceptance fixture must be a regular .lua save file.'
}

$loveConsole = [IO.Path]::GetFullPath((Join-Path $LoveRoot 'lovec.exe'))
if (-not (Test-Path -LiteralPath $loveConsole -PathType Leaf)) {
    throw "The LÖVE console runtime was not found at $loveConsole"
}

$stamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmssfff')
$identity = "the-picture-shop-acceptance-$stamp"
$loveSaveRoot = [IO.Path]::GetFullPath((Join-Path $env:APPDATA 'LOVE'))
$identityRoot = [IO.Path]::GetFullPath((Join-Path $loveSaveRoot $identity))
$saveRoot = [IO.Path]::GetFullPath((Join-Path $identityRoot 'saves'))
$loveSavePrefix = $loveSaveRoot.TrimEnd('\') + '\'
if (-not $identityRoot.StartsWith($loveSavePrefix,
        [StringComparison]::OrdinalIgnoreCase) -or
        (Test-Path -LiteralPath $identityRoot)) {
    throw 'Could not reserve a new isolated acceptance save identity.'
}

$runRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot `
    "output\mobile\device-tests\acceptance-host\$identity"))
New-Item -ItemType Directory -Path $saveRoot -Force | Out-Null
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
$savePath = Join-Path $saveRoot "slot$Slot.lua"
Copy-Item -LiteralPath $fixture -Destination $savePath

$stdoutPath = Join-Path $runRoot 'host.stdout.log'
$stderrPath = Join-Path $runRoot 'host.stderr.log'
$previousSlot = $env:PICTURE_SHOP_ACCEPTANCE_HOST_SLOT
$previousIdentity = $env:PICTURE_SHOP_ACCEPTANCE_IDENTITY
$process = $null
try {
    $env:PICTURE_SHOP_ACCEPTANCE_HOST_SLOT = [string]$Slot
    $env:PICTURE_SHOP_ACCEPTANCE_IDENTITY = $identity
    $process = Start-Process -FilePath $loveConsole `
        -ArgumentList @('"' + $projectRoot + '"') `
        -WorkingDirectory $projectRoot `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath `
        -WindowStyle Hidden `
        -PassThru
}
finally {
    if ($null -eq $previousSlot) {
        Remove-Item Env:PICTURE_SHOP_ACCEPTANCE_HOST_SLOT -ErrorAction SilentlyContinue
    } else {
        $env:PICTURE_SHOP_ACCEPTANCE_HOST_SLOT = $previousSlot
    }
    if ($null -eq $previousIdentity) {
        Remove-Item Env:PICTURE_SHOP_ACCEPTANCE_IDENTITY -ErrorAction SilentlyContinue
    } else {
        $env:PICTURE_SHOP_ACCEPTANCE_IDENTITY = $previousIdentity
    }
}

$readyLine = $null
$deadline = [DateTime]::UtcNow.AddSeconds(30)
while ([DateTime]::UtcNow -lt $deadline) {
    if ($process.HasExited) { break }
    if (Test-Path -LiteralPath $stdoutPath) {
        $readyLine = Get-Content -LiteralPath $stdoutPath |
            Where-Object { $_ -like '[[]ACCEPTANCE HOST[]] READY*' } |
            Select-Object -Last 1
        if ($readyLine) { break }
    }
    Start-Sleep -Milliseconds 250
    $process.Refresh()
}

if (-not $readyLine) {
    if (-not $process.HasExited -and $process.Path -ceq $loveConsole) {
        Stop-Process -Id $process.Id
    }
    $errorText = if (Test-Path -LiteralPath $stderrPath) {
        (Get-Content -Raw -LiteralPath $stderrPath).Trim()
    } else { '' }
    throw "The isolated acceptance host did not report ready. $errorText"
}

$addresses = @([Net.Dns]::GetHostAddresses([Net.Dns]::GetHostName()) |
    Where-Object {
        $_.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork -and
        -not [Net.IPAddress]::IsLoopback($_)
    } | ForEach-Object { $_.IPAddressToString } | Select-Object -Unique)
$manifest = [ordered]@{
    schemaVersion = 1
    createdAtUtc = [DateTime]::UtcNow.ToString('o')
    processId = $process.Id
    executable = $loveConsole
    identity = $identity
    slot = $Slot
    fixture = $fixture
    fixtureSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $fixture).Hash.ToLowerInvariant()
    isolatedSave = $savePath
    addresses = $addresses
    port = 22122
    stdout = $stdoutPath
    stderr = $stderrPath
}
$manifestPath = Join-Path $runRoot 'manifest.json'
[IO.File]::WriteAllText(
    $manifestPath,
    (($manifest | ConvertTo-Json -Depth 5) + [Environment]::NewLine),
    [Text.UTF8Encoding]::new($false))

Write-Output 'GUEST_WORKER_ACCEPTANCE_HOST=READY'
Write-Output "PROCESS_ID=$($process.Id)"
Write-Output "IDENTITY=$identity"
Write-Output "ADDRESS=$($addresses -join ',')"
Write-Output 'PORT=22122'
Write-Output "MANIFEST=$manifestPath"
