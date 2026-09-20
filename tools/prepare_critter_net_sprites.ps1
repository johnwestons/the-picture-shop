param(
    [Parameter(Mandatory = $true)]
    [string]$Path
)

$sourcePath = (Resolve-Path -LiteralPath $Path).Path
$temporaryPath = "$sourcePath.alpha.png"

Add-Type -AssemblyName System.Drawing
$runtimeDirectory = Split-Path ([System.Drawing.Bitmap].Assembly.Location)
$drawingAssemblies = @(
    (Join-Path $runtimeDirectory 'System.Drawing.Common.dll'),
    (Join-Path $runtimeDirectory 'System.Drawing.Primitives.dll'),
    (Join-Path $runtimeDirectory 'System.Private.Windows.Core.dll'),
    (Join-Path $runtimeDirectory 'System.Private.Windows.GdiPlus.dll')
)
Add-Type -ReferencedAssemblies $drawingAssemblies -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public static class CritterNetTransparency
{
    private static bool IsConnectedBackdrop(byte b, byte g, byte r)
    {
        int maximum = Math.Max(r, Math.Max(g, b));
        int minimum = Math.Min(r, Math.Min(g, b));
        return minimum >= 225 && maximum - minimum <= 18;
    }

    public static void Convert(string inputPath, string outputPath)
    {
        using (var source = new Bitmap(inputPath))
        using (var image = new Bitmap(source.Width, source.Height, PixelFormat.Format32bppArgb))
        {
            using (var graphics = Graphics.FromImage(image))
            {
                graphics.DrawImageUnscaled(source, 0, 0);
            }

            var rectangle = new Rectangle(0, 0, image.Width, image.Height);
            var bits = image.LockBits(rectangle, ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
            int stride = Math.Abs(bits.Stride);
            byte[] pixels = new byte[stride * image.Height];
            Marshal.Copy(bits.Scan0, pixels, 0, pixels.Length);

            bool[] visited = new bool[image.Width * image.Height];
            int[] queue = new int[image.Width * image.Height];
            int queueHead = 0;
            int queueTail = 0;
            Action<int, int> seed = (x, y) =>
            {
                int index = y * image.Width + x;
                int offset = y * stride + x * 4;
                if (!visited[index] && IsConnectedBackdrop(
                    pixels[offset], pixels[offset + 1], pixels[offset + 2]))
                {
                    visited[index] = true;
                    queue[queueTail++] = index;
                }
            };

            for (int x = 0; x < image.Width; x++)
            {
                seed(x, 0);
                seed(x, image.Height - 1);
            }
            for (int y = 0; y < image.Height; y++)
            {
                seed(0, y);
                seed(image.Width - 1, y);
            }

            while (queueHead < queueTail)
            {
                int index = queue[queueHead++];
                int x = index % image.Width;
                int y = index / image.Width;
                int offset = y * stride + x * 4;
                pixels[offset] = pixels[offset + 1] = pixels[offset + 2] = 0;
                pixels[offset + 3] = 0;

                if (x > 0) seed(x - 1, y);
                if (x + 1 < image.Width) seed(x + 1, y);
                if (y > 0) seed(x, y - 1);
                if (y + 1 < image.Height) seed(x, y + 1);
            }

            Marshal.Copy(pixels, 0, bits.Scan0, pixels.Length);
            image.UnlockBits(bits);
            image.Save(outputPath, ImageFormat.Png);
        }
    }
}
'@

[CritterNetTransparency]::Convert($sourcePath, $temporaryPath)
Move-Item -LiteralPath $temporaryPath -Destination $sourcePath -Force
