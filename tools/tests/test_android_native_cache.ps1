$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\android_native_cache.ps1')
$project = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$fixture = Join-Path $project ('tmp\android-cache-test-' + [Guid]::NewGuid().ToString('N'))
$cache = Join-Path $fixture 'love\build\.cxx'
$metadata = Join-Path $cache 'Debug\arm64-v8a\android_gradle_build.json'
$keep = Join-Path $fixture 'love\build\intermediates\keep.txt'
New-Item -ItemType Directory -Path (Split-Path $metadata), (Split-Path $keep) -Force | Out-Null
Set-Content -LiteralPath $keep -Value 'compiled objects must survive'
$current = 'M:\love-android'
@{ buildFiles = @('M:\love-android\love\src\jni\Android.mk') } |
    ConvertTo-Json | Set-Content -LiteralPath $metadata
Reset-StaleAndroidNativeCache -WrapperRoot $fixture -BuildRoot $current
if (-not (Test-Path -LiteralPath $metadata)) { throw 'Matching cache was removed.' }
@{ buildFiles = @('N:\love-android\love\src\jni\Android.mk') } |
    ConvertTo-Json | Set-Content -LiteralPath $metadata
Reset-StaleAndroidNativeCache -WrapperRoot $fixture -BuildRoot $current
if (Test-Path -LiteralPath $cache) { throw 'Old drive cache survived.' }
if (-not (Test-Path -LiteralPath $keep)) { throw 'Compiled objects were removed.' }
Reset-StaleAndroidNativeCache -WrapperRoot $fixture -BuildRoot $current
New-Item -ItemType Directory -Path (Split-Path $metadata) -Force | Out-Null
Set-Content -LiteralPath $metadata -Value '{invalid'
Reset-StaleAndroidNativeCache -WrapperRoot $fixture -BuildRoot $current
if (Test-Path -LiteralPath $cache) { throw 'Corrupt cache survived.' }
$resolved = (Resolve-Path -LiteralPath $fixture).Path
if (-not $resolved.StartsWith($project + '\tmp\android-cache-test-', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Fixture cleanup escaped its test directory.'
}
Remove-Item -LiteralPath $resolved -Recurse -Force
Write-Output 'PASS: matching cache retained, old drive/corrupt cache removed, missing cache accepted, compiled objects retained.'
