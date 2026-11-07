param([string]$InputPath,[string]$OutputPath,[int]$FrameSize=512,[int]$Baseline=491,[int]$MaxSpriteExtent=460)

Add-Type -AssemblyName System.Drawing
$sourcePath=(Resolve-Path -LiteralPath $InputPath).Path
$drawingAssembly=[Drawing.Bitmap].Assembly.Location
$drawingDirectory=Split-Path -Parent $drawingAssembly
$drawingReferences=@(
    $drawingAssembly,
    (Join-Path $drawingDirectory 'System.Drawing.Primitives.dll'),
    (Join-Path $drawingDirectory 'System.Private.Windows.Core.dll'),
    (Join-Path $drawingDirectory 'System.Private.Windows.GdiPlus.dll')
)
$definition=@'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;

public static class Sprite64AtlasPacker {
    private sealed class Cell {
        public int Width, Height, MinX, MinY, MaxX, MaxY;
        public Color[] Pixels;
        public bool[] Keep;
    }

    public static void Run(string input, string output, int frameSize, int baseline, int maxSpriteExtent) {
        using (Bitmap source = new Bitmap(input))
        using (Bitmap atlas = new Bitmap(frameSize * 8, frameSize * 8, PixelFormat.Format32bppArgb)) {
            Cell[] cells = new Cell[64];
            int largestWidth = 0, largestHeight = 0;
            for (int frame = 0; frame < 64; frame++) {
                int column = frame % 8, row = frame / 8;
                int x0 = (int)Math.Floor(column * source.Width / 8.0);
                int x1 = (int)Math.Floor((column + 1) * source.Width / 8.0);
                int y0 = (int)Math.Floor(row * source.Height / 8.0);
                int y1 = (int)Math.Floor((row + 1) * source.Height / 8.0);
                Cell cell = new Cell();
                cell.Width = x1 - x0; cell.Height = y1 - y0;
                int count = cell.Width * cell.Height;
                cell.Pixels = new Color[count]; cell.Keep = new bool[count];
                int[] labels = new int[count]; int[] componentSizes = new int[count + 1];
                int[] queue = new int[count]; int componentCount = 0, largestComponent = 0;
                for (int y = 0; y < cell.Height; y++)
                    for (int x = 0; x < cell.Width; x++)
                        cell.Pixels[y * cell.Width + x] = source.GetPixel(x0 + x, y0 + y);

                for (int i = 0; i < count; i++) {
                    if (labels[i] != 0 || cell.Pixels[i].A < 28) continue;
                    int id = ++componentCount;
                    int head = 0, tail = 0; queue[tail++] = i; labels[i] = id;
                    while (head < tail) {
                        int p = queue[head++];
                        int px = p % cell.Width, py = p / cell.Width;
                        for (int oy = -1; oy <= 1; oy++) for (int ox = -1; ox <= 1; ox++) {
                            if (ox == 0 && oy == 0) continue;
                            int nx = px + ox, ny = py + oy;
                            if (nx < 0 || nx >= cell.Width || ny < 0 || ny >= cell.Height) continue;
                            int next = ny * cell.Width + nx;
                            if (labels[next] == 0 && cell.Pixels[next].A >= 28) {
                                labels[next] = id; queue[tail++] = next;
                            }
                        }
                    }
                    componentSizes[id] = tail;
                    largestComponent = Math.Max(largestComponent, tail);
                }

                // Keep the machine and any meaningful attached detail while dropping
                // small isolated image-generation specks in each transparent cell.
                int minimumComponent = Math.Max(8, largestComponent / 1200);
                for (int i = 0; i < count; i++) {
                    int id = labels[i];
                    if (id != 0 && componentSizes[id] >= minimumComponent) cell.Keep[i] = true;
                }

                cell.MinX = cell.Width; cell.MinY = cell.Height; cell.MaxX = -1; cell.MaxY = -1;
                for (int y = 0; y < cell.Height; y++) for (int x = 0; x < cell.Width; x++) {
                    if (!cell.Keep[y * cell.Width + x]) continue;
                    cell.MinX = Math.Min(cell.MinX, x); cell.MaxX = Math.Max(cell.MaxX, x);
                    cell.MinY = Math.Min(cell.MinY, y); cell.MaxY = Math.Max(cell.MaxY, y);
                }
                if (cell.MaxX < cell.MinX || cell.MaxY < cell.MinY)
                    throw new InvalidOperationException("Sprite frame " + (frame + 1) + " has no visible sprite.");
                largestWidth = Math.Max(largestWidth, cell.MaxX - cell.MinX + 1);
                largestHeight = Math.Max(largestHeight, cell.MaxY - cell.MinY + 1);
                cells[frame] = cell;
            }

            int cellSize = frameSize;
            double scale = Math.Min(maxSpriteExtent / (double)largestWidth,
                                    maxSpriteExtent / (double)largestHeight);
            using (Graphics g = Graphics.FromImage(atlas)) {
                g.Clear(Color.Transparent);
                g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                g.SmoothingMode = SmoothingMode.HighQuality;
                g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                g.CompositingMode = CompositingMode.SourceCopy;
                for (int frame = 0; frame < 64; frame++) {
                    Cell cell = cells[frame];
                    using (Bitmap clean = new Bitmap(cell.Width, cell.Height, PixelFormat.Format32bppArgb)) {
                        for (int y = 0; y < cell.Height; y++) for (int x = 0; x < cell.Width; x++) {
                            int i = y * cell.Width + x;
                            clean.SetPixel(x, y, cell.Keep[i] ? cell.Pixels[i] : Color.Transparent);
                        }
                        int cropWidth = cell.MaxX - cell.MinX + 1;
                        int cropHeight = cell.MaxY - cell.MinY + 1;
                        int drawWidth = (int)Math.Round(cropWidth * scale);
                        int drawHeight = (int)Math.Round(cropHeight * scale);
                        int column = frame % 8, row = frame / 8;
                        int destX = column * cellSize + (cellSize - drawWidth) / 2;
                        int destY = row * cellSize + baseline - drawHeight;
                        g.DrawImage(clean, new Rectangle(destX, destY, drawWidth, drawHeight),
                            new Rectangle(cell.MinX, cell.MinY, cropWidth, cropHeight), GraphicsUnit.Pixel);
                    }
                }
            }
            atlas.Save(output, ImageFormat.Png);
        }
    }
}
'@

Add-Type -TypeDefinition $definition -ReferencedAssemblies $drawingReferences
$fullOutput=[IO.Path]::GetFullPath((Join-Path (Get-Location) $OutputPath))
[Sprite64AtlasPacker]::Run($sourcePath,$fullOutput,$FrameSize,$Baseline,$MaxSpriteExtent)
