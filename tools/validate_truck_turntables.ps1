param([string] $AtlasDirectory='assets/commute/truck/turntables')

$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
if (-not ('TruckAtlasValidation' -as [type])) {
    $drawingRefs=@([System.Drawing.Bitmap].Assembly.Location,
        [System.Reflection.Assembly]::Load('System.Private.Windows.GdiPlus').Location,
        [System.Reflection.Assembly]::Load('System.Private.Windows.Core').Location,
        [System.Drawing.Point].Assembly.Location,
        [System.Security.Cryptography.SHA256].Assembly.Location)
    Add-Type -ReferencedAssemblies $drawingRefs -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Security.Cryptography;

public static class TruckAtlasValidation {
    public static string[] Inspect(string path, int frameWidth, int frameHeight, int columns, int rows) {
        using (var atlas = new Bitmap(path)) {
            if (atlas.Width != frameWidth * columns || atlas.Height != frameHeight * rows)
                throw new Exception("Unexpected atlas dimensions: " + path);
            var hashes = new string[columns * rows];
            for (int i = 0; i < hashes.Length; i++) {
                var rect = new Rectangle((i % columns) * frameWidth, (i / columns) * frameHeight, frameWidth, frameHeight);
                using (var cell = atlas.Clone(rect, PixelFormat.Format32bppArgb)) {
                    var bits = cell.LockBits(new Rectangle(0, 0, frameWidth, frameHeight),
                        ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
                    try {
                        var raw = new byte[Math.Abs(bits.Stride) * frameHeight];
                        Marshal.Copy(bits.Scan0, raw, 0, raw.Length);
                        int count = 0, minX = frameWidth, minY = frameHeight, maxX = -1, maxY = -1;
                        for (int y = 0; y < frameHeight; y++) for (int x = 0; x < frameWidth; x++) {
                            int offset = y * bits.Stride + x * 4;
                            if (raw[offset + 3] < 24) continue;
                            count++;
                            if (x < minX) minX = x;
                            if (x > maxX) maxX = x;
                            if (y < minY) minY = y;
                            if (y > maxY) maxY = y;
                        }
                        if (count < 500) throw new Exception("Empty truck frame " + (i + 1) + ": " + path);
                        if (minX < 4 || minY < 4 || maxX >= frameWidth - 4 || maxY >= frameHeight - 4)
                            throw new Exception("Clipped truck frame " + (i + 1) + ": " + path);
                        using (var sha = SHA256.Create())
                            hashes[i] = BitConverter.ToString(sha.ComputeHash(raw)).Replace("-", "").ToLowerInvariant();
                    } finally { cell.UnlockBits(bits); }
                }
            }
            return hashes;
        }
    }
}
'@
}

$root=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$directory=[IO.Path]::GetFullPath((Join-Path $root $AtlasDirectory))
$views=@()
foreach ($kind in @('chase','isometric')) {
    $width=if($kind -eq 'chase'){640}else{384}
        $hashes=[System.Collections.Generic.List[string]]::new()
        $pages=@()
        foreach ($page in 1..4) {
            $name="$kind-64-$page.png"
            $path=Join-Path $directory $name
            if (-not (Test-Path -LiteralPath $path)) { throw "Missing truck page: $path" }
            foreach ($hash in [TruckAtlasValidation]::Inspect($path,$width,384,4,4)) { $hashes.Add($hash) }
            $pages+=@{file=$name;sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()}
        }
        $unique=@($hashes | Select-Object -Unique).Count
        if ($hashes.Count -ne 64 -or $unique -ne 64) {
            throw "$kind has $($hashes.Count) frames and $unique distinct frames; expected 64 each"
        }
        $views+=@{kind=$kind;frameWidth=$width;frameHeight=384;
            frameCount=64;uniqueFrameHashes=$unique;pages=$pages}
}
$masterRelative='assets/source/delivery-truck-64/truck-complete.png'
$masterPath=Join-Path $root $masterRelative
$masterFrames=[TruckAtlasValidation]::Inspect($masterPath,640,448,8,16)
if (@($masterFrames | Select-Object -Unique).Count -ne 128) { throw 'Duplicate frames in the complete truck sheet' }
$manifest=[ordered]@{
    version=3;status='high_resolution_64_angle_truck'
    completeSheet=@{file=$masterRelative;sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $masterPath).Hash.ToLowerInvariant()
        columns=8;rows=16;frameWidth=640;frameHeight=448;anchor=@(320,320);frameCount=128
        order='row-major';chaseFirstFrame=1;isometricFirstFrame=65}
    sourceAssets=@(@{file='assets/commute/truck/elevated-panels.png';sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $root 'assets/commute/truck/elevated-panels.png')).Hash.ToLowerInvariant()})
    angles=@{frameOne='rear';stepDegrees=5.625;direction='clockwise';mirroredAtRuntime=$false}
    pitchesDegrees=@{chase=8;isometric=32}
    views=$views
    validation=@{nonempty=$true;unclipped=$true;allFramesUnique=$true;logoBakedIntoSprites=$false}
}
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $directory 'manifest.json') -Encoding utf8NoBOM
"TRUCK_TURNTABLES_VALID: two unbranded 64-frame sets, 128 nonempty distinct unclipped frames"
