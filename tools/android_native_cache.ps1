function Reset-StaleAndroidNativeCache {
    param(
        [Parameter(Mandatory=$true)][string]$WrapperRoot,
        [Parameter(Mandatory=$true)][string]$BuildRoot
    )
    # Gradle records absolute SUBST paths here. A later build may receive a
    # different drive letter even though the wrapper has not moved.
    $wrapper = [IO.Path]::GetFullPath($WrapperRoot).TrimEnd('\')
    $cache = [IO.Path]::GetFullPath((Join-Path $wrapper 'love\build\.cxx'))
    if (-not (Test-Path -LiteralPath $cache)) { return }
    $expected = [IO.Path]::GetFullPath([IO.Path]::Combine($BuildRoot, 'love\src\jni\Android.mk'))
    $stale = $false
    foreach ($metadata in Get-ChildItem -LiteralPath $cache -Recurse -Filter 'android_gradle_build.json') {
        try {
            $record = Get-Content -LiteralPath $metadata.FullName -Raw | ConvertFrom-Json
            if (@($record.buildFiles) -notcontains $expected) { $stale = $true; break }
        }
        catch { $stale = $true; break }
    }
    if (-not $stale) { return }
    if (-not $cache.StartsWith($wrapper + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Native cache path escapes the Android wrapper.'
    }
    # Never traverse a junction while removing the generated cache.
    $ancestor = $cache
    while ($ancestor.Length -ge $wrapper.Length) {
        if (((Get-Item -LiteralPath $ancestor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Refusing to clear a redirected native cache: $ancestor"
        }
        $ancestor = Split-Path $ancestor -Parent
    }
    if (Get-ChildItem -LiteralPath $cache -Recurse -Force |
            Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 }) {
        throw 'Refusing to clear a native cache containing a redirected path.'
    }
    Write-Output 'Clearing Android native configuration cached for another build path...'
    Remove-Item -LiteralPath $cache -Recurse -Force
}
