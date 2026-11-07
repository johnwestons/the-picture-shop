param([string]$InputPath,[string]$OutputPath)
Add-Type -AssemblyName System.Drawing
$sourcePath=(Resolve-Path -LiteralPath $InputPath).Path
$drawingAssembly=[Drawing.Bitmap].Assembly.Location
$primitiveAssembly=[Drawing.Color].Assembly.Location
$gdiAssembly=[System.Reflection.Assembly]::Load('System.Private.Windows.GdiPlus').Location
$windowsCoreAssembly=[System.Reflection.Assembly]::Load('System.Private.Windows.Core').Location
$definition=@'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
public static class SpriteSheetCleaner {
 public static void Run(string input,string output) {
  using(Bitmap src=new Bitmap(input)) using(Bitmap dst=new Bitmap(2048,2048,PixelFormat.Format32bppArgb)) {
   double cw=src.Width/8.0,ch=src.Height/8.0;
   using(Graphics g=Graphics.FromImage(dst)) {
    g.Clear(Color.Transparent);g.InterpolationMode=InterpolationMode.HighQualityBicubic;
    g.SmoothingMode=SmoothingMode.HighQuality;g.PixelOffsetMode=PixelOffsetMode.HighQuality;
    for(int row=0;row<8;row++) for(int col=0;col<8;col++) {
     int x0=(int)Math.Floor(col*cw),x1=(int)Math.Floor((col+1)*cw);
     int y0=(int)Math.Floor(row*ch),y1=(int)Math.Floor((row+1)*ch);
     int w=x1-x0,h=y1-y0,n=w*h;Color[] pix=new Color[n];bool[] bg=new bool[n],seen=new bool[n];
     for(int y=0;y<h;y++)for(int x=0;x<w;x++){
      int i=y*w+x;Color c=src.GetPixel(x0+x,y0+y);pix[i]=c;
      int hi=Math.Max(c.R,Math.Max(c.G,c.B)),lo=Math.Min(c.R,Math.Min(c.G,c.B));
      float hue=c.GetHue();int sat=hi-lo;
      bg[i]=c.A<12 || (c.A<248 && sat>48 && (hue<14 || (hue>48 && hue<76) || hue>330));
     }
     int[] q=new int[n];int head=0,tail=0;
     Action<int> add=i=>{if(i>=0&&i<n&&bg[i]&&!seen[i]){seen[i]=true;q[tail++]=i;}};
     for(int x=0;x<w;x++){add(x);add((h-1)*w+x);}
     for(int y=0;y<h;y++){add(y*w);add(y*w+w-1);}
     while(head<tail){int i=q[head++],x=i%w,y=i/w;if(x>0)add(i-1);if(x+1<w)add(i+1);if(y>0)add(i-w);if(y+1<h)add(i+w);}
     int minx=w,miny=h,maxx=-1,maxy=-1;
     using(Bitmap frame=new Bitmap(w,h,PixelFormat.Format32bppArgb)){
      for(int y=0;y<h;y++)for(int x=0;x<w;x++){
       int i=y*w+x;Color c=pix[i];
       if(seen[i])c=Color.FromArgb(0,c.R,c.G,c.B);else{minx=Math.Min(minx,x);maxx=Math.Max(maxx,x);miny=Math.Min(miny,y);maxy=Math.Max(maxy,y);}
       frame.SetPixel(x,y,c);
      }
      if(maxx>=minx){int sw=maxx-minx+1,sh=maxy-miny+1;double scale=Math.Min(1.48,Math.Min(216.0/sw,216.0/sh));
       int dw=(int)Math.Round(sw*scale),dh=(int)Math.Round(sh*scale),dx=col*256+(int)Math.Round(128-dw/2.0),dy=row*256+238-dh;
       g.DrawImage(frame,new Rectangle(dx,dy,dw,dh),new Rectangle(minx,miny,sw,sh),GraphicsUnit.Pixel);
      }
     }
    }
   }
   dst.Save(output,ImageFormat.Png);
  }
 }
}
'@
Add-Type -TypeDefinition $definition -ReferencedAssemblies @($drawingAssembly,$primitiveAssembly,$gdiAssembly,$windowsCoreAssembly)
[SpriteSheetCleaner]::Run($sourcePath,(Join-Path (Get-Location) $OutputPath))
