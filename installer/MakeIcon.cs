using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;

namespace BatAppSetup
{
    public class MakeIcon
    {
        public static void Main(string[] args)
        {
            string outPath = (args.Length > 0) ? args[0] : @"installer\app.ico";
            int[] sizes = new int[] { 256, 128, 64, 48, 32, 16 };
            List<int> sizeList = new List<int>();
            List<byte[]> images = new List<byte[]>();
            foreach (int s in sizes)
            {
                Bitmap bmp = Render(s);
                images.Add(ToIcoImage(bmp));
                sizeList.Add(s);
                bmp.Dispose();
            }
            WriteIco(outPath, sizeList, images);
            Console.WriteLine("icon written: " + outPath);
        }

        private static Bitmap Render(int size)
        {
            Bitmap bmp = new Bitmap(size, size, PixelFormat.Format32bppArgb);
            Graphics g = Graphics.FromImage(bmp);
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.Clear(Color.Transparent);

            float pad = size * 0.05f;
            RectangleF rect = new RectangleF(pad, pad, size - pad * 2, size - pad * 2);

            using (GraphicsPath path = Round(rect, size * 0.20f))
            {
                using (LinearGradientBrush lg = new LinearGradientBrush(rect,
                    Color.FromArgb(34, 211, 238), Color.FromArgb(99, 102, 241), 45f))
                {
                    g.FillPath(lg, path);
                }
                using (Pen pen = new Pen(Color.FromArgb(190, 165, 243, 252), Math.Max(1f, size / 64f)))
                {
                    g.DrawPath(pen, path);
                }
            }

            RectangleF inner = new RectangleF(
                rect.X + size * 0.09f, rect.Y + size * 0.09f,
                rect.Width - size * 0.18f, rect.Height - size * 0.18f);
            using (GraphicsPath path = Round(inner, size * 0.14f))
            using (SolidBrush sb = new SolidBrush(Color.FromArgb(9, 17, 30)))
            {
                g.FillPath(sb, path);
            }

            if (size >= 32)
            {
                using (Pen cp = new Pen(Color.FromArgb(95, 34, 211, 238), Math.Max(1f, size / 96f)))
                {
                    g.DrawLine(cp, inner.X + size * 0.06f, inner.Y + inner.Height * 0.20f,
                        inner.Right - size * 0.06f, inner.Y + inner.Height * 0.20f);
                    g.DrawLine(cp, inner.X + size * 0.06f, inner.Bottom - inner.Height * 0.20f,
                        inner.Right - size * 0.06f, inner.Bottom - inner.Height * 0.20f);
                }
                float r = size * 0.022f;
                using (SolidBrush nb = new SolidBrush(Color.FromArgb(34, 211, 238)))
                {
                    g.FillEllipse(nb, inner.X + size * 0.05f, inner.Y + inner.Height * 0.20f - r, r * 2, r * 2);
                    g.FillEllipse(nb, inner.Right - size * 0.05f - r * 2,
                        inner.Bottom - inner.Height * 0.20f - r, r * 2, r * 2);
                }
            }

            using (Font f = new Font("Segoe UI", size * 0.44f, FontStyle.Bold, GraphicsUnit.Pixel))
            using (StringFormat sf = new StringFormat())
            {
                sf.Alignment = StringAlignment.Center;
                sf.LineAlignment = StringAlignment.Center;
                using (SolidBrush tb = new SolidBrush(Color.White))
                    g.DrawString("B", f, tb, inner, sf);
            }

            g.Dispose();
            return bmp;
        }

        private static GraphicsPath Round(RectangleF r, float radius)
        {
            GraphicsPath p = new GraphicsPath();
            float d = radius * 2;
            p.AddArc(r.X, r.Y, d, d, 180, 90);
            p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
            p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
            p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
            p.CloseFigure();
            return p;
        }

        private static byte[] ToIcoImage(Bitmap bmp)
        {
            int w = bmp.Width, h = bmp.Height;
            int andStride = ((w + 31) / 32) * 4;
            int xorSize = w * h * 4;
            int andSize = andStride * h;
            byte[] data = new byte[40 + xorSize + andSize];
            using (MemoryStream ms = new MemoryStream(data))
            using (BinaryWriter bw = new BinaryWriter(ms))
            {
                bw.Write(40);
                bw.Write(w);
                bw.Write(h * 2);
                bw.Write((ushort)1);
                bw.Write((ushort)32);
                bw.Write(0);
                bw.Write(xorSize + andSize);
                bw.Write(0);
                bw.Write(0);
                bw.Write(0);
                bw.Write(0);
                for (int y = h - 1; y >= 0; y--)
                {
                    for (int x = 0; x < w; x++)
                    {
                        Color c = bmp.GetPixel(x, y);
                        bw.Write(c.B);
                        bw.Write(c.G);
                        bw.Write(c.R);
                        bw.Write(c.A);
                    }
                }
                bw.Write(new byte[andSize]);
            }
            return data;
        }

        private static void WriteIco(string path, List<int> sizes, List<byte[]> images)
        {
            string dir = Path.GetDirectoryName(Path.GetFullPath(path));
            if (!Directory.Exists(dir)) Directory.CreateDirectory(dir);
            using (FileStream fs = new FileStream(path, FileMode.Create))
            using (BinaryWriter bw = new BinaryWriter(fs))
            {
                bw.Write((ushort)0);
                bw.Write((ushort)1);
                bw.Write((ushort)sizes.Count);
                int offset = 6 + 16 * sizes.Count;
                for (int i = 0; i < sizes.Count; i++)
                {
                    int s = sizes[i];
                    bw.Write((byte)(s >= 256 ? 0 : s));
                    bw.Write((byte)(s >= 256 ? 0 : s));
                    bw.Write((byte)0);
                    bw.Write((byte)0);
                    bw.Write((ushort)1);
                    bw.Write((ushort)32);
                    bw.Write((uint)images[i].Length);
                    bw.Write((uint)offset);
                    offset += images[i].Length;
                }
                foreach (byte[] img in images) bw.Write(img);
            }
        }
    }
}
