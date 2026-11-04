using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

namespace BatAppSetup
{
    public class Program
    {
        [DllImport("user32.dll")]
        private static extern bool SetProcessDPIAware();

        [STAThread]
        public static void Main(string[] args)
        {
            try { SetProcessDPIAware(); }
            catch { }
            if (args.Length > 0 && args[0] == "-selftest")
            {
                RunSelfTest();
                return;
            }
            if (args.Length > 0 && args[0] == "-uittest")
            {
                RunUiTest();
                return;
            }
            if (args.Length > 0 && args[0] == "-uicapture")
            {
                RunUiCapture();
                return;
            }
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new MainForm());
        }

        private static void RunUiCapture()
        {
            string root = PathHelper.Root;
            using (MainForm f = new MainForm())
            {
                f.Show();
                Application.DoEvents();
                for (int i = 0; i < 6; i++)
                {
                    f.ShowPage(i);
                    Application.DoEvents();
                    Bitmap bmp = new Bitmap(f.Width, f.Height);
                    f.DrawToBitmap(bmp, new Rectangle(0, 0, f.Width, f.Height));
                    bmp.Save(Path.Combine(root, "setup_uicap_" + (i + 1) + ".png"), ImageFormat.Png);
                    bmp.Dispose();
                }
            }
        }

        private static void RunUiTest()
        {
            string root = PathHelper.Root;
            string file = Path.Combine(root, "setup_uittest.txt");
            try
            {
                using (MainForm f = new MainForm())
                {
                    f.Show();
                    Application.DoEvents();
                    File.WriteAllText(file,
                        "OK\r\nbounds=" + f.Bounds + "\r\nclient=" + f.ClientSize +
                        "\r\nscreen=" + Screen.PrimaryScreen.WorkingArea,
                        new UTF8Encoding(false));
                }
            }
            catch (Exception ex)
            {
                File.WriteAllText(file, ex.ToString(), new UTF8Encoding(false));
            }
        }

        private static void RunSelfTest()
        {
            string root = PathHelper.Root;
            StringBuilder sb = new StringBuilder();
            sb.AppendLine("root=" + root);
            sb.AppendLine("runtime=" + Directory.Exists(Path.Combine(root, "runtime")));
            sb.AppendLine("infra=" + Directory.Exists(Path.Combine(root, "infra")));
            sb.AppendLine("jdk17=" + File.Exists(Path.Combine(root, @"runtime\jdk17\bin\java.exe")));
            sb.AppendLine("jdk21=" + File.Exists(Path.Combine(root, @"runtime\jdk21\bin\java.exe")));
            sb.AppendLine("deploy=" + File.Exists(PathHelper.DeployPath(root)));
            sb.AppendLine("apps=" + File.Exists(PathHelper.AppsPath(root)));
            sb.AppendLine("ymlRows=" + YmlEditor.Scan(root).Count);
            File.WriteAllText(Path.Combine(root, "setup_selftest.txt"), sb.ToString(), new UTF8Encoding(false));
        }
    }
}
