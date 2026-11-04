using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace BatAppSetup
{
    public static class Theme
    {
        public static readonly Color Bg = Color.FromArgb(10, 16, 28);
        public static readonly Color Bg2 = Color.FromArgb(15, 23, 42);
        public static readonly Color Card = Color.FromArgb(23, 33, 52);
        public static readonly Color Border = Color.FromArgb(45, 58, 82);
        public static readonly Color Text = Color.FromArgb(229, 231, 235);
        public static readonly Color Muted = Color.FromArgb(148, 163, 184);
        public static readonly Color Accent = Color.FromArgb(14, 165, 233);
        public static readonly Color AccentHover = Color.FromArgb(56, 189, 248);
        public static readonly Color Neon = Color.FromArgb(34, 211, 238);
        public static readonly Color Neon2 = Color.FromArgb(99, 102, 241);
        public static readonly Color Dim = Color.FromArgb(8, 47, 73);
        public static readonly Color Hover = Color.FromArgb(30, 41, 59);
        public static readonly Color Ok = Color.FromArgb(16, 185, 129);

        public static readonly Font Body = new Font("Microsoft YaHei", 9.5f);
        public static readonly Font BodyBold = new Font("Microsoft YaHei", 9.5f, FontStyle.Bold);
        public static readonly Font Small = new Font("Microsoft YaHei", 8.5f);
        public static readonly Font H1 = new Font("Microsoft YaHei", 18f, FontStyle.Bold);
        public static readonly Font H2 = new Font("Microsoft YaHei", 13f, FontStyle.Bold);
        public static readonly Font Mono = new Font("Consolas", 9f);

        public static void StyleButton(Button b, bool primary)
        {
            b.FlatStyle = FlatStyle.Flat;
            b.FlatAppearance.BorderSize = primary ? 0 : 1;
            b.FlatAppearance.BorderColor = Border;
            b.Font = BodyBold;
            b.Cursor = Cursors.Hand;
            b.BackColor = primary ? Accent : Card;
            b.ForeColor = Color.White;
            b.Height = 32;
            Color normal = primary ? Accent : Card;
            Color hover = primary ? AccentHover : Hover;
            b.MouseEnter += delegate { if (b.Enabled) b.BackColor = hover; };
            b.MouseLeave += delegate { b.BackColor = normal; };
        }

        public static void StyleInput(TextBox t)
        {
            t.BackColor = Card;
            t.ForeColor = Text;
            t.BorderStyle = BorderStyle.FixedSingle;
            t.Font = Body;
        }

        public static void StyleLog(RichTextBox r)
        {
            r.BackColor = Color.FromArgb(8, 13, 23);
            r.ForeColor = Color.FromArgb(209, 230, 245);
            r.BorderStyle = BorderStyle.None;
            r.Font = Mono;
        }

        public static void StyleGrid(DataGridView g)
        {
            try
            {
                PropertyInfo db = typeof(DataGridView).GetProperty("DoubleBuffered",
                    BindingFlags.Instance | BindingFlags.NonPublic);
                if (db != null) db.SetValue(g, true, null);
            }
            catch { }
            g.BackgroundColor = Bg2;
            g.BorderStyle = BorderStyle.None;
            g.EnableHeadersVisualStyles = false;
            g.GridColor = Border;
            g.CellBorderStyle = DataGridViewCellBorderStyle.SingleHorizontal;
            g.ColumnHeadersHeight = 34;
            g.ColumnHeadersDefaultCellStyle.BackColor = Card;
            g.ColumnHeadersDefaultCellStyle.ForeColor = Text;
            g.ColumnHeadersDefaultCellStyle.Font = BodyBold;
            g.ColumnHeadersDefaultCellStyle.SelectionBackColor = Card;
            g.ColumnHeadersDefaultCellStyle.SelectionForeColor = Text;
            g.DefaultCellStyle.BackColor = Bg2;
            g.DefaultCellStyle.ForeColor = Text;
            g.DefaultCellStyle.Font = Body;
            g.DefaultCellStyle.SelectionBackColor = Accent;
            g.DefaultCellStyle.SelectionForeColor = Color.White;
            g.AlternatingRowsDefaultCellStyle.BackColor = Color.FromArgb(13, 20, 35);
            g.RowHeadersDefaultCellStyle.BackColor = Card;
            g.RowHeadersDefaultCellStyle.ForeColor = Muted;
            g.RowTemplate.Height = 30;
            g.EditingControlShowing += delegate(object s, DataGridViewEditingControlShowingEventArgs e)
            {
                TextBox tb = e.Control as TextBox;
                if (tb != null)
                {
                    tb.BackColor = Card;
                    tb.ForeColor = Text;
                    tb.BorderStyle = BorderStyle.FixedSingle;
                }
                ComboBox cb = e.Control as ComboBox;
                if (cb != null)
                {
                    cb.BackColor = Card;
                    cb.ForeColor = Text;
                }
            };
        }
    }

    public class DarkMenuColorTable : ProfessionalColorTable
    {
        public override Color ToolStripDropDownBackground { get { return Theme.Card; } }
        public override Color ImageMarginGradientBegin { get { return Theme.Card; } }
        public override Color ImageMarginGradientMiddle { get { return Theme.Card; } }
        public override Color ImageMarginGradientEnd { get { return Theme.Card; } }
        public override Color MenuBorder { get { return Theme.Border; } }
        public override Color MenuItemBorder { get { return Theme.Accent; } }
        public override Color MenuItemSelected { get { return Theme.Accent; } }
        public override Color MenuItemSelectedGradientBegin { get { return Theme.Accent; } }
        public override Color MenuItemSelectedGradientEnd { get { return Theme.Accent; } }
        public override Color CheckBackground { get { return Theme.Accent; } }
        public override Color CheckSelectedBackground { get { return Theme.Accent; } }
        public override Color CheckPressedBackground { get { return Theme.Accent; } }
        public override Color SeparatorDark { get { return Theme.Border; } }
        public override Color SeparatorLight { get { return Theme.Border; } }
    }

    public class DarkMenuRenderer : ToolStripProfessionalRenderer
    {
        public DarkMenuRenderer() : base(new DarkMenuColorTable()) { }
    }

    public class GradientPanel : Panel
    {
        public Color C1 = Color.FromArgb(37, 99, 235);
        public Color C2 = Color.FromArgb(14, 165, 233);

        protected override void OnPaintBackground(PaintEventArgs e)
        {
            Rectangle r = ClientRectangle;
            if (r.Width <= 0 || r.Height <= 0) return;
            using (LinearGradientBrush b = new LinearGradientBrush(r, C1, C2, 0f))
            {
                e.Graphics.FillRectangle(b, r);
            }
            using (SolidBrush glow = new SolidBrush(Color.FromArgb(28, 255, 255, 255)))
            {
                e.Graphics.FillEllipse(glow, r.Width - 260, -70, 320, 220);
            }
        }
    }

    public class TechPanel : Panel
    {
        public bool DrawGrid = true;
        private Bitmap bgCache;
        private int bgW, bgH;

        public TechPanel()
        {
            SetStyle(ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint, true);
        }

        protected override void OnPaintBackground(PaintEventArgs e)
        {
            Rectangle r = ClientRectangle;
            if (r.Width <= 0 || r.Height <= 0) return;
            if (bgCache == null || bgW != r.Width || bgH != r.Height)
            {
                if (bgCache != null) bgCache.Dispose();
                bgCache = new Bitmap(r.Width, r.Height);
                using (Graphics g = Graphics.FromImage(bgCache))
                {
                    using (LinearGradientBrush b = new LinearGradientBrush(r,
                        Color.FromArgb(7, 12, 21), Color.FromArgb(10, 19, 33), 90f))
                    {
                        g.FillRectangle(b, r);
                    }
                    if (DrawGrid)
                    {
                        using (Pen p = new Pen(Color.FromArgb(20, 34, 56)))
                        {
                            for (int x = 0; x < r.Width; x += 40) g.DrawLine(p, x, 0, x, r.Height);
                            for (int y = 0; y < r.Height; y += 40) g.DrawLine(p, 0, y, r.Width, y);
                        }
                    }
                    using (SolidBrush glow = new SolidBrush(Color.FromArgb(16, 34, 211, 238)))
                    {
                        g.FillEllipse(glow, r.Width - 420, -180, 520, 380);
                    }
                }
                bgW = r.Width;
                bgH = r.Height;
            }
            e.Graphics.DrawImageUnscaled(bgCache, 0, 0);
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing && bgCache != null)
            {
                bgCache.Dispose();
                bgCache = null;
            }
            base.Dispose(disposing);
        }
    }

    public class TechHeader : Panel
    {
        public float Scan = 0f;
        public int ScanDir = 1;
        private Bitmap bgCache;
        private Bitmap scanCache;
        private Bitmap scanCacheFlip;
        private int bgW, bgH;
        private const int ScanWidth = 240;

        public TechHeader()
        {
            SetStyle(ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint, true);
        }

        // 推进扫描线并只重绘扫描条经过的区域，避免整块 header 每帧重绘
        public void Step()
        {
            float oldScan = Scan;
            Scan += 0.012f * ScanDir;
            if (Scan >= 1f) { Scan = 1f; ScanDir = -1; }
            else if (Scan <= 0f) { Scan = 0f; ScanDir = 1; }
            InvalidateScan(oldScan);
        }

        private void InvalidateScan(float oldScan)
        {
            int w = ClientSize.Width;
            int h = ClientSize.Height;
            if (w <= 0 || h <= 0) return;
            int half = ScanWidth / 2 + 8;
            int x1 = (int)(oldScan * w) - half;
            int x2 = (int)(Scan * w) - half;
            int left = Math.Min(x1, x2);
            int right = Math.Max(x1, x2) + ScanWidth + 16;
            if (left < 0) left = 0;
            if (right > w) right = w;
            if (right > left) Invalidate(new Rectangle(left, 0, right - left, h));
        }

        protected override void OnPaintBackground(PaintEventArgs e)
        {
            Rectangle r = ClientRectangle;
            if (r.Width <= 0 || r.Height <= 0) return;
            if (bgCache == null || bgW != r.Width || bgH != r.Height)
            {
                if (bgCache != null) bgCache.Dispose();
                if (scanCache != null) { scanCache.Dispose(); scanCache = null; }
                if (scanCacheFlip != null) { scanCacheFlip.Dispose(); scanCacheFlip = null; }
                bgCache = new Bitmap(r.Width, r.Height);
                using (Graphics g = Graphics.FromImage(bgCache))
                {
                    using (LinearGradientBrush b = new LinearGradientBrush(r,
                        Color.FromArgb(5, 12, 22), Color.FromArgb(8, 56, 74), 0f))
                    {
                        ColorBlend cb = new ColorBlend();
                        cb.Positions = new float[] { 0f, 0.52f, 1f };
                        cb.Colors = new Color[] {
                            Color.FromArgb(5, 12, 22),
                            Color.FromArgb(7, 27, 42),
                            Color.FromArgb(8, 56, 74)
                        };
                        b.InterpolationColors = cb;
                        g.FillRectangle(b, r);
                    }
                    using (LinearGradientBrush depth = new LinearGradientBrush(r,
                        Color.FromArgb(55, 0, 0, 0), Color.Transparent, 90f))
                    {
                        g.FillRectangle(depth, r);
                    }
                    using (Pen stripe = new Pen(Color.FromArgb(14, 255, 255, 255)))
                    {
                        for (int x = -r.Height; x < r.Width; x += 22)
                            g.DrawLine(stripe, x, r.Height, x + r.Height, 0);
                    }
                    using (Pen p = new Pen(Color.FromArgb(140, 34, 211, 238)))
                    {
                        g.DrawLine(p, 0, r.Height - 1, r.Width, r.Height - 1);
                        g.DrawLine(p, r.Width - 46, r.Height - 12, r.Width, r.Height - 12);
                        g.DrawLine(p, r.Width - 12, r.Height - 46, r.Width - 12, r.Height);
                    }
                    using (Pen p = new Pen(Color.FromArgb(90, 34, 211, 238)))
                    {
                        g.DrawLine(p, 0, 0, 60, 0);
                        g.DrawLine(p, 0, 0, 0, 24);
                    }
                }
                bgW = r.Width;
                bgH = r.Height;
            }
            e.Graphics.DrawImageUnscaled(bgCache, 0, 0);

            if (scanCache == null) scanCache = BuildScanBar(ScanWidth, r.Height, true);
            if (scanCacheFlip == null) scanCacheFlip = BuildScanBar(ScanWidth, r.Height, false);
            Bitmap bar = ScanDir >= 0 ? scanCache : scanCacheFlip;
            int sx = (int)(Scan * r.Width);
            e.Graphics.DrawImageUnscaled(bar, sx - bar.Width / 2, 0);
        }

        private static Bitmap BuildScanBar(int w, int h, bool tailLeft)
        {
            Bitmap bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb);
            BitmapData data = bmp.LockBits(new Rectangle(0, 0, w, h),
                ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
            byte[] buf = new byte[data.Stride * h];
            int cx = w / 2;
            double slant = 0.28;
            double cy = (h - 1) / 2.0;
            try
            {
                for (int y = 0; y < h; y++)
                {
                    double yNorm = h <= 1 ? 0 : Math.Abs(y - cy) / cy;
                    double vfade = 1.0 - Math.Pow(yNorm, 2.4);
                    if (vfade <= 0) continue;
                    double shift = (y - cy) * slant;
                    int row = y * data.Stride;
                    for (int x = 0; x < w; x++)
                    {
                        double dx = x - cx - shift;
                        double ad = Math.Abs(dx);
                        double core = Math.Exp(-(ad * ad) / 12.5);    // 2.5px 青色主体
                        double hot = Math.Exp(-(ad * ad) / 1.62);     // 0.9px 白热亮芯
                        double mid = Math.Exp(-(ad * ad) / 162.0);    // 9px 过渡层
                        bool tailSide = tailLeft ? (dx <= 0) : (dx >= 0);
                        double haloSigma = tailSide ? 36.0 : 15.0;     // 运动尾迹长于前沿
                        double halo = Math.Exp(-(ad * ad) / (2.0 * haloSigma * haloSigma));
                        double aura = Math.Exp(-(ad * ad) / (2.0 * 55.0 * 55.0));
                        double ht = core * 1.5 + hot * 0.6;
                        if (ht > 1.0) ht = 1.0;
                        int r = (int)(34 + 206 * ht);
                        int g = (int)(211 + 42 * ht);
                        int b = (int)(238 + 17 * ht);
                        int a = (int)((125.0 * core + 88.0 * mid + 52.0 * halo + 14.0 * aura) * vfade);
                        if (a > 255) a = 255;
                        if (a <= 0) continue;
                        int i = row + x * 4;
                        buf[i] = (byte)b;
                        buf[i + 1] = (byte)g;
                        buf[i + 2] = (byte)r;
                        buf[i + 3] = (byte)a;
                    }
                }
                Marshal.Copy(buf, 0, data.Scan0, buf.Length);
            }
            finally
            {
                bmp.UnlockBits(data);
            }
            return bmp;
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                if (bgCache != null) { bgCache.Dispose(); bgCache = null; }
                if (scanCache != null) { scanCache.Dispose(); scanCache = null; }
                if (scanCacheFlip != null) { scanCacheFlip.Dispose(); scanCacheFlip = null; }
            }
            base.Dispose(disposing);
        }
    }

    public static class Ui
    {
        public static GraphicsPath RoundRect(Rectangle r, int radius)
        {
            GraphicsPath p = new GraphicsPath();
            int d = radius * 2;
            p.AddArc(r.X, r.Y, d, d, 180, 90);
            p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
            p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
            p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
            p.CloseFigure();
            return p;
        }
    }

    public class NeonButton : Button
    {
        public bool Primary;
        private bool hover;

        public NeonButton()
        {
            FlatStyle = FlatStyle.Flat;
            FlatAppearance.BorderSize = 0;
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer, true);
            Font = BodyBoldFont();
            ForeColor = Theme.Text;
            BackColor = Theme.Bg;
            Cursor = Cursors.Hand;
        }

        private static Font BodyBoldFont() { return Theme.BodyBold; }

        protected override void OnMouseEnter(EventArgs e)
        {
            hover = true;
            Invalidate();
            base.OnMouseEnter(e);
        }

        protected override void OnMouseLeave(EventArgs e)
        {
            hover = false;
            Invalidate();
            base.OnMouseLeave(e);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            Rectangle r = new Rectangle(0, 0, Width - 1, Height - 1);
            if (!Enabled)
            {
                using (GraphicsPath p0 = Ui.RoundRect(r, 6))
                {
                    using (SolidBrush b = new SolidBrush(Color.FromArgb(13, 23, 38)))
                        g.FillPath(b, p0);
                    using (Pen p = new Pen(Color.FromArgb(50, 45, 58, 82)))
                        g.DrawPath(p, p0);
                }
                TextRenderer.DrawText(g, Text, Font, r, Color.FromArgb(90, 148, 163, 184),
                    TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis);
                return;
            }
            using (GraphicsPath path = Ui.RoundRect(r, 6))
            {
                if (Primary)
                {
                    using (LinearGradientBrush b = new LinearGradientBrush(r,
                        Color.FromArgb(34, 211, 238), Color.FromArgb(79, 70, 229), 0f))
                    {
                        g.FillPath(b, path);
                    }
                    if (hover)
                        using (Pen p = new Pen(Color.FromArgb(200, 165, 243, 252), 1.4f))
                            g.DrawPath(p, path);
                }
                else
                {
                    using (SolidBrush b = new SolidBrush(hover ? Color.FromArgb(16, 48, 68) : Color.FromArgb(13, 23, 38)))
                        g.FillPath(b, path);
                    using (Pen p = new Pen(hover ? Color.FromArgb(200, 34, 211, 238)
                                                 : Color.FromArgb(80, 34, 211, 238), 1f))
                        g.DrawPath(p, path);
                }
            }
            Color txt = Primary ? Color.White : (hover ? Color.White : Theme.Text);
            TextRenderer.DrawText(g, Text, Font, r, txt,
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis);
        }
    }

    public class NavButton : Button
    {
        public bool Active;
        private bool hover;

        public NavButton()
        {
            FlatStyle = FlatStyle.Flat;
            FlatAppearance.BorderSize = 0;
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer, true);
            BackColor = Theme.Bg2;
            ForeColor = Theme.Muted;
            Font = Theme.Body;
            Cursor = Cursors.Hand;
            TextAlign = ContentAlignment.MiddleLeft;
        }

        public void SetActive(bool active)
        {
            Active = active;
            Invalidate();
        }

        protected override void OnMouseEnter(EventArgs e)
        {
            hover = true;
            Invalidate();
            base.OnMouseEnter(e);
        }

        protected override void OnMouseLeave(EventArgs e)
        {
            hover = false;
            Invalidate();
            base.OnMouseLeave(e);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.Clear(Active ? Color.FromArgb(9, 44, 60) : (hover ? Color.FromArgb(17, 41, 58) : Theme.Bg2));

            Color bar = Active ? Theme.Neon : Color.FromArgb(70, 34, 211, 238);
            using (SolidBrush b = new SolidBrush(bar))
                g.FillRectangle(b, 0, 6, Active ? 3 : (hover ? 2 : 1), Height - 12);

            int cx = 15, cy = Height / 2;
            using (SolidBrush dot = new SolidBrush(Active ? Theme.Neon : Color.FromArgb(80, 148, 163, 184)))
            {
                Point[] pts = new Point[] {
                    new Point(cx, cy - 5), new Point(cx + 5, cy),
                    new Point(cx, cy + 5), new Point(cx - 5, cy) };
                g.FillPolygon(dot, pts);
            }

            Font f = Active ? Theme.BodyBold : Theme.Body;
            Color c = Active ? Color.White : (hover ? Theme.Text : Theme.Muted);
            TextRenderer.DrawText(g, Text, f, new Rectangle(32, 0, Width - 38, Height), c,
                TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis);
        }
    }
}
