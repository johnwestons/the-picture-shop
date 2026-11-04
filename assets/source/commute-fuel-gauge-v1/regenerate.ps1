# Bake the same generated instrument into the two registered cockpit sprites.
# The coordinates are the optical center of the face, not the mounting foot.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$cockpit = Join-Path $PSScriptRoot '../../commute/cockpit'
$housing = [System.Drawing.Bitmap]::new((Join-Path $PSScriptRoot 'housing.png'))
try {
    $views = @(
        @{base='handlebars-controls-v1'; output='handlebars-fuel-v2'; x=267; y=87; diameter=54; layoutWidth=720},
        @{base='first-person-bike-controls-v1'; output='first-person-bike-fuel-v2'; x=410; y=228; diameter=64; layoutWidth=1024}
    )
    foreach ($view in $views) {
        $sprite = [System.Drawing.Bitmap]::new((Join-Path $cockpit ($view.base + '.png')))
        try {
            $pixels = $sprite.Width / $view.layoutWidth
            $scale = $pixels * $view.diameter / 940
            $rect = [System.Drawing.RectangleF]::new(
                $view.x * $pixels - 616 * $scale, $view.y * $pixels - 542 * $scale,
                $housing.Width * $scale, $housing.Height * $scale)
            $g = [System.Drawing.Graphics]::FromImage($sprite)
            try {
                $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                $g.DrawImage($housing, $rect)
            } finally { $g.Dispose() }
            $sprite.Save((Join-Path $cockpit ($view.output + '.png')), [System.Drawing.Imaging.ImageFormat]::Png)
        } finally { $sprite.Dispose() }
    }
} finally { $housing.Dispose() }
