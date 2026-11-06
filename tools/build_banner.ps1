# Paints DMorph's own banner and "World of Morphcraft" wordmark (6 Nov 2026, user: "make our own in the WoW style";
# then "looks a bit cheap": no more stars, magic ring or shield, just bevelled gold letters on a calm dark band).
# Nothing here comes from Blizzard's art: text from a font file, metal and clouds worked out per pixel.
# Writes PNGs and raw BGRA files; wowport's "rawblp" turns those into BLPs for media\art.
# -Font = the game's Fonts\MORPHEUS.ttf (wowport vextract), -CreditFont = media\fonts\FiraSansCondensed-SemiBold.ttf.
param([Parameter(Mandatory = $true)][string]$Font, [Parameter(Mandatory = $true)][string]$CreditFont, [Parameter(Mandatory = $true)][string]$Out)
$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force $Out | Out-Null
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.IO;
using System.Runtime.InteropServices;

public static class MorphArt {
    static float Clamp(float v, float a, float b) { return v < a ? a : v > b ? b : v; }
    static float Mix(float a, float b, float t) { return a + (b - a) * t; }
    static float Smooth(float a, float b, float x) { float t = Clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); }

    static float[] Blur(float[] src, int w, int h, int r) {
        float[] a = (float[])src.Clone(), b = new float[w * h];
        for (int pass = 0; pass < 3; pass++) {
            for (int y = 0; y < h; y++) {
                float sum = 0; int n = 0;
                for (int x = -r; x < w; x++) {
                    if (x + r < w) { sum += a[y * w + x + r]; n++; }
                    if (x - r - 1 >= 0) { sum -= a[y * w + x - r - 1]; n--; }
                    if (x >= 0) b[y * w + x] = sum / n;
                }
            }
            for (int x = 0; x < w; x++) {
                float sum = 0; int n = 0;
                for (int y = -r; y < h; y++) {
                    if (y + r < h) { sum += b[(y + r) * w + x]; n++; }
                    if (y - r - 1 >= 0) { sum -= b[(y - r - 1) * w + x]; n--; }
                    if (y >= 0) a[y * w + x] = sum / n;
                }
            }
        }
        return a;
    }

    static float[] Read(Bitmap bmp) {
        int w = bmp.Width, h = bmp.Height; float[] m = new float[w * h];
        BitmapData d = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        byte[] p = new byte[w * h * 4]; Marshal.Copy(d.Scan0, p, 0, p.Length); bmp.UnlockBits(d);
        for (int i = 0; i < w * h; i++) m[i] = p[i * 4 + 1] / 255f;
        return m;
    }

    // Letters keep their own proportions: as tall as asked, unless that is wider than maxW.
    static GraphicsPath Text(FontFamily f, string s, float cx, float top, float height, float maxW) {
        GraphicsPath path = new GraphicsPath();
        path.AddString(s, f, (int)FontStyle.Regular, 200, new PointF(0, 0), StringFormat.GenericTypographic);
        RectangleF b = path.GetBounds();
        float k = Math.Min(height / b.Height, maxW / b.Width);
        Matrix m = new Matrix();
        m.Translate(cx - b.Width * k / 2, top);
        m.Scale(k, k);
        m.Translate(-b.X, -b.Y);
        path.Transform(m);
        return path;
    }

    static void Save(string dir, string name, int w, int h, byte[] bgra) {
        File.WriteAllBytes(Path.Combine(dir, name + ".raw"), bgra);
        using (Bitmap o = new Bitmap(w, h, PixelFormat.Format32bppArgb)) {
            BitmapData d = o.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
            Marshal.Copy(bgra, 0, d.Scan0, bgra.Length); o.UnlockBits(d);
            o.Save(Path.Combine(dir, name + ".png"), ImageFormat.Png);
        }
    }

    // The wordmark: 512x256 (the window uses the top 170 rows), painted at twice that.
    public static void Logo(string fontFile, string dir) {
        int W = 1024, H = 512, TOP = 126;   // rows above TOP: the small line
        PrivateFontCollection fonts = new PrivateFontCollection(); fonts.AddFontFile(fontFile);
        FontFamily f = fonts.Families[0];
        float[] flat;
        RectangleF small;
        using (Bitmap bmp = new Bitmap(W, H, PixelFormat.Format32bppArgb))
        using (Graphics g = Graphics.FromImage(bmp)) {
            g.SmoothingMode = SmoothingMode.AntiAlias; g.Clear(Color.Black);
            GraphicsPath top = Text(f, "WORLD OF", W / 2f, 40, 62, 420);
            small = top.GetBounds();
            g.FillPath(Brushes.White, top);
            g.FillPath(Brushes.White, Text(f, "MORPHCRAFT", W / 2f, TOP + 8, 168, 980));
            // Slim tapered rules either side of the small line, each ending in a small diamond.
            float y = small.Top + small.Height / 2;
            foreach (int side in new[] { -1, 1 }) {
                float near = W / 2f + side * (small.Width / 2 + 26), far = W / 2f + side * 380;
                g.FillPolygon(Brushes.White, new[] { new PointF(near, y - 3), new PointF(far, y), new PointF(near, y + 3) });
                float s = 10, c = near - side * 2;
                g.FillPolygon(Brushes.White, new[] { new PointF(c - s, y), new PointF(c, y - s), new PointF(c + s, y), new PointF(c, y + s) });
            }
            flat = Read(bmp);
        }
        float[] mask = new float[W * H];
        float[] thick = Blur(flat, W, H, 2), slight = Blur(flat, W, H, 1);
        for (int i = 0; i < W * H; i++) mask[i] = i / W < TOP ? Smooth(0.28f, 0.5f, slight[i]) : Smooth(0.24f, 0.46f, thick[i]);
        float[] h1 = Blur(mask, W, H, 2), h2 = Blur(mask, W, H, 5);
        float[] outline = Blur(mask, W, H, 4), shadow = Blur(mask, W, H, 9), glow = Blur(mask, W, H, 26);
        byte[] px = new byte[W * H * 4];
        for (int y = 1; y < H - 1; y++) for (int x = 1; x < W - 1; x++) {
            int i = y * W + x;
            float dx = (h1[i + 1] - h1[i - 1]) * 0.7f + (h2[i + 1] - h2[i - 1]) * 1.3f;
            float dy = (h1[i + W] - h1[i - W]) * 0.7f + (h2[i + W] - h2[i - W]) * 1.3f;
            float nx = -dx * 5, ny = -dy * 5, nz = 1, nl = (float)Math.Sqrt(nx * nx + ny * ny + nz * nz); nx /= nl; ny /= nl; nz /= nl;
            float lit = Clamp(nx * -0.4f + ny * -0.65f + nz * 0.62f, 0, 1);
            float spec = (float)Math.Pow(Clamp(nx * -0.3f + ny * -0.5f + nz * 0.81f, 0, 1), 30);
            // Warm metal: pale at the top of each line, deep gold at its foot.
            float line = y < TOP ? (y - 40) / 62f : (y - TOP - 8) / 168f;
            float v = Clamp(lit * 0.78f + (1 - Clamp(line, 0, 1)) * 0.42f - 0.02f, 0, 1);
            float r = v < 0.5f ? Mix(92, 216, v * 2) : Mix(216, 255, (v - 0.5f) * 2);
            float gr = v < 0.5f ? Mix(50, 158, v * 2) : Mix(158, 232, (v - 0.5f) * 2);
            float b = v < 0.5f ? Mix(14, 48, v * 2) : Mix(48, 150, (v - 0.5f) * 2);
            r += spec * 70; gr += spec * 70; b += spec * 80;
            // Layers from the back: faint violet air, soft shadow, near-black outline, the metal.
            float m = Smooth(0.42f, 0.58f, mask[i]);
            float ol = Smooth(0.05f, 0.32f, outline[i]), sh = Smooth(0.01f, 0.3f, shadow[i]) * 0.6f, gl = Clamp(glow[i] * 1.4f, 0, 1) * 0.3f;
            float cr = 96, cg = 58, cb = 190, ca = gl;
            if (sh > 0) { float t = sh / Math.Max(sh + ca * (1 - sh), 0.001f); cr = Mix(cr, 6, t); cg = Mix(cg, 3, t); cb = Mix(cb, 10, t); ca = sh + ca * (1 - sh); }
            if (ol > 0) { cr = Mix(cr, 14, ol); cg = Mix(cg, 7, ol); cb = Mix(cb, 12, ol); ca = Math.Max(ca, ol); }
            cr = Mix(cr, r, m); cg = Mix(cg, gr, m); cb = Mix(cb, b, m); ca = Math.Max(ca, m);
            px[i * 4] = (byte)Clamp(cb, 0, 255); px[i * 4 + 1] = (byte)Clamp(cg, 0, 255); px[i * 4 + 2] = (byte)Clamp(cr, 0, 255); px[i * 4 + 3] = (byte)Clamp(ca * 255, 0, 255);
        }
        // Down to 512x256.
        int w2 = W / 2, h2n = H / 2; byte[] o = new byte[w2 * h2n * 4];
        for (int y = 0; y < h2n; y++) for (int x = 0; x < w2; x++) {
            float aSum = 0, bs = 0, gs = 0, rs = 0;
            for (int k = 0; k < 4; k++) {
                int p = ((y * 2 + (k >> 1)) * W + x * 2 + (k & 1)) * 4; float a = px[p + 3];
                aSum += a; bs += px[p] * a; gs += px[p + 1] * a; rs += px[p + 2] * a;
            }
            int q = (y * w2 + x) * 4;
            if (aSum > 0) { o[q] = (byte)(bs / aSum); o[q + 1] = (byte)(gs / aSum); o[q + 2] = (byte)(rs / aSum); o[q + 3] = (byte)(aSum / 4); }
        }
        Save(dir, "logo", w2, h2n, o);
    }

    // Soft clouds.
    static float[] lattice;
    static float N(float x, float y) {
        int xi = (int)Math.Floor(x), yi = (int)Math.Floor(y); float fx = x - xi, fy = y - yi;
        fx = fx * fx * (3 - 2 * fx); fy = fy * fy * (3 - 2 * fy);
        Func<int, int, float> L = (a, b) => lattice[((a & 255) * 257 + (b & 255) * 31) & 65535];
        return Mix(Mix(L(xi, yi), L(xi + 1, yi), fx), Mix(L(xi, yi + 1), L(xi + 1, yi + 1), fx), fy);
    }
    static float Fbm(float x, float y) { float s = 0, a = 0.5f; for (int i = 0; i < 4; i++) { s += a * N(x, y); x = x * 2.03f + 7; y = y * 2.03f + 3; a *= 0.5f; } return s; }

    // The background: 1024x128, cut into two 512x128 tiles. logoX: the wordmark's middle.
    public static void Banner(string dir, float logoX) {
        int W = 1024, H = 128; Random rnd = new Random(1989);
        lattice = new float[65536]; for (int i = 0; i < 65536; i++) lattice[i] = (float)rnd.NextDouble();
        float[] rgb = new float[W * H * 3];
        for (int y = 0; y < H; y++) for (int x = 0; x < W; x++) {
            // Broad, slow shapes only: fine detail turns blocky in the texture compression.
            float u = x / 300f, v = y / 170f;
            float c = Smooth(0.3f, 0.72f, Fbm(u + Fbm(u + 3, v) * 0.8f, v * 1.4f));
            float dx = (x - logoX) / 330f, dy = (y - 58) / 92f;
            float halo = (float)Math.Exp(-(dx * dx + dy * dy) * 1.5f);
            float edge = (y - H / 2f) / (H / 2f); edge = 1 - edge * edge * 0.45f;      // darker at top and bottom
            float side = 0.72f + 0.28f * Smooth(0, 0.7f, x / (float)W);                 // the text side stays quiet
            float r = (13 + c * 15 + halo * 44) * edge * side;
            float g = (10 + c * 6 + halo * 18) * edge * side;
            float b = (22 + c * 34 + halo * 88) * edge * side;
            rgb[(y * W + x) * 3] = r; rgb[(y * W + x) * 3 + 1] = g; rgb[(y * W + x) * 3 + 2] = b;
        }
        // One fine gold line along the foot, fading out towards the left; a dimmer one along the top.
        for (int x = 0; x < W; x++) {
            float fade = 0.25f + 0.75f * Smooth(0, 0.6f, x / (float)W);
            float[] alpha = { 0.75f * fade, 0.4f * fade };
            for (int e = 0; e < 2; e++) {
                int i = ((H - 1 - e) * W + x) * 3;
                rgb[i] = Mix(rgb[i], 212, alpha[e]); rgb[i + 1] = Mix(rgb[i + 1], 164, alpha[e]); rgb[i + 2] = Mix(rgb[i + 2], 82, alpha[e]);
            }
            int t = x * 3;
            rgb[t] = Mix(rgb[t], 212, 0.22f * fade); rgb[t + 1] = Mix(rgb[t + 1], 164, 0.22f * fade); rgb[t + 2] = Mix(rgb[t + 2], 82, 0.22f * fade);
        }
        byte[] full = new byte[W * H * 4];
        for (int i = 0; i < W * H; i++) { full[i * 4] = (byte)Clamp(rgb[i * 3 + 2], 0, 255); full[i * 4 + 1] = (byte)Clamp(rgb[i * 3 + 1], 0, 255); full[i * 4 + 2] = (byte)Clamp(rgb[i * 3], 0, 255); full[i * 4 + 3] = 255; }
        Save(dir, "banner_full", W, H, full);
        for (int part = 0; part < 2; part++) {
            byte[] tile = new byte[512 * H * 4];
            for (int y = 0; y < H; y++) Array.Copy(full, (y * W + part * 512) * 4, tile, y * 512 * 4, 512 * 4);
            Save(dir, "banner" + (part + 1), 512, H, tile);
        }
    }

    // How it will sit in the window, to look at.
    public static void Preview(string dir, string titleFont, string creditFont, int w, int h, int logoW, int logoH) {
        PrivateFontCollection fonts = new PrivateFontCollection(); fonts.AddFontFile(titleFont); fonts.AddFontFile(creditFont);
        FontFamily title = null, credit = null;
        foreach (FontFamily ff in fonts.Families) { if (ff.Name.IndexOf("Fira", StringComparison.OrdinalIgnoreCase) >= 0) credit = ff; else title = ff; }
        using (Bitmap o = new Bitmap(w * 2, h * 2))
        using (Graphics g = Graphics.FromImage(o))
        using (Image b = Image.FromFile(Path.Combine(dir, "banner_full.png")))
        using (Image l = Image.FromFile(Path.Combine(dir, "logo.png"))) {
            g.ScaleTransform(2, 2);
            g.InterpolationMode = InterpolationMode.HighQualityBilinear;
            g.DrawImage(b, 0, 0, w, h);
            g.DrawImage(l, new Rectangle(w - logoW - 10, 3, logoW, logoH), new Rectangle(0, 0, l.Width, 170), GraphicsUnit.Pixel);
            g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
            using (Font t = new Font(title, 20, FontStyle.Regular, GraphicsUnit.Pixel)) g.DrawString("Weapon glows", t, new SolidBrush(Color.FromArgb(255, 212, 164, 82)), 12, 6);
            using (Font c = new Font(credit, 13, FontStyle.Regular, GraphicsUnit.Pixel)) {
                StringFormat sf = new StringFormat(); sf.Alignment = StringAlignment.Center;
                RectangleF box = new RectangleF(w - logoW - 30, 3 + logoH + 2, logoW + 40, 16);
                g.DrawString("DMorph - Created by Upsilon-Keenhoof-Rag", c, Brushes.Black, new RectangleF(box.X + 1, box.Y + 1, box.Width, box.Height), sf);
                g.DrawString("DMorph - Created by Upsilon-Keenhoof-Rag", c, new SolidBrush(Color.FromArgb(255, 240, 228, 200)), box, sf);
            }
            o.Save(Path.Combine(dir, "preview.png"), ImageFormat.Png);
        }
    }
}
'@
[MorphArt]::Logo($Font, $Out)
[MorphArt]::Banner($Out, 848)
[MorphArt]::Preview($Out, $Font, $CreditFont, 730, 104, 236, 78)
"painted"
