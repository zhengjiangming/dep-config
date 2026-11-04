using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;

namespace BatAppSetup
{
    public class MainForm : Form
    {
        private Panel contentPanel;
        private NavButton[] navs;
        private Panel[] pages;
        private Label lblWorkDir;
        private Label lblStatus;
        private TextBox txtTarget;
        private CheckBox chkInit;
        private CheckBox chkShortcut;
        private RichTextBox txtInstallLog;
        private Dictionary<string, TextBox> deployBoxes = new Dictionary<string, TextBox>();
        private DataGridView dgvApps;
        private DataGridView dgvYml;
        private RichTextBox txtCfgFile;
        private RichTextBox txtRunLog;
        private DataGridView dgvUnits;
        private List<UnitRow> units = new List<UnitRow>();
        private ListBox lstCfgFiles;
        private List<CfgItem> cfgItems = new List<CfgItem>();
        private string currentCfgRel = "";
        private bool loadingCfgList;
        private bool ymlDirty;
        private bool loadingYml;
        private int lastCfgIndex = -1;
        private Label lblCfgPath;
        private TextBox txtCfgName;
        private TextBox txtCfgNew;
        private List<YmlRow> deletedYmlRows = new List<YmlRow>();
        private List<NacosCfg> nacosCfgs = new List<NacosCfg>();
        private NacosCfg currentNacos;
        private NeonButton btnNacosPick;
        private int nacosIndex = -1;
        private Font cfgTitleFont = new Font("Microsoft YaHei", 9.5f, FontStyle.Bold);
        private Font cfgPathFont = new Font("Consolas", 7.5f);

        private class NacosCfg
        {
            public string DataId;
            public string Group;
            public string Tenant;
            public string Type;
            public string Content;
            public override string ToString()
            {
                return DataId + "   [" + Group + "]";
            }
        }

        private class UnitRow
        {
            public string Name;
            public string Type;
            public string Host;
            public int Port;
            public bool Local;
            public bool IsApp;
            public string Key;
        }

        private class ScriptItem
        {
            public string Path;
            public string Display;
            public override string ToString() { return Display; }
        }

        private Button btnInstall;
        private Button btnStart;
        private Button btnStop;
        private Button btnStatus;
        private Button btnInitNow;
        private Button btnImport;
        private CheckedListBox lstSqlScripts;
        private Label lblSqlEmpty;
        private ComboBox cmbSqlTarget;
        private TextBox txtSqlDb;
        private Button btnSqlInit;
        private string workDir;
        private bool running;
        private int currentPage = -1;
        private TechHeader header;
        private System.Windows.Forms.Timer fxTimer;
        private Label lblClock;
        private int fxTick;
        private Color statusColor = Theme.Ok;

        public MainForm()
        {
            workDir = PathHelper.Root;
            try
            {
                System.Drawing.Icon appIcon = System.Drawing.Icon.ExtractAssociatedIcon(Application.ExecutablePath);
                if (appIcon != null) Icon = appIcon;
            }
            catch { }
            BuildUi();
            ShowPage(0);
            ReloadAll();
        }

        [DllImport("dwmapi.dll", PreserveSig = true)]
        private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);

        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            try
            {
                int dark = 1;
                DwmSetWindowAttribute(Handle, 20, ref dark, 4);   // Windows 11
                DwmSetWindowAttribute(Handle, 19, ref dark, 4);   // Windows 10 1809+
            }
            catch { }
        }

        // ---------------- shell ----------------
        private void BuildUi()
        {
            Text = "智能部署中心";
            BackColor = Theme.Bg;
            ForeColor = Theme.Text;
            Rectangle wa = Screen.PrimaryScreen.WorkingArea;
            float dpi = DpiScale();
            // 按当前 DPI 放大设计尺寸，窄屏时再收缩到工作区内，保证窗口永远不超出屏幕
            int wantW = (int)(1080 * dpi);
            int wantH = (int)(740 * dpi);
            int w = Math.Min(wantW, Math.Max(560, wa.Width - 40));
            int h = Math.Min(wantH, Math.Max(380, wa.Height - 70));
            ClientSize = new Size(w, h);
            MinimumSize = new Size(
                Math.Min((int)(900 * dpi), w + 16),
                Math.Min((int)(560 * dpi), h + 39));
            StartPosition = FormStartPosition.Manual;
            Location = new Point(
                wa.Left + Math.Max(12, (wa.Width - (w + 16)) / 2),
                wa.Top + Math.Max(12, (wa.Height - (h + 39)) / 2));
            DoubleBuffered = true;

            TableLayoutPanel root = new TableLayoutPanel();
            root.Dock = DockStyle.Fill;
            root.ColumnCount = 1;
            root.RowCount = 3;
            root.BackColor = Theme.Bg;
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, 60));
            root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, 28));
            Controls.Add(root);

            root.Controls.Add(header = BuildHeader(), 0, 0);

            TableLayoutPanel mid = new TableLayoutPanel();
            mid.Dock = DockStyle.Fill;
            mid.ColumnCount = 2;
            mid.RowCount = 1;
            mid.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 200));
            mid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            mid.BackColor = Theme.Bg;
            root.Controls.Add(mid, 0, 1);

            mid.Controls.Add(BuildNav(), 0, 0);

            contentPanel = new Panel();
            contentPanel.Dock = DockStyle.Fill;
            contentPanel.BackColor = Theme.Bg;
            contentPanel.Padding = new Padding(18, 4, 18, 10);
            contentPanel.AutoScroll = true;
            mid.Controls.Add(contentPanel, 1, 0);
            contentPanel.Resize += delegate { FitPages(); };

            root.Controls.Add(BuildStatus(), 0, 2);
            StartFx();
            Resize += delegate { SyncFxTimer(); };
            VisibleChanged += delegate { SyncFxTimer(); };
            FormClosed += delegate { if (fxTimer != null) fxTimer.Stop(); };
        }

        private static float DpiScale()
        {
            try
            {
                using (Graphics g = Graphics.FromHwnd(IntPtr.Zero))
                {
                    float s = g.DpiX / 96f;
                    if (s < 1f) s = 1f;
                    if (s > 3f) s = 3f;
                    return s;
                }
            }
            catch { return 1f; }
        }

        // 内容区在窗口过小时可滚动：页面保持最小可用尺寸，其余空间自适应
        private const int MinPageW = 760;
        private const int MinPageH = 520;

        private void FitPages()
        {
            if (pages == null || contentPanel == null) return;
            int cw = contentPanel.ClientSize.Width - contentPanel.Padding.Horizontal;
            int ch = contentPanel.ClientSize.Height - contentPanel.Padding.Vertical;
            int pw = Math.Max(MinPageW, cw);
            int ph = Math.Max(MinPageH, ch);
            for (int i = 0; i < pages.Length; i++)
            {
                Panel p = pages[i];
                if (p == null) continue;
                p.Location = new Point(contentPanel.Padding.Left, contentPanel.Padding.Top);
                p.Size = new Size(pw, ph);
            }
        }

        private void StartFx()
        {
            fxTimer = new System.Windows.Forms.Timer();
            fxTimer.Interval = 120;
            fxTimer.Tick += delegate
            {
                fxTick++;
                if (header != null) header.Step();
                if (lblClock != null && (fxTick % 8) == 0)
                    lblClock.Text = "SYS   " + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss");
                if (lblStatus != null)
                {
                    lblStatus.ForeColor = (fxTick % 12) < 7 ? statusColor
                        : Color.FromArgb((statusColor.R + Theme.Bg2.R) / 2,
                                         (statusColor.G + Theme.Bg2.G) / 2,
                                         (statusColor.B + Theme.Bg2.B) / 2);
                }
            };
            SyncFxTimer();
        }

        // 窗口最小化或隐藏时暂停动画，避免后台空转
        private void SyncFxTimer()
        {
            if (fxTimer == null) return;
            bool run = Visible && WindowState != FormWindowState.Minimized;
            if (run && !fxTimer.Enabled) fxTimer.Start();
            else if (!run && fxTimer.Enabled) fxTimer.Stop();
        }

        private TechHeader BuildHeader()
        {
            TechHeader h = new TechHeader();
            h.Dock = DockStyle.Fill;

            Label sub = new Label();
            sub.Text = "部署  ·  配置管理  ·  服务编排";
            sub.Font = Theme.Body;
            sub.ForeColor = Color.FromArgb(190, 227, 245);
            sub.BackColor = Color.Transparent;
            sub.SetBounds(28, 20, 500, 22);
            h.Controls.Add(sub);

            Label clock = new Label();
            clock.Text = "SYS   " + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss");
            clock.Font = new Font("Consolas", 8.5f);
            clock.ForeColor = Color.FromArgb(125, 211, 252);
            clock.BackColor = Color.Transparent;
            clock.TextAlign = ContentAlignment.MiddleRight;
            clock.SetBounds(0, 17, 300, 26);
            h.Resize += delegate { clock.Left = h.ClientSize.Width - 580; };
            h.Controls.Add(clock);
            lblClock = clock;

            Label chip = new Label();
            chip.Text = "OFFLINE  ·  JDK 17 / 21";
            chip.Font = Theme.Small;
            chip.ForeColor = Color.FromArgb(186, 230, 253);
            chip.BackColor = Color.FromArgb(10, 48, 68);
            chip.TextAlign = ContentAlignment.MiddleCenter;
            chip.SetBounds(0, 17, 236, 26);
            h.Resize += delegate { chip.Left = h.ClientSize.Width - 256; };
            h.Controls.Add(chip);

            return h;
        }

        private Panel BuildNav()
        {
            Panel nav = new Panel();
            nav.Dock = DockStyle.Fill;
            nav.BackColor = Theme.Bg2;

            Label caption = new Label();
            caption.Text = "功能导航";
            caption.Font = Theme.Small;
            caption.ForeColor = Theme.Muted;
            caption.SetBounds(22, 18, 150, 20);
            nav.Controls.Add(caption);

            Panel line = new Panel();
            line.Dock = DockStyle.Right;
            line.Width = 1;
            line.BackColor = Theme.Border;
            nav.Controls.Add(line);

            Label ver = new Label();
            ver.Text = "v1.0  ·  OFFLINE";
            ver.Font = new Font("Microsoft YaHei", 8f);
            ver.ForeColor = Color.FromArgb(100, 116, 139);
            ver.Dock = DockStyle.Bottom;
            ver.Height = 36;
            ver.TextAlign = ContentAlignment.MiddleLeft;
            ver.Padding = new Padding(22, 0, 0, 0);
            nav.Controls.Add(ver);

            string[] names = new string[] { "安装部署", "部署参数", "服务清单", "YML 配置", "组件控制", "运行控制" };
            navs = new NavButton[names.Length];
            for (int i = 0; i < names.Length; i++)
            {
                NavButton b = new NavButton();
                b.Text = names[i];
                b.SetBounds(12, 52 + i * 52, 176, 44);
                b.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
                int index = i;
                b.Click += delegate { ShowPage(index); };
                nav.Controls.Add(b);
                navs[i] = b;
            }
            return nav;
        }

        private Panel BuildStatus()
        {
            Panel p = new Panel();
            p.Dock = DockStyle.Fill;
            p.BackColor = Theme.Bg2;

            lblWorkDir = new Label();
            lblWorkDir.Dock = DockStyle.Fill;
            lblWorkDir.TextAlign = ContentAlignment.MiddleLeft;
            lblWorkDir.Padding = new Padding(16, 0, 0, 0);
            lblWorkDir.Font = Theme.Small;
            lblWorkDir.ForeColor = Theme.Muted;
            p.Controls.Add(lblWorkDir);

            lblStatus = new Label();
            lblStatus.Dock = DockStyle.Right;
            lblStatus.Width = 160;
            lblStatus.TextAlign = ContentAlignment.MiddleRight;
            lblStatus.Padding = new Padding(0, 0, 16, 0);
            lblStatus.Font = Theme.BodyBold;
            lblStatus.ForeColor = Theme.Ok;
            lblStatus.Text = "●  就绪";
            p.Controls.Add(lblStatus);

            return p;
        }

        private Panel CreatePage(string title, string subtitle, out Panel body)
        {
            TechPanel page = new TechPanel();
            page.DrawGrid = true;
            page.BackColor = Theme.Bg;
            page.Visible = false;
            page.Anchor = AnchorStyles.Top | AnchorStyles.Left;

            TableLayoutPanel t = new TableLayoutPanel();
            t.Dock = DockStyle.Fill;
            t.ColumnCount = 1;
            t.RowCount = 2;
            t.BackColor = Color.Transparent;
            t.RowStyles.Add(new RowStyle(SizeType.Absolute, 62));
            t.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            page.Controls.Add(t);

            Panel head = new Panel();
            head.Dock = DockStyle.Fill;
            head.BackColor = Color.Transparent;
            Label lt = new Label();
            lt.Text = title;
            lt.Font = Theme.H2;
            lt.ForeColor = Theme.Text;
            lt.BackColor = Color.Transparent;
            lt.AutoSize = false;
            lt.AutoEllipsis = true;
            lt.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
            lt.SetBounds(0, 2, 700, 28);
            Label ls = new Label();
            ls.Text = subtitle;
            ls.Font = Theme.Small;
            ls.ForeColor = Theme.Muted;
            ls.BackColor = Color.Transparent;
            ls.AutoSize = false;
            ls.AutoEllipsis = true;
            ls.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
            ls.SetBounds(1, 32, 700, 20);
            head.Controls.Add(lt);
            head.Controls.Add(ls);
            head.Resize += delegate
            {
                lt.Width = Math.Max(120, head.ClientSize.Width);
                ls.Width = Math.Max(120, head.ClientSize.Width - 1);
            };
            t.Controls.Add(head, 0, 0);

            body = new Panel();
            body.Dock = DockStyle.Fill;
            body.BackColor = Color.Transparent;
            t.Controls.Add(body, 0, 1);
            return page;
        }

        private void BuildPages()
        {
            pages = new Panel[6];
            int i = 0;

            Panel body;
            pages[i] = CreatePage("安装部署", "选择目录后一键复制 runtime / infra / apps，并写入配置、初始化数据", out body);
            BuildInstallPage(body);
            i++;

            pages[i] = CreatePage("部署参数", "conf\\deploy.properties：访问地址、各组件主机、端口与启动开关", out body);
            BuildDeployPage(body);
            i++;

            pages[i] = CreatePage("服务清单", "conf\\apps.cfg 服务清单，主机分配到 conf\\service-hosts.cfg", out body);
            BuildAppsPage(body);
            i++;

            pages[i] = CreatePage("YML 配置", "本地文件或 Nacos 在线配置，原位修改属性值，可直接保存到 Nacos", out body);
            BuildYmlPage(body);
            i++;

            pages[i] = CreatePage("组件控制", "全部中间件与服务列表，可对单个组件启动 / 停止 / 重启（含 Nginx）", out body);
            BuildUnitsPage(body);
            i++;

            pages[i] = CreatePage("运行控制", "数据目录初始化、本地 SQL 脚本导入、启停与状态、Nacos 配置同步", out body);
            BuildRunPage(body);

            foreach (Panel p in pages) contentPanel.Controls.Add(p);
        }

        public void ShowPage(int index)
        {
            if (pages == null) { BuildPages(); FitPages(); }
            if (index == currentPage && pages[index].Visible) return;
            contentPanel.SuspendLayout();
            for (int i = 0; i < pages.Length; i++)
            {
                pages[i].Visible = (i == index);
                navs[i].SetActive(i == index);
            }
            contentPanel.ResumeLayout();
            pages[index].BringToFront();
            currentPage = index;
        }

        // ---------------- pages ----------------
        private void BuildInstallPage(Panel body)
        {
            TableLayoutPanel t = new TableLayoutPanel();
            t.Dock = DockStyle.Fill;
            t.ColumnCount = 1;
            t.RowCount = 4;
            t.BackColor = Color.Transparent;
            t.RowStyles.Add(new RowStyle(SizeType.Absolute, 22));
            t.RowStyles.Add(new RowStyle(SizeType.Absolute, 40));
            t.RowStyles.Add(new RowStyle(SizeType.Absolute, 50));
            t.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            body.Controls.Add(t);

            Label l = new Label();
            l.Text = "安装目录（不能含空格，建议 D:\\bat_application）";
            l.Font = Theme.Small;
            l.ForeColor = Theme.Muted;
            l.Dock = DockStyle.Fill;
            t.Controls.Add(l, 0, 0);

            Panel pathRow = new Panel();
            pathRow.Dock = DockStyle.Fill;
            pathRow.BackColor = Color.Transparent;
            pathRow.Padding = new Padding(0, 4, 0, 4);
            t.Controls.Add(pathRow, 0, 1);

            txtTarget = new TextBox();
            txtTarget.Dock = DockStyle.Fill;
            Theme.StyleInput(txtTarget);
            pathRow.Controls.Add(txtTarget);

            Button browse = MakeButton("浏览...", false);
            browse.Dock = DockStyle.Right;
            browse.Width = 100;
            browse.Click += delegate
            {
                FolderBrowserDialog dlg = new FolderBrowserDialog();
                dlg.Description = "选择安装目录";
                if (dlg.ShowDialog(this) == DialogResult.OK) txtTarget.Text = dlg.SelectedPath;
            };
            pathRow.Controls.Add(browse);

            FlowLayoutPanel bar = new FlowLayoutPanel();
            bar.Dock = DockStyle.Fill;
            bar.BackColor = Color.Transparent;
            bar.Padding = new Padding(0, 6, 0, 0);
            bar.WrapContents = false;
            t.Controls.Add(bar, 0, 2);

            btnInstall = MakeButton("开始安装", true);
            btnInstall.Width = 140;
            btnInstall.Height = 38;
            btnInstall.Margin = new Padding(0, 0, 16, 0);
            btnInstall.Click += delegate { OnInstall(); };
            bar.Controls.Add(btnInstall);

            chkInit = new CheckBox();
            chkInit.Text = "初始化 MySQL / PostgreSQL 数据目录";
            chkInit.ForeColor = Theme.Text;
            chkInit.Font = Theme.Body;
            chkInit.AutoSize = true;
            chkInit.Margin = new Padding(0, 15, 18, 0);
            chkInit.Checked = true;
            bar.Controls.Add(chkInit);

            chkShortcut = new CheckBox();
            chkShortcut.Text = "创建桌面快捷方式";
            chkShortcut.ForeColor = Theme.Text;
            chkShortcut.Font = Theme.Body;
            chkShortcut.AutoSize = true;
            chkShortcut.Margin = new Padding(0, 15, 0, 0);
            chkShortcut.Checked = true;
            bar.Controls.Add(chkShortcut);

            Panel logWrap = new Panel();
            logWrap.Dock = DockStyle.Fill;
            logWrap.BackColor = Theme.Border;
            logWrap.Padding = new Padding(1);
            logWrap.Margin = new Padding(0, 6, 0, 0);
            t.Controls.Add(logWrap, 0, 3);

            txtInstallLog = new RichTextBox();
            txtInstallLog.Dock = DockStyle.Fill;
            txtInstallLog.ReadOnly = true;
            Theme.StyleLog(txtInstallLog);
            logWrap.Controls.Add(txtInstallLog);
        }

        private void BuildDeployPage(Panel body)
        {
            TableLayoutPanel bt = new TableLayoutPanel();
            bt.Dock = DockStyle.Fill;
            bt.ColumnCount = 1;
            bt.RowCount = 2;
            bt.BackColor = Color.Transparent;
            bt.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            bt.RowStyles.Add(new RowStyle(SizeType.Absolute, 48));
            body.Controls.Add(bt);

            Panel scroll = new Panel();
            scroll.Dock = DockStyle.Fill;
            scroll.AutoScroll = true;
            scroll.BackColor = Color.Transparent;
            bt.Controls.Add(scroll, 0, 0);

            TableLayoutPanel t = new TableLayoutPanel();
            t.Dock = DockStyle.Top;
            t.ColumnCount = 4;
            t.RowCount = (DeployConfig.Keys.Length + 1) / 2;
            t.Height = t.RowCount * 36 + 8;
            t.BackColor = Color.Transparent;
            t.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 175));
            t.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
            t.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 175));
            t.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
            scroll.Controls.Add(t);

            for (int i = 0; i < DeployConfig.Keys.Length; i++)
            {
                string key = DeployConfig.Keys[i];
                int row = i / 2;
                int col = (i % 2) * 2;
                Label lbl = new Label();
                lbl.Text = key;
                lbl.TextAlign = ContentAlignment.MiddleLeft;
                lbl.Dock = DockStyle.Fill;
                lbl.Font = new Font("Consolas", 9f);
                lbl.ForeColor = Theme.Muted;
                TextBox tb = new TextBox();
                tb.Dock = DockStyle.Fill;
                tb.Margin = new Padding(2, 6, 12, 6);
                Theme.StyleInput(tb);
                t.Controls.Add(lbl, col, row);
                t.Controls.Add(tb, col + 1, row);
                deployBoxes[key] = tb;
            }

            Panel bar = new Panel();
            bar.Dock = DockStyle.Fill;
            bar.BackColor = Color.Transparent;
            bt.Controls.Add(bar, 0, 1);

            NeonButton reload = MakeButton("重新读取", false);
            reload.SetBounds(0, 8, 110, 32);
            NeonButton save = MakeButton("保存参数", true);
            save.SetBounds(120, 8, 110, 32);
            Label deployHint = new Label();
            deployHint.Text = "MINIO_DATA_DIR 留空 = data\\minio，可填绝对路径";
            deployHint.AutoSize = true;
            deployHint.Font = Theme.Small;
            deployHint.ForeColor = Theme.Muted;
            deployHint.Location = new Point(252, 14);
            bar.Controls.Add(deployHint);
            bar.Controls.Add(reload);
            bar.Controls.Add(save);
            reload.Click += delegate
            {
                if (DeployDirty() && MessageBox.Show("部署参数有未保存的修改，重新读取将放弃这些修改。\r\n确定继续？",
                    "未保存的修改", MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes) return;
                ReloadDeploy();
            };
            save.Click += delegate
            {
                DeployConfig cfg = CollectDeploy();
                string bad = ValidateConfigNumbers(cfg, CollectApps());
                if (bad.Length > 0)
                {
                    MessageBox.Show(bad, "配置有误");
                    return;
                }
                cfg.Save(workDir);
                MessageBox.Show("部署参数已保存到 " + PathHelper.DeployPath(workDir));
            };
        }

        private void BuildAppsPage(Panel body)
        {
            TableLayoutPanel bt = new TableLayoutPanel();
            bt.Dock = DockStyle.Fill;
            bt.ColumnCount = 1;
            bt.RowCount = 3;
            bt.BackColor = Color.Transparent;
            bt.RowStyles.Add(new RowStyle(SizeType.Absolute, 40));
            bt.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            bt.RowStyles.Add(new RowStyle(SizeType.Absolute, 48));
            body.Controls.Add(bt);

            FlowLayoutPanel nodeBar = new FlowLayoutPanel();
            nodeBar.Dock = DockStyle.Fill;
            nodeBar.BackColor = Color.Transparent;
            nodeBar.WrapContents = false;
            nodeBar.Padding = new Padding(0, 4, 0, 0);
            bt.Controls.Add(nodeBar, 0, 0);

            Label nodeLbl = new Label();
            nodeLbl.Text = "节点主机";
            nodeLbl.AutoSize = true;
            nodeLbl.Font = Theme.Small;
            nodeLbl.ForeColor = Theme.Muted;
            nodeLbl.Margin = new Padding(0, 6, 6, 0);
            nodeBar.Controls.Add(nodeLbl);

            TextBox txtNodeHost = new TextBox();
            txtNodeHost.Width = 150;
            txtNodeHost.Margin = new Padding(0, 2, 6, 0);
            Theme.StyleInput(txtNodeHost);
            nodeBar.Controls.Add(txtNodeHost);

            NeonButton packNode = MakeButton("生成节点包", true);
            packNode.Width = 120;
            packNode.Height = 26;
            packNode.Margin = new Padding(0, 0, 8, 0);
            nodeBar.Controls.Add(packNode);

            Label nodeHint = new Label();
            nodeHint.Text = "留空 = 按 service-hosts.cfg 中所有远程主机生成";
            nodeHint.AutoSize = true;
            nodeHint.Font = Theme.Small;
            nodeHint.ForeColor = Theme.Muted;
            nodeHint.Margin = new Padding(0, 6, 0, 0);
            nodeBar.Controls.Add(nodeHint);
            packNode.Click += delegate { GenerateNodePackages(txtNodeHost.Text.Trim()); };

            dgvApps = new DataGridView();
            dgvApps.Dock = DockStyle.Fill;
            dgvApps.AllowUserToAddRows = true;
            dgvApps.AllowUserToDeleteRows = true;
            dgvApps.SelectionMode = DataGridViewSelectionMode.FullRowSelect;
            dgvApps.RowHeadersWidth = 30;
            dgvApps.AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.None;
            Theme.StyleGrid(dgvApps);
            AddTextCol(dgvApps, "name", "服务名", 100, false);
            AddTextCol(dgvApps, "jar", "jar 路径", 180, false);
            AddTextCol(dgvApps, "port", "端口", 64, false);
            DataGridViewComboBoxColumn jdk = new DataGridViewComboBoxColumn();
            jdk.HeaderText = "JDK";
            jdk.Name = "jdk";
            jdk.Width = 60;
            jdk.DisplayStyle = DataGridViewComboBoxDisplayStyle.Nothing;
            jdk.Items.Add("17");
            jdk.Items.Add("21");
            dgvApps.Columns.Add(jdk);
            AddTextCol(dgvApps, "host", "主机", 100, false);
            AddTextCol(dgvApps, "jvm", "JVM 参数", 140, false);
            AddTextCol(dgvApps, "extra", "额外参数", 140, false);
            dgvApps.Resize += delegate { LayoutApps(); };
            bt.Controls.Add(dgvApps, 0, 1);

            Panel bar = new Panel();
            bar.Dock = DockStyle.Fill;
            bar.BackColor = Color.Transparent;
            bt.Controls.Add(bar, 0, 2);

            NeonButton reload = MakeButton("重新读取", false);
            reload.SetBounds(0, 8, 110, 32);
            NeonButton save = MakeButton("保存清单", true);
            save.SetBounds(120, 8, 110, 32);
            NeonButton startSel = MakeButton("启动选中", false);
            startSel.SetBounds(240, 8, 110, 32);
            NeonButton stopSel = MakeButton("停止选中", false);
            stopSel.SetBounds(360, 8, 110, 32);
            NeonButton restartSel = MakeButton("重启选中", true);
            restartSel.SetBounds(480, 8, 110, 32);
            bar.Controls.Add(reload);
            bar.Controls.Add(save);
            bar.Controls.Add(startSel);
            bar.Controls.Add(stopSel);
            bar.Controls.Add(restartSel);
            reload.Click += delegate
            {
                if (AppsDirty() && MessageBox.Show("服务清单有未保存的修改，重新读取将放弃这些修改。\r\n确定继续？",
                    "未保存的修改", MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes) return;
                ReloadApps();
            };
            save.Click += delegate
            {
                string badName = FindAppNameError();
                if (badName.Length > 0)
                {
                    MessageBox.Show(badName, "配置有误");
                    return;
                }
                AppsConfig cfg = CollectApps();
                string bad = ValidateConfigNumbers(CollectDeploy(), cfg);
                if (bad.Length > 0)
                {
                    MessageBox.Show(bad, "配置有误");
                    return;
                }
                cfg.Save(workDir);
                MessageBox.Show("服务清单已保存到 " + PathHelper.AppsPath(workDir));
            };
            startSel.Click += delegate { ServiceAction("start"); };
            stopSel.Click += delegate { ServiceAction("stop"); };
            restartSel.Click += delegate { ServiceAction("restart"); };
        }

        private void BuildYmlPage(Panel body)
        {
            TableLayoutPanel bt = new TableLayoutPanel();
            bt.Dock = DockStyle.Fill;
            bt.ColumnCount = 1;
            bt.RowCount = 2;
            bt.BackColor = Color.Transparent;
            bt.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            bt.RowStyles.Add(new RowStyle(SizeType.Absolute, 48));
            body.Controls.Add(bt);

            TableLayoutPanel main = new TableLayoutPanel();
            main.Dock = DockStyle.Fill;
            main.ColumnCount = 2;
            main.RowCount = 1;
            main.BackColor = Color.Transparent;
            main.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 330));
            main.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            bt.Controls.Add(main, 0, 0);

            TableLayoutPanel left = new TableLayoutPanel();
            left.Dock = DockStyle.Fill;
            left.ColumnCount = 1;
            left.RowCount = 4;
            left.BackColor = Color.Transparent;
            left.RowStyles.Add(new RowStyle(SizeType.Absolute, 34));
            left.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            left.RowStyles.Add(new RowStyle(SizeType.Absolute, 42));
            left.RowStyles.Add(new RowStyle(SizeType.Absolute, 36));
            main.Controls.Add(left, 0, 0);

            FlowLayoutPanel capBar = new FlowLayoutPanel();
            capBar.Dock = DockStyle.Fill;
            capBar.BackColor = Color.Transparent;
            capBar.WrapContents = false;
            capBar.Padding = new Padding(0, 4, 0, 0);
            left.Controls.Add(capBar, 0, 0);

            Label cap = new Label();
            cap.Text = "清单名称";
            cap.AutoSize = true;
            cap.Font = Theme.Small;
            cap.ForeColor = Theme.Muted;
            cap.Margin = new Padding(0, 4, 6, 0);
            capBar.Controls.Add(cap);

            txtCfgName = new TextBox();
            Theme.StyleInput(txtCfgName);
            txtCfgName.Width = 190;
            txtCfgName.Font = Theme.Small;
            txtCfgName.Margin = new Padding(0, 0, 6, 0);
            capBar.Controls.Add(txtCfgName);
            txtCfgName.Leave += delegate
            {
                string n = txtCfgName.Text.Trim();
                if (n.Length == 0) n = "配置文件清单";
                ConfigList.SaveItems(workDir, n, cfgItems);
            };
            ToolTip nameTip = new ToolTip();
            nameTip.SetToolTip(txtCfgName, "清单名称，保存在 conf\\config-files.cfg 的 # NAME= 行");

            lstCfgFiles = new ListBox();
            lstCfgFiles.Dock = DockStyle.Fill;
            lstCfgFiles.BorderStyle = BorderStyle.None;
            lstCfgFiles.BackColor = Theme.Card;
            lstCfgFiles.ForeColor = Theme.Text;
            lstCfgFiles.Font = Theme.Small;
            lstCfgFiles.IntegralHeight = false;
            lstCfgFiles.DrawMode = DrawMode.OwnerDrawFixed;
            // 行高按字体实际高度计算，避免高 DPI 下标题与路径重叠
            lstCfgFiles.ItemHeight = 6 + cfgTitleFont.Height + 2 + cfgPathFont.Height + 6;
            lstCfgFiles.DrawItem += delegate(object s, DrawItemEventArgs e)
            {
                if (e.Index < 0) return;
                CfgItem it = lstCfgFiles.Items[e.Index] as CfgItem;
                if (it == null) return;
                bool sel = (e.State & DrawItemState.Selected) != 0;
                using (SolidBrush bg = new SolidBrush(sel ? Theme.Accent : Theme.Card))
                    e.Graphics.FillRectangle(bg, e.Bounds);
                StringFormat ell = new StringFormat();
                ell.Trimming = StringTrimming.EllipsisCharacter;
                ell.FormatFlags = StringFormatFlags.NoWrap;
                int w = e.Bounds.Width - 20;
                int tx = e.Bounds.Left + 10;
                int top = e.Bounds.Top + 5;
                int titleH = cfgTitleFont.Height;
                string title = it.Name.Length > 0 ? it.Name : it.Path;
                using (SolidBrush tb = new SolidBrush(Color.White))
                    e.Graphics.DrawString(title, cfgTitleFont, tb,
                        new RectangleF(tx, top, w, titleH), ell);
                if (it.Name.Length > 0 && it.Path.Length > 0)
                {
                    string fullPath = Path.IsPathRooted(it.Path) ? it.Path : Path.Combine(workDir, it.Path);
                    ell.Trimming = StringTrimming.EllipsisPath;
                    using (SolidBrush pb = new SolidBrush(sel ? Color.FromArgb(226, 240, 252) : Theme.Muted))
                        e.Graphics.DrawString(fullPath, cfgPathFont, pb,
                            new RectangleF(tx, top + titleH + 2, w, cfgPathFont.Height), ell);
                }
                ell.Dispose();
            };
            lstCfgFiles.SelectedIndexChanged += delegate
            {
                if (loadingCfgList) return;
                if (!ConfirmDiscardYml())
                {
                    loadingCfgList = true;
                    lstCfgFiles.SelectedIndex = lastCfgIndex;
                    loadingCfgList = false;
                    return;
                }
                lastCfgIndex = lstCfgFiles.SelectedIndex;
                if (currentNacos != null)
                {
                    currentNacos = null;
                    nacosIndex = -1;
                    if (btnNacosPick != null) btnNacosPick.Text = "Nacos: 未选择  ▾";
                }
                CfgItem it = lstCfgFiles.SelectedItem as CfgItem;
                if (it != null) ShowConfigFile(it.Path);
            };
            lstCfgFiles.DoubleClick += delegate { RenameConfigFile(); };
            left.Controls.Add(lstCfgFiles, 0, 1);

            FlowLayoutPanel lb = new FlowLayoutPanel();
            lb.Dock = DockStyle.Fill;
            lb.BackColor = Color.Transparent;
            lb.WrapContents = false;
            lb.Padding = new Padding(0, 6, 0, 0);
            left.Controls.Add(lb, 0, 2);

            NeonButton addBtn = MakeButton("添加", false);
            addBtn.Width = 62;
            addBtn.Height = 28;
            addBtn.Margin = new Padding(0, 0, 6, 0);
            NeonButton delBtn = MakeButton("移除", false);
            delBtn.Width = 62;
            delBtn.Height = 28;
            delBtn.Margin = new Padding(0, 0, 6, 0);
            NeonButton renameBtn = MakeButton("改名", false);
            renameBtn.Width = 62;
            renameBtn.Height = 28;
            renameBtn.Margin = new Padding(0, 0, 6, 0);
            NeonButton defBtn = MakeButton("设为默认", false);
            defBtn.Width = 92;
            defBtn.Height = 28;
            lb.Controls.Add(addBtn);
            lb.Controls.Add(delBtn);
            lb.Controls.Add(renameBtn);
            lb.Controls.Add(defBtn);
            addBtn.Click += delegate { AddConfigFile(); };
            delBtn.Click += delegate { RemoveConfigFile(); };
            renameBtn.Click += delegate { RenameConfigFile(); };
            defBtn.Click += delegate { SetDefaultConfigFile(); };

            FlowLayoutPanel addBar = new FlowLayoutPanel();
            addBar.Dock = DockStyle.Fill;
            addBar.BackColor = Color.Transparent;
            addBar.WrapContents = false;
            addBar.Padding = new Padding(0, 4, 0, 0);
            left.Controls.Add(addBar, 0, 3);

            txtCfgNew = new TextBox();
            Theme.StyleInput(txtCfgNew);
            txtCfgNew.Width = 170;
            txtCfgNew.Font = Theme.Small;
            txtCfgNew.Margin = new Padding(0, 0, 6, 0);
            addBar.Controls.Add(txtCfgNew);

            NeonButton addPath = MakeButton("添加路径", false);
            addPath.Width = 96;
            addPath.Height = 28;
            addBar.Controls.Add(addPath);
            addPath.Click += delegate { AddConfigPath(); };
            txtCfgNew.KeyDown += delegate(object s, KeyEventArgs e)
            {
                if (e.KeyCode == Keys.Enter) { e.SuppressKeyPress = true; AddConfigPath(); }
            };
            ToolTip tip = new ToolTip();
            tip.SetToolTip(txtCfgNew, "输入相对路径后回车，文件不存在会自动创建");

            Panel rightHost = new Panel();
            rightHost.Dock = DockStyle.Fill;
            rightHost.Margin = new Padding(10, 0, 0, 0);
            rightHost.BackColor = Color.Transparent;
            main.Controls.Add(rightHost, 1, 0);

            TableLayoutPanel rt = new TableLayoutPanel();
            rt.Dock = DockStyle.Fill;
            rt.ColumnCount = 1;
            rt.RowCount = 3;
            rt.BackColor = Color.Transparent;
            rt.RowStyles.Add(new RowStyle(SizeType.Absolute, 34));
            rt.RowStyles.Add(new RowStyle(SizeType.Absolute, 36));
            rt.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            rightHost.Controls.Add(rt);

            FlowLayoutPanel srcBar = new FlowLayoutPanel();
            srcBar.Dock = DockStyle.Fill;
            srcBar.BackColor = Color.Transparent;
            srcBar.WrapContents = false;
            srcBar.Padding = new Padding(0, 4, 0, 0);
            rt.Controls.Add(srcBar, 0, 0);

            Label srcCap = new Label();
            srcCap.Text = "Nacos 配置";
            srcCap.AutoSize = true;
            srcCap.Font = Theme.Small;
            srcCap.ForeColor = Theme.Muted;
            srcCap.Margin = new Padding(0, 5, 6, 0);
            srcBar.Controls.Add(srcCap);

            btnNacosPick = MakeButton("Nacos: 未读取  ▾", false);
            btnNacosPick.Font = Theme.Small;
            btnNacosPick.Width = 236;
            btnNacosPick.Height = 26;
            btnNacosPick.Margin = new Padding(0, 0, 6, 0);
            srcBar.Controls.Add(btnNacosPick);
            btnNacosPick.Click += delegate { ShowNacosMenu(); };

            NeonButton readN = MakeButton("读取", false);
            readN.Width = 64;
            readN.Height = 26;
            readN.Margin = new Padding(0, 0, 0, 0);
            srcBar.Controls.Add(readN);
            readN.Click += delegate { ReadNacos(); };

            FlowLayoutPanel ymlTools = new FlowLayoutPanel();
            ymlTools.Dock = DockStyle.Fill;
            ymlTools.BackColor = Color.Transparent;
            ymlTools.WrapContents = false;
            ymlTools.Padding = new Padding(0, 4, 0, 0);
            rt.Controls.Add(ymlTools, 0, 1);

            NeonButton addProp = MakeButton("新增属性", false);
            addProp.Width = 96;
            addProp.Height = 28;
            addProp.Margin = new Padding(0, 0, 6, 0);
            NeonButton delProp = MakeButton("删除属性", false);
            delProp.Width = 96;
            delProp.Height = 28;
            delProp.Margin = new Padding(0, 0, 10, 0);
            NeonButton push = MakeButton("保存到 Nacos", true);
            push.Width = 140;
            push.Height = 28;
            push.Margin = new Padding(0, 0, 6, 0);
            ymlTools.Controls.Add(addProp);
            ymlTools.Controls.Add(delProp);
            ymlTools.Controls.Add(push);
            addProp.Click += delegate { AddYmlProperty(); };
            delProp.Click += delegate { DeleteYmlProperty(); };
            push.Click += delegate { SaveYmlToNacos(); };

            Panel right = new Panel();
            right.Dock = DockStyle.Fill;
            right.BackColor = Theme.Border;
            right.Padding = new Padding(1);
            rt.Controls.Add(right, 0, 2);

            dgvYml = new DataGridView();
            dgvYml.Dock = DockStyle.Fill;
            dgvYml.AllowUserToAddRows = false;
            dgvYml.AllowUserToDeleteRows = false;
            dgvYml.SelectionMode = DataGridViewSelectionMode.FullRowSelect;
            dgvYml.RowHeadersWidth = 30;
            Theme.StyleGrid(dgvYml);
            dgvYml.AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.None;
            AddTextCol(dgvYml, "line", "行", 60, true);
            AddTextCol(dgvYml, "key", "属性", 200, false);
            AddTextCol(dgvYml, "value", "值", 240, false);
            dgvYml.Columns["line"].AutoSizeMode = DataGridViewAutoSizeColumnMode.None;
            dgvYml.Columns["key"].AutoSizeMode = DataGridViewAutoSizeColumnMode.None;
            dgvYml.Columns["value"].AutoSizeMode = DataGridViewAutoSizeColumnMode.None;
            dgvYml.Columns["line"].DefaultCellStyle.Font = Theme.Mono;
            dgvYml.Columns["key"].DefaultCellStyle.Font = Theme.Mono;
            dgvYml.Columns["value"].DefaultCellStyle.Font = Theme.Mono;
            dgvYml.Columns["key"].DefaultCellStyle.Padding = new Padding(0, 0, 8, 0);
            dgvYml.Columns["value"].DefaultCellStyle.Padding = new Padding(8, 0, 0, 0);
            dgvYml.RowsDefaultCellStyle.Font = Theme.Mono;
            dgvYml.Resize += delegate { LayoutYml(); };
            dgvYml.CellValueChanged += delegate { if (!loadingYml) ymlDirty = true; };
            right.Controls.Add(dgvYml);

            txtCfgFile = new RichTextBox();
            txtCfgFile.Dock = DockStyle.Fill;
            txtCfgFile.Visible = false;
            Theme.StyleLog(txtCfgFile);
            txtCfgFile.ReadOnly = false;
            txtCfgFile.WordWrap = false;
            txtCfgFile.ScrollBars = RichTextBoxScrollBars.Both;
            txtCfgFile.Font = new Font("Consolas", 10f);
            txtCfgFile.TextChanged += delegate { if (!loadingYml) ymlDirty = true; };
            right.Controls.Add(txtCfgFile);

            Panel bar = new Panel();
            bar.Dock = DockStyle.Fill;
            bar.BackColor = Color.Transparent;
            bt.Controls.Add(bar, 0, 1);

            NeonButton scan = MakeButton("重新扫描", false);
            scan.SetBounds(0, 8, 110, 32);
            NeonButton save = MakeButton("保存修改", true);
            save.SetBounds(120, 8, 110, 32);
            NeonButton open = MakeButton("记事本打开", false);
            open.SetBounds(240, 8, 120, 32);
            bar.Controls.Add(scan);
            bar.Controls.Add(save);
            bar.Controls.Add(open);

            lblCfgPath = new Label();
            lblCfgPath.AutoSize = false;
            lblCfgPath.SetBounds(372, 14, 380, 22);
            lblCfgPath.Font = Theme.Small;
            lblCfgPath.ForeColor = Theme.Muted;
            lblCfgPath.AutoEllipsis = true;
            lblCfgPath.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
            bar.Controls.Add(lblCfgPath);

            scan.Click += delegate
            {
                if (ConfirmDiscardYml()) ShowConfigFile(currentCfgRel);
            };
            save.Click += delegate { SaveYml(); };
            open.Click += delegate
            {
                if (currentCfgRel.Length == 0) return;
                string f = Path.IsPathRooted(currentCfgRel) ? currentCfgRel : Path.Combine(workDir, currentCfgRel);
                if (File.Exists(f)) Process.Start("notepad.exe", "\"" + f + "\"");
            };
        }

        private void LoadConfigList()
        {
            if (lstCfgFiles == null) return;
            cfgItems = ConfigList.LoadItems(workDir);
            if (txtCfgName != null) txtCfgName.Text = ConfigList.LoadName(workDir);
            RefreshCfgList(cfgItems.Count > 0 ? cfgItems[0].Path : "");
        }

        private void RefreshCfgList(string selectPath)
        {
            loadingCfgList = true;
            lstCfgFiles.Items.Clear();
            foreach (CfgItem it in cfgItems) lstCfgFiles.Items.Add(it);
            loadingCfgList = false;
            if (lstCfgFiles.Items.Count == 0)
            {
                currentCfgRel = "";
                dgvYml.Rows.Clear();
                if (lblCfgPath != null) lblCfgPath.Text = "清单为空，请添加";
                return;
            }
            int idx = IndexOfCfgPath(selectPath);
            if (idx < 0) idx = 0;
            lstCfgFiles.SelectedIndex = idx;
        }

        private int IndexOfCfgPath(string path)
        {
            for (int i = 0; i < cfgItems.Count; i++)
                if (string.Equals(cfgItems[i].Path, path, StringComparison.OrdinalIgnoreCase)) return i;
            return -1;
        }

        private CfgItem FindCfgItem(string path)
        {
            int i = IndexOfCfgPath(path);
            return i < 0 ? null : cfgItems[i];
        }

        // 未保存的单元格/文本修改会被“切换文件”“重新扫描”“读取 Nacos”直接冲掉，先确认
        private bool ConfirmDiscardYml()
        {
            if (!ymlDirty) return true;
            return MessageBox.Show("当前配置有未保存的修改，继续将放弃这些修改。\r\n确定继续？", "未保存的修改",
                MessageBoxButtons.YesNo, MessageBoxIcon.Warning) == DialogResult.Yes;
        }

        private void ShowConfigFile(string rel)
        {
            currentCfgRel = rel == null ? "" : rel;
            loadingYml = true;
            ymlDirty = false;
            dgvYml.Rows.Clear();
            deletedYmlRows.Clear();
            if (lblCfgPath != null)
                lblCfgPath.Text = currentCfgRel.Length == 0
                    ? "未选择配置文件"
                    : (Path.IsPathRooted(currentCfgRel) ? currentCfgRel : Path.Combine(workDir, currentCfgRel));
            if (currentCfgRel.Length == 0)
            {
                dgvYml.Visible = true;
                txtCfgFile.Visible = false;
                loadingYml = false;
                return;
            }
            string f = Path.IsPathRooted(currentCfgRel) ? currentCfgRel : Path.Combine(workDir, currentCfgRel);
            string ext = Path.GetExtension(f).ToLowerInvariant();
            bool tableMode = (ext == ".yml" || ext == ".yaml" || ext == ".properties");
            dgvYml.Visible = tableMode;
            txtCfgFile.Visible = !tableMode;
            if (!File.Exists(f))
            {
                if (!tableMode) txtCfgFile.Text = "";
                loadingYml = false;
                return;
            }
            if (!tableMode)
            {
                try { txtCfgFile.Text = File.ReadAllText(f); }
                catch { txtCfgFile.Text = ""; }
                loadingYml = false;
                return;
            }
            List<YmlRow> rows = YmlEditor.ScanFile(workDir, currentCfgRel);
            foreach (YmlRow r in rows)
            {
                string lineText = r.IsNew ? "新增" : (r.LineIndex + 1).ToString();
                int i = dgvYml.Rows.Add(lineText, r.Key, r.Value);
                dgvYml.Rows[i].Tag = r;
                UseMono(dgvYml.Rows[i]);
            }
            LayoutYml();
            loadingYml = false;
        }

        private void ShowNacosConfig(NacosCfg c)
        {
            if (c == null) return;
            currentNacos = c;
            currentCfgRel = "";
            loadingYml = true;
            ymlDirty = false;
            deletedYmlRows.Clear();
            dgvYml.Rows.Clear();
            if (txtCfgFile != null) txtCfgFile.Visible = false;
            dgvYml.Visible = true;
            string tag = c.DataId;
            if (c.Type == "properties" && !tag.ToLowerInvariant().EndsWith(".properties"))
                tag += ".properties";
            List<YmlRow> rows = YmlEditor.ScanText(c.Content, tag);
            foreach (YmlRow r in rows)
            {
                string lineText = (r.LineIndex + 1).ToString();
                int i = dgvYml.Rows.Add(lineText, r.Key, r.Value);
                dgvYml.Rows[i].Tag = r;
                UseMono(dgvYml.Rows[i]);
            }
            if (lblCfgPath != null)
                lblCfgPath.Text = "NACOS  ·  " + c.DataId + "   Group=" + c.Group
                    + "   命名空间=" + (c.Tenant.Length == 0 ? "public" : c.Tenant);
            LayoutYml();
            loadingYml = false;
        }

        private void LayoutYml()
        {
            if (dgvYml == null || dgvYml.Columns.Count < 3) return;
            int avail = dgvYml.ClientSize.Width - dgvYml.RowHeadersWidth
                - SystemInformation.VerticalScrollBarWidth - 4;
            if (avail < 300) avail = 300;
            int lineW = 56;
            int keyW = avail - lineW - 90;
            if (keyW > 200) keyW = 200;
            if (keyW < 120) keyW = 120;
            int valW = avail - lineW - keyW;
            if (valW < 90) valW = 90;
            dgvYml.Columns["line"].Width = lineW;
            dgvYml.Columns["key"].Width = keyW;
            dgvYml.Columns["value"].Width = valW;
        }

        private static void UseMono(DataGridViewRow row)
        {
            row.Cells["line"].Style.Font = Theme.Mono;
            row.Cells["key"].Style.Font = Theme.Mono;
            row.Cells["value"].Style.Font = Theme.Mono;
        }

        private void AddYmlProperty()
        {
            if (!dgvYml.Visible || (currentCfgRel.Length == 0 && currentNacos == null))
            {
                MessageBox.Show("请先在左侧选择本地文件，或读取 Nacos 配置");
                return;
            }
            string f = currentNacos != null
                ? currentNacos.DataId
                : (Path.IsPathRooted(currentCfgRel) ? currentCfgRel : Path.Combine(workDir, currentCfgRel));
            string ext = currentNacos != null
                ? (currentNacos.Type == "properties" ? ".properties" : ".yaml")
                : Path.GetExtension(f).ToLowerInvariant();
            YmlRow r = new YmlRow();
            r.FilePath = f;
            r.RelPath = currentNacos != null ? currentNacos.DataId : currentCfgRel;
            r.LineIndex = -1;
            r.IsNew = true;
            r.Separator = ext == ".properties" ? "=" : ":";
            int i = dgvYml.Rows.Add("新增", "", "");
            dgvYml.Rows[i].Tag = r;
            UseMono(dgvYml.Rows[i]);
            dgvYml.CurrentCell = dgvYml.Rows[i].Cells["key"];
            dgvYml.BeginEdit(true);
            ymlDirty = true;
        }

        private void DeleteYmlProperty()
        {
            if (!dgvYml.Visible || (currentCfgRel.Length == 0 && currentNacos == null))
            {
                MessageBox.Show("请先在左侧选择本地文件，或读取 Nacos 配置");
                return;
            }
            if (dgvYml.SelectedRows.Count == 0)
            {
                MessageBox.Show("请先选中要删除的属性行");
                return;
            }
            List<DataGridViewRow> sel = new List<DataGridViewRow>();
            foreach (DataGridViewRow row in dgvYml.SelectedRows) sel.Add(row);
            if (MessageBox.Show("删除选中的 " + sel.Count + " 个属性？\r\n保存后才会从配置中移除对应行", "确认",
                MessageBoxButtons.YesNo) != DialogResult.Yes) return;
            foreach (DataGridViewRow row in sel)
            {
                YmlRow r = row.Tag as YmlRow;
                if (r != null && !r.IsNew)
                {
                    r.IsDeleted = true;
                    deletedYmlRows.Add(r);
                }
                dgvYml.Rows.Remove(row);
            }
            ymlDirty = true;
        }

        private void AddConfigPath()
        {
            string raw = txtCfgNew.Text.Trim().Trim('"');
            if (raw.Length == 0) { MessageBox.Show("请输入配置文件路径，或“名称|路径”"); return; }
            string itemName = "";
            string rel = raw;
            int bar = raw.IndexOf('|');
            if (bar > 0)
            {
                itemName = raw.Substring(0, bar).Trim();
                rel = raw.Substring(bar + 1).Trim();
            }
            if (rel.Length == 0) { MessageBox.Show("路径不能为空"); return; }
            if (rel.StartsWith(workDir + "\\", StringComparison.OrdinalIgnoreCase))
                rel = rel.Substring(workDir.Length + 1);
            string full = Path.IsPathRooted(rel) ? rel : Path.Combine(workDir, rel);
            try
            {
                if (!File.Exists(full))
                {
                    Directory.CreateDirectory(Path.GetDirectoryName(full));
                    File.WriteAllText(full, "", new UTF8Encoding(false));
                }
            }
            catch (Exception ex)
            {
                MessageBox.Show("创建文件失败: " + ex.Message);
                return;
            }
            CfgItem exist = FindCfgItem(rel);
            if (exist != null)
            {
                if (itemName.Length > 0) exist.Name = itemName;
            }
            else
            {
                CfgItem it = new CfgItem();
                it.Name = itemName;
                it.Path = rel;
                cfgItems.Add(it);
            }
            ConfigList.SaveItems(workDir, txtCfgName.Text.Trim(), cfgItems);
            txtCfgNew.Text = "";
            RefreshCfgList(rel);
        }

        private void AddConfigFile()
        {
            using (OpenFileDialog d = new OpenFileDialog())
            {
                d.Filter = "配置文件|*.yml;*.yaml;*.properties;*.conf;*.js;*.json;*.ini;*.xml;*.txt|所有文件|*.*";
                string conf = PathHelper.ConfDir(workDir);
                if (Directory.Exists(conf)) d.InitialDirectory = conf;
                d.Multiselect = true;
                if (d.ShowDialog() != DialogResult.OK) return;
                string last = "";
                foreach (string f in d.FileNames)
                {
                    string rel = f;
                    if (f.StartsWith(workDir + "\\", StringComparison.OrdinalIgnoreCase))
                        rel = f.Substring(workDir.Length + 1);
                    if (FindCfgItem(rel) == null)
                    {
                        CfgItem it = new CfgItem();
                        it.Path = rel;
                        cfgItems.Add(it);
                    }
                    last = rel;
                }
                ConfigList.SaveItems(workDir, txtCfgName.Text.Trim(), cfgItems);
                RefreshCfgList(last);
            }
        }

        private void RemoveConfigFile()
        {
            CfgItem it = lstCfgFiles.SelectedItem as CfgItem;
            if (it == null) return;
            string label = it.Name.Length > 0 ? it.Name + "  (" + it.Path + ")" : it.Path;
            if (MessageBox.Show("从清单移除 " + label + "？\r\n（只移除列表项，不删除文件）", "确认",
                MessageBoxButtons.YesNo) != DialogResult.Yes) return;
            cfgItems.Remove(it);
            ConfigList.SaveItems(workDir, txtCfgName.Text.Trim(), cfgItems);
            RefreshCfgList(cfgItems.Count > 0 ? cfgItems[0].Path : "");
        }

        private void SetDefaultConfigFile()
        {
            int i = lstCfgFiles.SelectedIndex;
            if (i <= 0) { MessageBox.Show("请先选中一个非首行的配置项"); return; }
            CfgItem it = cfgItems[i];
            cfgItems.RemoveAt(i);
            cfgItems.Insert(0, it);
            ConfigList.SaveItems(workDir, txtCfgName.Text.Trim(), cfgItems);
            RefreshCfgList(it.Path);
        }

        private void RenameConfigFile()
        {
            CfgItem it = lstCfgFiles.SelectedItem as CfgItem;
            if (it == null) { MessageBox.Show("请先选中一个配置项"); return; }
            string n = PromptText("重命名配置项", "显示名称（留空则显示路径）", it.Name);
            if (n == null) return;
            n = n.Trim();
            if (n.IndexOf('|') >= 0)
            {
                MessageBox.Show("配置项名称不能包含 | 字符（会破坏 config-files.cfg 的“名称|路径”格式）");
                return;
            }
            it.Name = n;
            ConfigList.SaveItems(workDir, txtCfgName.Text.Trim(), cfgItems);
            RefreshCfgList(it.Path);
        }

        private static string PromptText(string title, string caption, string value)
        {
            using (Form dlg = new Form())
            {
                dlg.Text = title;
                dlg.FormBorderStyle = FormBorderStyle.FixedDialog;
                dlg.StartPosition = FormStartPosition.CenterParent;
                dlg.MaximizeBox = false;
                dlg.MinimizeBox = false;
                dlg.BackColor = Theme.Bg;
                dlg.ClientSize = new Size(360, 132);

                Label lbl = new Label();
                lbl.Text = caption;
                lbl.ForeColor = Theme.Text;
                lbl.SetBounds(16, 14, 330, 20);
                dlg.Controls.Add(lbl);

                TextBox box = new TextBox();
                Theme.StyleInput(box);
                box.Text = value;
                box.SetBounds(16, 40, 328, 24);
                dlg.Controls.Add(box);

                NeonButton ok = MakeButton("确定", true);
                ok.SetBounds(240, 84, 104, 32);
                NeonButton cancel = MakeButton("取消", false);
                cancel.SetBounds(128, 84, 104, 32);
                dlg.Controls.Add(ok);
                dlg.Controls.Add(cancel);
                ok.Click += delegate { dlg.DialogResult = DialogResult.OK; };
                cancel.Click += delegate { dlg.DialogResult = DialogResult.Cancel; };
                dlg.AcceptButton = ok;
                dlg.CancelButton = cancel;
                dlg.ShowDialog();
                return dlg.DialogResult == DialogResult.OK ? box.Text : null;
            }
        }

        private void BuildRunPage(Panel body)
        {
            TableLayoutPanel root = new TableLayoutPanel();
            root.Dock = DockStyle.Fill;
            root.ColumnCount = 1;
            root.RowCount = 3;
            root.BackColor = Color.Transparent;
            root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            body.Controls.Add(root);

            root.Controls.Add(BuildSqlInitPanel(), 0, 0);

            FlowLayoutPanel barHost = new FlowLayoutPanel();
            barHost.Dock = DockStyle.Top;
            barHost.AutoSize = true;
            barHost.AutoSizeMode = AutoSizeMode.GrowAndShrink;
            barHost.FlowDirection = FlowDirection.TopDown;
            barHost.WrapContents = false;
            barHost.BackColor = Color.Transparent;
            root.Controls.Add(barHost, 0, 1);

            FlowLayoutPanel bar = new FlowLayoutPanel();
            bar.AutoSize = true;
            bar.AutoSizeMode = AutoSizeMode.GrowAndShrink;
            bar.BackColor = Color.Transparent;
            bar.WrapContents = false;
            bar.Margin = new Padding(0);
            barHost.Controls.Add(bar);

            btnInitNow = MakeBarButton(bar, "初始化数据目录", false);
            btnStart = MakeBarButton(bar, "启动全部", true);
            btnStop = MakeBarButton(bar, "停止全部", false);
            btnStatus = MakeBarButton(bar, "查看状态", false);
            btnInitNow.Width = 160;
            foreach (Control c in bar.Controls)
                if (c is Button) FitButton((Button)c);

            FlowLayoutPanel barCfg = new FlowLayoutPanel();
            barCfg.AutoSize = true;
            barCfg.AutoSizeMode = AutoSizeMode.GrowAndShrink;
            barCfg.BackColor = Color.Transparent;
            barCfg.WrapContents = false;
            barCfg.Margin = new Padding(0, 4, 0, 0);
            barHost.Controls.Add(barCfg);

            Button btnRead = MakeBarButton(barCfg, "读取 Nacos", false);
            btnImport = MakeBarButton(barCfg, "写入 Nacos", false);
            btnRead.Width = 136;
            btnImport.Width = 136;
            FitButton(btnRead);
            FitButton(btnImport);

            btnInitNow.Click += delegate { RunScripts(new string[] { @"bin\0-init.bat" }); };
            btnStart.Click += delegate { RunScripts(new string[] { @"bin\2-start-infra.bat", @"bin\3-start-apps.bat" }); };
            btnStop.Click += delegate { RunScripts(new string[] { @"bin\9-stop-all.bat" }); };
            btnStatus.Click += delegate { RunScripts(new string[] { @"bin\4-status.bat" }); };
            btnRead.Click += delegate { ReadNacos(); };
            btnImport.Click += delegate
            {
                if (MessageBox.Show("将把 conf\\nacos 中的配置写入 Nacos，覆盖同名 dataId，继续？",
                    "确认", MessageBoxButtons.YesNo) != DialogResult.Yes) return;
                RunScripts(new string[] { @"bin\5-import-config.bat" });
            };

            Panel logWrap = new Panel();
            logWrap.Dock = DockStyle.Fill;
            logWrap.BackColor = Theme.Border;
            logWrap.Padding = new Padding(1);
            logWrap.Margin = new Padding(0, 4, 0, 0);
            root.Controls.Add(logWrap, 0, 2);

            txtRunLog = new RichTextBox();
            txtRunLog.Dock = DockStyle.Fill;
            txtRunLog.ReadOnly = true;
            Theme.StyleLog(txtRunLog);
            logWrap.Controls.Add(txtRunLog);
        }

        // 初始化脚本选择区：勾选后按列表顺序执行
        private Panel BuildSqlInitPanel()
        {
            Panel wrap = new Panel();
            wrap.Dock = DockStyle.Top;
            wrap.AutoSize = true;
            wrap.AutoSizeMode = AutoSizeMode.GrowAndShrink;
            wrap.BackColor = Color.Transparent;

            TableLayoutPanel t = new TableLayoutPanel();
            t.Dock = DockStyle.Top;
            t.AutoSize = true;
            t.AutoSizeMode = AutoSizeMode.GrowAndShrink;
            t.ColumnCount = 1;
            t.RowCount = 5;
            t.BackColor = Color.Transparent;
            t.RowStyles.Add(new RowStyle(SizeType.Absolute, Theme.Small.Height + 10));
            t.RowStyles.Add(new RowStyle(SizeType.Absolute, Theme.Small.Height * 4 + 16));
            t.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            t.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            t.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            wrap.Controls.Add(t);

            Label hint = new Label();
            hint.Text = "默认读取 conf\\sql；.sql 导入所选数据库，.bat/.cmd 作为数据导入脚本。";
            hint.Font = Theme.Small;
            hint.ForeColor = Theme.Muted;
            hint.AutoSize = false;
            hint.AutoEllipsis = true;
            hint.Dock = DockStyle.Fill;
            t.Controls.Add(hint, 0, 0);

            Panel listWrap = new Panel();
            listWrap.Dock = DockStyle.Fill;
            listWrap.BackColor = Theme.Border;
            listWrap.Padding = new Padding(1);
            listWrap.Margin = new Padding(0, 0, 0, 4);
            t.Controls.Add(listWrap, 0, 1);

            lstSqlScripts = new CheckedListBox();
            lstSqlScripts.Dock = DockStyle.Fill;
            lstSqlScripts.BackColor = Theme.Bg2;
            lstSqlScripts.ForeColor = Theme.Text;
            lstSqlScripts.BorderStyle = BorderStyle.None;
            lstSqlScripts.Font = Theme.Small;
            lstSqlScripts.CheckOnClick = true;
            lstSqlScripts.IntegralHeight = false;
            lstSqlScripts.HorizontalScrollbar = true;
            listWrap.Controls.Add(lstSqlScripts);

            lblSqlEmpty = new Label();
            lblSqlEmpty.Dock = DockStyle.Fill;
            lblSqlEmpty.BackColor = Theme.Bg2;
            lblSqlEmpty.ForeColor = Theme.Muted;
            lblSqlEmpty.Font = Theme.Small;
            lblSqlEmpty.TextAlign = ContentAlignment.MiddleLeft;
            lblSqlEmpty.Padding = new Padding(10, 0, 0, 0);
            lblSqlEmpty.Text = "未找到默认脚本。点击「选择脚本」添加 .sql 初始化脚本或 .bat/.cmd 数据导入脚本";
            listWrap.Controls.Add(lblSqlEmpty);
            lblSqlEmpty.BringToFront();

            FlowLayoutPanel bar1 = new FlowLayoutPanel();
            bar1.Dock = DockStyle.Top;
            bar1.AutoSize = true;
            bar1.AutoSizeMode = AutoSizeMode.GrowAndShrink;
            bar1.BackColor = Color.Transparent;
            bar1.WrapContents = true;
            t.Controls.Add(bar1, 0, 2);

            NeonButton addScript = MakeButton("选择脚本", false);
            addScript.Width = 96;
            addScript.Height = 26;
            addScript.Margin = new Padding(0, 4, 8, 0);
            bar1.Controls.Add(addScript);

            NeonButton delScript = MakeButton("移除选中", false);
            delScript.Width = 96;
            delScript.Height = 26;
            delScript.Margin = new Padding(0, 4, 8, 0);
            bar1.Controls.Add(delScript);

            NeonButton defScript = MakeButton("默认脚本", false);
            defScript.Width = 96;
            defScript.Height = 26;
            defScript.Margin = new Padding(0, 4, 12, 0);
            bar1.Controls.Add(defScript);

            btnSqlInit = MakeButton("执行 SQL 初始化", true);
            btnSqlInit.Width = 190;
            btnSqlInit.Height = 26;
            btnSqlInit.Margin = new Padding(0, 4, 0, 0);
            bar1.Controls.Add(btnSqlInit);
            FitButton(addScript);
            FitButton(delScript);
            FitButton(defScript);
            FitButton(btnSqlInit);

            FlowLayoutPanel bar2 = new FlowLayoutPanel();
            bar2.Dock = DockStyle.Top;
            bar2.AutoSize = true;
            bar2.AutoSizeMode = AutoSizeMode.GrowAndShrink;
            bar2.BackColor = Color.Transparent;
            bar2.WrapContents = true;
            t.Controls.Add(bar2, 0, 3);

            Label lblTarget = new Label();
            lblTarget.Text = "目标数据库";
            lblTarget.AutoSize = true;
            lblTarget.Font = Theme.Small;
            lblTarget.ForeColor = Theme.Muted;
            lblTarget.Margin = new Padding(0, 6, 6, 0);
            bar2.Controls.Add(lblTarget);

            cmbSqlTarget = new ComboBox();
            cmbSqlTarget.DropDownStyle = ComboBoxStyle.DropDownList;
            cmbSqlTarget.Width = 160;
            cmbSqlTarget.FlatStyle = FlatStyle.Flat;
            cmbSqlTarget.BackColor = Theme.Card;
            cmbSqlTarget.ForeColor = Theme.Text;
            cmbSqlTarget.Font = Theme.Small;
            cmbSqlTarget.Margin = new Padding(0, 3, 14, 0);
            cmbSqlTarget.Items.Add("MySQL");
            cmbSqlTarget.Items.Add("PostgreSQL");
            cmbSqlTarget.Items.Add("MySQL + PostgreSQL");
            cmbSqlTarget.SelectedIndex = 0;
            cmbSqlTarget.Width = Math.Max(160,
                TextRenderer.MeasureText("MySQL + PostgreSQL", cmbSqlTarget.Font).Width + 40);
            bar2.Controls.Add(cmbSqlTarget);

            Label lblDb = new Label();
            lblDb.Text = "数据库名（可选）";
            lblDb.AutoSize = true;
            lblDb.Font = Theme.Small;
            lblDb.ForeColor = Theme.Muted;
            lblDb.Margin = new Padding(0, 6, 6, 0);
            bar2.Controls.Add(lblDb);

            txtSqlDb = new TextBox();
            Theme.StyleInput(txtSqlDb);
            txtSqlDb.Width = 150;
            txtSqlDb.Font = Theme.Small;
            txtSqlDb.Margin = new Padding(0, 2, 14, 0);
            bar2.Controls.Add(txtSqlDb);

            Label lblMinio = new Label();
            lblMinio.Text = "MinIO 存储目录：" + MinioDataValue();
            lblMinio.AutoSize = true;
            lblMinio.Font = Theme.Small;
            lblMinio.ForeColor = Theme.Muted;

            FlowLayoutPanel bar3 = new FlowLayoutPanel();
            bar3.Dock = DockStyle.Top;
            bar3.AutoSize = true;
            bar3.AutoSizeMode = AutoSizeMode.GrowAndShrink;
            bar3.BackColor = Color.Transparent;
            bar3.WrapContents = true;
            t.Controls.Add(bar3, 0, 4);
            lblMinio.Margin = new Padding(0, 2, 0, 0);
            lblMinio.VisibleChanged += delegate
            {
                if (lblMinio.Visible) lblMinio.Text = "MinIO 存储目录：" + MinioDataValue();
            };
            bar3.Controls.Add(lblMinio);

            addScript.Click += delegate { AddSqlScripts(); };
            delScript.Click += delegate { RemoveSqlScripts(); };
            defScript.Click += delegate { RefreshSqlScripts(); };
            btnSqlInit.Click += delegate { RunSqlInit(); };

            RefreshSqlScripts();
            return wrap;
        }

        // 默认脚本目录：conf\sql、sql、data\sql
        private List<string> FindDefaultSqlScripts()
        {
            List<string> result = new List<string>();
            string[] dirs = new string[]
            {
                Path.Combine(workDir, "conf", "sql"),
                Path.Combine(workDir, "sql"),
                Path.Combine(workDir, "data", "sql")
            };
            foreach (string d in dirs)
            {
                if (!Directory.Exists(d)) continue;
                string[] files = Directory.GetFiles(d, "*.*", SearchOption.AllDirectories);
                Array.Sort(files, StringComparer.OrdinalIgnoreCase);
                foreach (string f in files)
                {
                    string ext = Path.GetExtension(f).ToLowerInvariant();
                    if (ext != ".sql" && ext != ".bat" && ext != ".cmd") continue;
                    if (!result.Contains(f)) result.Add(f);
                }
            }
            return result;
        }

        private void RefreshSqlScripts()
        {
            if (lstSqlScripts == null) return;
            lstSqlScripts.Items.Clear();
            foreach (string f in FindDefaultSqlScripts())
                AddSqlScriptItem(f);
            UpdateSqlEmptyState();
        }

        private void UpdateSqlEmptyState()
        {
            if (lblSqlEmpty == null || lstSqlScripts == null) return;
            lblSqlEmpty.Visible = lstSqlScripts.Items.Count == 0;
            if (lblSqlEmpty.Visible) lblSqlEmpty.BringToFront();
        }

        private void AddSqlScriptItem(string f)
        {
            ScriptItem it = new ScriptItem();
            it.Path = f;
            it.Display = f;
            string root = workDir.TrimEnd('\\') + "\\";
            if (f.StartsWith(root, StringComparison.OrdinalIgnoreCase))
                it.Display = f.Substring(root.Length);
            lstSqlScripts.Items.Add(it, true);
        }

        private bool HasSqlScript(string f)
        {
            foreach (object o in lstSqlScripts.Items)
            {
                ScriptItem it = o as ScriptItem;
                if (it != null && string.Equals(it.Path, f, StringComparison.OrdinalIgnoreCase))
                    return true;
            }
            return false;
        }

        private void AddSqlScripts()
        {
            OpenFileDialog dlg = new OpenFileDialog();
            dlg.Title = "选择初始化 / 数据导入脚本";
            dlg.Multiselect = true;
            dlg.Filter = "SQL / 脚本|*.sql;*.bat;*.cmd|SQL 文件|*.sql|批处理脚本|*.bat;*.cmd|所有文件|*.*";
            if (dlg.ShowDialog(this) != DialogResult.OK) return;
            foreach (string f in dlg.FileNames)
            {
                if (HasSqlScript(f)) continue;
                AddSqlScriptItem(f);
            }
            UpdateSqlEmptyState();
        }

        private void RemoveSqlScripts()
        {
            if (lstSqlScripts == null) return;
            for (int i = lstSqlScripts.Items.Count - 1; i >= 0; i--)
                if (lstSqlScripts.GetItemChecked(i)) lstSqlScripts.Items.RemoveAt(i);
            UpdateSqlEmptyState();
        }

        private static void FitButton(Button b)
        {
            int tw = TextRenderer.MeasureText(b.Text, b.Font).Width;
            b.Width = Math.Max(b.Width, tw + 30);
            b.Height = Math.Max(b.Height, b.Font.Height + 14);
        }

        private string MinioDataRaw()
        {
            return DeployConfig.Load(workDir).Get("MINIO_DATA_DIR").Trim().Trim('"').Trim();
        }

        private string MinioDataValue()
        {
            string v = MinioDataRaw();
            return v.Length == 0 ? @"data\minio" : v;
        }

        private string MinioDataPath()
        {
            string v = MinioDataRaw();
            if (v.Length == 0) return Path.Combine(workDir, "data", "minio");
            return Path.IsPathRooted(v) ? v : Path.Combine(workDir, v);
        }

        private void RunSqlInit()
        {
            if (running) { MessageBox.Show("有任务正在执行，请稍候"); return; }
            if (lstSqlScripts == null) return;
            List<string> scripts = new List<string>();
            for (int i = 0; i < lstSqlScripts.Items.Count; i++)
            {
                if (!lstSqlScripts.GetItemChecked(i)) continue;
                ScriptItem it = lstSqlScripts.Items[i] as ScriptItem;
                if (it != null) scripts.Add(it.Path);
            }
            if (scripts.Count == 0)
            {
                MessageBox.Show("请先勾选要执行的脚本，可点击「选择脚本」添加");
                return;
            }

            int idx = cmbSqlTarget.SelectedIndex;
            string target = idx == 1 ? "pg" : (idx == 2 ? "all" : "mysql");
            string targetText = idx == 1 ? "PostgreSQL" : (idx == 2 ? "MySQL + PostgreSQL" : "MySQL");
            string db = txtSqlDb.Text.Trim();
            StringBuilder msg = new StringBuilder();
            msg.AppendLine("将按列表顺序执行以下脚本：");
            foreach (string s in scripts) msg.AppendLine("  " + s);
            msg.AppendLine();
            msg.AppendLine("目标数据库：" + targetText + (db.Length > 0 ? "，数据库名：" + db : ""));
            msg.AppendLine("请确认对应数据库已启动，继续？");
            if (MessageBox.Show(msg.ToString(), "确认", MessageBoxButtons.YesNo) != DialogResult.Yes)
                return;

            RunTask("初始化数据", delegate()
            {
                foreach (string s in scripts)
                {
                    RunLog("");
                    RunLog(">>> " + s);
                    int rc = RunProcessArgs(@"bin\6-init-data.bat",
                        target + " \"" + s + "\" \"" + db + "\"", workDir, RunLog);
                    if (rc != 0)
                    {
                        RunLog("脚本执行失败，已停止后续脚本: " + s);
                        return 1;
                    }
                }
                string minio = MinioDataPath();
                try { Directory.CreateDirectory(minio); }
                catch { }
                RunLog("MinIO 存储目录: " + minio);
                return 0;
            }, null);
        }

        private void ServiceAction(string action)
        {
            if (running) { MessageBox.Show("有任务正在执行，请稍候"); return; }
            if (!ConfirmUsingSavedConfig()) return;
            if (dgvApps.SelectedRows.Count == 0)
            {
                MessageBox.Show("请先在服务列表中选中一行或多行");
                return;
            }
            List<string> names = new List<string>();
            List<string> remotes = new List<string>();
            DeployConfig dc = CollectDeploy();
            string selfHost = dc.Get("DEPLOY_HOST");
            if (selfHost.Length == 0) selfHost = "127.0.0.1";
            foreach (DataGridViewRow row in dgvApps.SelectedRows)
            {
                if (row.IsNewRow) continue;
                string n = Cell(row, "name");
                if (n.Length == 0 || names.Contains(n)) continue;
                string host = Cell(row, "host");
                if (!IsLocalHost(host, selfHost))
                {
                    remotes.Add(n + " @ " + host);
                    continue;
                }
                names.Add(n);
            }
            if (names.Count == 0)
            {
                MessageBox.Show(remotes.Count > 0
                    ? "选中的服务都在远程主机，请到对应机器上启动：\r\n" + string.Join("\r\n", remotes.ToArray())
                    : "选中的行没有服务名");
                return;
            }
            if (action == "stop" || action == "restart")
            {
                string tip = action == "stop" ? "确定停止以下服务？" : "确定重启以下服务？";
                if (MessageBox.Show(tip + "\r\n" + string.Join(", ", names.ToArray()),
                    "确认", MessageBoxButtons.YesNo) != DialogResult.Yes) return;
            }
            string title = action == "stop" ? "停止服务" : (action == "restart" ? "重启服务" : "启动服务");
            RunTask(title, delegate()
            {
                if (remotes.Count > 0)
                    RunLog("跳过远程服务: " + string.Join(", ", remotes.ToArray()));
                int failed = 0;
                foreach (string n in names)
                {
                    RunLog("");
                    RunLog(">>> " + action + " " + n);
                    if (RunProcessArgs(@"bin\8-service.bat", action + " " + n, workDir, RunLog) != 0)
                    {
                        failed++;
                        RunLog("失败: " + action + " " + n);
                    }
                }
                return failed == 0 ? 0 : 1;
            }, null);
        }

        private static bool IsLocalHost(string host, string self)
        {
            if (host.Length == 0) return true;
            if (string.Equals(host, self, StringComparison.OrdinalIgnoreCase)) return true;
            bool hLoop = string.Equals(host, "127.0.0.1", StringComparison.OrdinalIgnoreCase)
                || string.Equals(host, "localhost", StringComparison.OrdinalIgnoreCase);
            bool sLoop = string.Equals(self, "127.0.0.1", StringComparison.OrdinalIgnoreCase)
                || string.Equals(self, "localhost", StringComparison.OrdinalIgnoreCase);
            return hLoop && sLoop;
        }

        private void GenerateNodePackages(string host)
        {
            if (running) { MessageBox.Show("有任务正在执行，请稍候"); return; }
            if (host.Length == 0)
            {
                if (MessageBox.Show("未填写节点主机，将按 service-hosts.cfg 中已填写的所有远程主机生成节点包。\r\n"
                    + "输出目录: nodes\\node-<主机>，继续？", "确认", MessageBoxButtons.YesNo) != DialogResult.Yes) return;
            }
            string arg = host.Length == 0 ? "all" : host;
            RunTask("生成节点包", delegate()
            {
                RunLog(">>> 生成节点包: " + (host.Length == 0 ? "所有远程主机" : host));
                int rc = RunProcessArgs(@"bin\make-node.bat", arg, workDir, RunLog);
                RunLog("节点包目录: " + Path.Combine(workDir, "nodes"));
                return rc;
            }, null);
        }

        private void BuildUnitsPage(Panel body)
        {
            TableLayoutPanel bt = new TableLayoutPanel();
            bt.Dock = DockStyle.Fill;
            bt.ColumnCount = 1;
            bt.RowCount = 2;
            bt.BackColor = Color.Transparent;
            bt.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            bt.RowStyles.Add(new RowStyle(SizeType.Absolute, 48));
            body.Controls.Add(bt);

            dgvUnits = new DataGridView();
            dgvUnits.Dock = DockStyle.Fill;
            dgvUnits.AllowUserToAddRows = false;
            dgvUnits.AllowUserToDeleteRows = false;
            dgvUnits.MultiSelect = false;
            dgvUnits.RowHeadersWidth = 30;
            Theme.StyleGrid(dgvUnits);
            AddTextCol(dgvUnits, "name", "组件", 140, true);
            AddTextCol(dgvUnits, "type", "类型", 90, true);
            AddTextCol(dgvUnits, "host", "主机", 110, true);
            AddTextCol(dgvUnits, "port", "端口", 60, true);
            AddTextCol(dgvUnits, "status", "状态", 80, true);
            AddButtonCol(dgvUnits, "start", "启动");
            AddButtonCol(dgvUnits, "stop", "停止");
            AddButtonCol(dgvUnits, "restart", "重启");
            dgvUnits.AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.None;
            foreach (string n in new string[] { "start", "stop", "restart" })
            {
                dgvUnits.Columns[n].AutoSizeMode = DataGridViewAutoSizeColumnMode.None;
                dgvUnits.Columns[n].Width = 68;
            }
            dgvUnits.Resize += delegate { LayoutUnits(); };
            dgvUnits.CellContentClick += delegate(object s, DataGridViewCellEventArgs e)
            {
                OnUnitCellClick(e);
            };
            bt.Controls.Add(dgvUnits, 0, 0);

            Panel bar = new Panel();
            bar.Dock = DockStyle.Fill;
            bar.BackColor = Color.Transparent;
            bt.Controls.Add(bar, 0, 1);

            NeonButton refresh = MakeButton("刷新状态", false);
            refresh.SetBounds(0, 8, 110, 32);
            bar.Controls.Add(refresh);
            refresh.Click += delegate { RefreshUnits(); };

            Label hint = new Label();
            hint.Text = "REMOTE = 组件部署在其他机器，需到该机器操作";
            hint.Font = Theme.Small;
            hint.ForeColor = Theme.Muted;
            hint.AutoSize = true;
            hint.SetBounds(122, 15, 500, 20);
            bar.Controls.Add(hint);
        }

        private void LayoutUnits()
        {
            if (dgvUnits == null || dgvUnits.Columns.Count < 8) return;
            int avail = dgvUnits.ClientSize.Width - dgvUnits.RowHeadersWidth
                - SystemInformation.VerticalScrollBarWidth - 4;
            if (avail < 400) avail = 400;
            int fill = avail - 68 * 3;
            double[] wt = new double[] { 26, 14, 18, 10, 12 };
            string[] cols = new string[] { "name", "type", "host", "port", "status" };
            int[] min = new int[] { 100, 70, 90, 50, 60 };
            int sumWt = 80;
            int used = 0;
            for (int i = 0; i < cols.Length; i++)
            {
                int w = (int)(fill * wt[i] / sumWt);
                if (w < min[i]) w = min[i];
                dgvUnits.Columns[cols[i]].Width = w;
                used += w;
            }
            if (fill > used) dgvUnits.Columns["status"].Width += fill - used;
        }

        private void LayoutApps()
        {
            if (dgvApps == null || dgvApps.Columns.Count < 7) return;
            int avail = dgvApps.ClientSize.Width - dgvApps.RowHeadersWidth
                - SystemInformation.VerticalScrollBarWidth - 4;
            if (avail < 500) avail = 500;
            int fixedW = 100 + 64 + 60 + 100;   // name, port, jdk, host
            int fill = avail - fixedW;
            if (fill < 320) fill = 320;
            int jarW = (int)(fill * 0.36);
            int jvmW = (int)(fill * 0.30);
            int extraW = fill - jarW - jvmW;
            dgvApps.Columns["name"].Width = 100;
            dgvApps.Columns["port"].Width = 64;
            dgvApps.Columns["jdk"].Width = 60;
            dgvApps.Columns["host"].Width = 100;
            dgvApps.Columns["jar"].Width = jarW;
            dgvApps.Columns["jvm"].Width = jvmW;
            dgvApps.Columns["extra"].Width = extraW;
        }

        private static void AddButtonCol(DataGridView g, string name, string text)
        {
            DataGridViewButtonColumn c = new DataGridViewButtonColumn();
            c.Name = name;
            c.HeaderText = "";
            c.Text = text;
            c.UseColumnTextForButtonValue = true;
            c.Width = 72;
            c.FlatStyle = FlatStyle.Flat;
            c.DefaultCellStyle.BackColor = Theme.Card;
            c.DefaultCellStyle.ForeColor = Theme.Text;
            c.DefaultCellStyle.SelectionBackColor = Theme.Accent;
            c.DefaultCellStyle.SelectionForeColor = Color.White;
            g.Columns.Add(c);
        }

        private static string HostOf(DeployConfig cfg, string key)
        {
            string h = cfg.Get(key);
            if (h.Length == 0) h = cfg.Get("DEPLOY_HOST");
            if (h.Length == 0) h = "127.0.0.1";
            return h;
        }

        private static int ParsePort(string s, int def)
        {
            int v = 0;
            try { if (s != null && s.Length > 0) v = int.Parse(s); }
            catch { v = 0; }
            return v > 0 ? v : def;
        }

        private bool refreshingUnits;
        private bool refreshPending;

        private void RefreshUnits()
        {
            if (dgvUnits == null) return;
            if (refreshingUnits)
            {
                // 扫描期间来的刷新先记下，结束后补一轮，避免启动/停止后的状态停留在旧值
                refreshPending = true;
                return;
            }
            DeployConfig cfg = DeployConfig.Load(workDir);
            List<UnitRow> list = new List<UnitRow>();

            AddUnit(list, cfg, "MySQL", "数据库", "mysql", "MYSQL_HOST", "MYSQL_PORT", 3306, "START_MYSQL", false);
            AddUnit(list, cfg, "PostgreSQL", "数据库", "pg", "PG_HOST", "PG_PORT", 5432, "START_PG", false);
            AddUnit(list, cfg, "Redis", "缓存", "redis", "REDIS_HOST", "REDIS_PORT", 6379, "START_REDIS", false);
            AddUnit(list, cfg, "RocketMQ", "消息队列", "mq", "MQ_HOST", "MQ_NAMESRV_PORT", 9876, "START_MQ", false);
            AddUnit(list, cfg, "MinIO", "对象存储", "minio", "MINIO_HOST", "MINIO_PORT", 9000, "START_MINIO", false);
            AddUnit(list, cfg, "Nacos", "注册中心", "nacos", "NACOS_HOST", "NACOS_PORT", 8848, "START_NACOS", false);
            AddUnit(list, cfg, "GeoServer", "GIS", "geoserver", "GEOSERVER_HOST", "GEOSERVER_PORT", 8080, "START_GEOSERVER", false);
            AddUnit(list, cfg, "Nginx", "代理", "nginx", "NGINX_HOST", "NGINX_PORT", 80, "START_NGINX", false);

            string depHost = HostOf(cfg, "DEPLOY_HOST");
            AppsConfig apps = AppsConfig.Load(workDir);
            foreach (AppEntry e in apps.Items)
            {
                UnitRow u = new UnitRow();
                u.Name = e.Name;
                u.Type = "服务";
                u.Key = e.Name;
                string h = e.Host == null ? "" : e.Host.Trim();
                u.Host = h.Length > 0 ? h : depHost;
                u.Port = ParsePort(e.Port, 0);
                u.Local = IsLocalHost(h, depHost);
                u.IsApp = true;
                list.Add(u);
            }
            units = list;

            refreshingUnits = true;
            if (!dgvUnits.IsHandleCreated)
            {
                // 窗口句柄还没创建：推迟到句柄创建后再异步扫描，避免 netstat 阻塞首次显示
                refreshingUnits = false;
                refreshPending = false;
                EventHandler onHandle = null;
                onHandle = delegate
                {
                    dgvUnits.HandleCreated -= onHandle;
                    RefreshUnits();
                };
                dgvUnits.HandleCreated += onHandle;
                return;
            }
            Thread th = new Thread(delegate()
            {
                HashSet<int> ports = GetListeningPorts();
                try
                {
                    BeginInvoke(new Action(delegate()
                    {
                        FillUnits(ports);
                        refreshingUnits = false;
                        if (refreshPending)
                        {
                            refreshPending = false;
                            RefreshUnits();
                        }
                    }));
                }
                catch { refreshingUnits = false; refreshPending = false; }
            });
            th.IsBackground = true;
            th.Start();
        }

        private void FillUnits(HashSet<int> ports)
        {
            if (dgvUnits == null || dgvUnits.IsDisposed) return;
            dgvUnits.Rows.Clear();
            foreach (UnitRow u in units)
            {
                string st = !u.Local ? "REMOTE" : (ports.Contains(u.Port) ? "UP" : "DOWN");
                int i = dgvUnits.Rows.Add(u.Name, u.Type, u.Host, u.Port, st, "", "", "");
                dgvUnits.Rows[i].Tag = u;
                dgvUnits.Rows[i].Cells["status"].Style.ForeColor =
                    st == "UP" ? Theme.Ok : (st == "REMOTE" ? Theme.Muted : Color.FromArgb(248, 113, 113));
            }
            LayoutUnits();
        }

        private static void AddUnit(List<UnitRow> list, DeployConfig cfg, string name, string type,
            string key, string hostKey, string portKey, int defPort, string startKey, bool isApp)
        {
            UnitRow u = new UnitRow();
            u.Name = name;
            u.Type = type;
            u.Key = key;
            u.Host = HostOf(cfg, hostKey);
            u.Port = ParsePort(cfg.Get(portKey), defPort);
            u.Local = cfg.Get(startKey) != "0";
            u.IsApp = isApp;
            list.Add(u);
        }

        private static HashSet<int> GetListeningPorts()
        {
            HashSet<int> set = new HashSet<int>();
            try
            {
                ProcessStartInfo psi = new ProcessStartInfo("netstat", "-ano");
                psi.UseShellExecute = false;
                psi.CreateNoWindow = true;
                psi.RedirectStandardOutput = true;
                Process p = Process.Start(psi);
                string output = p.StandardOutput.ReadToEnd();
                p.WaitForExit();
                foreach (string line in output.Split('\n'))
                {
                    if (line.IndexOf("LISTENING", StringComparison.OrdinalIgnoreCase) < 0) continue;
                    string[] parts = line.Split(new char[] { ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries);
                    if (parts.Length < 2) continue;
                    string local = parts[1];
                    int c = local.LastIndexOf(':');
                    if (c < 0) continue;
                    string portText = local.Substring(c + 1);
                    try { set.Add(int.Parse(portText)); }
                    catch { }
                }
            }
            catch { }
            return set;
        }

        private void OnUnitCellClick(DataGridViewCellEventArgs e)
        {
            if (e.RowIndex < 0) return;
            string col = dgvUnits.Columns[e.ColumnIndex].Name;
            string action = null;
            if (col == "start") action = "start";
            else if (col == "stop") action = "stop";
            else if (col == "restart") action = "restart";
            if (action == null) return;
            UnitRow u = dgvUnits.Rows[e.RowIndex].Tag as UnitRow;
            if (u != null) UnitAction(action, u);
        }

        private void UnitAction(string action, UnitRow u)
        {
            if (running) { MessageBox.Show("有任务正在执行，请稍候"); return; }
            if (!u.Local)
            {
                MessageBox.Show(u.Name + " 运行在 " + u.Host + "，请到该机器上用 bin\\9-infra.bat 操作");
                return;
            }
            if (action != "start")
            {
                string tip = action == "stop" ? "确定停止 " : "确定重启 ";
                if (MessageBox.Show(tip + u.Name + "？", "确认", MessageBoxButtons.YesNo) != DialogResult.Yes)
                    return;
            }
            if (!ConfirmUsingSavedConfig()) return;
            string script = u.IsApp ? @"bin\8-service.bat" : @"bin\9-infra.bat";
            string args = action + " " + u.Key;
            string title = (action == "start" ? "启动 " : action == "stop" ? "停止 " : "重启 ") + u.Name;
            RunTask(title, delegate()
            {
                RunLog("");
                RunLog(">>> " + args);
                return RunProcessArgs(script, args, workDir, RunLog);
            }, delegate() { RefreshUnits(); });
        }

        private void ReadNacos()
        {
            if (running) { MessageBox.Show("有任务正在执行，请稍候"); return; }
            DeployConfig cfg = CollectDeploy();
            AppsConfig apps = CollectApps();
            string baseUrl = NacosApi.BaseUrl(cfg);
            string group = cfg.Get("NACOS_GROUP");
            if (group.Length == 0) group = "DEFAULT_GROUP";
            string tenant = cfg.Get("NACOS_NAMESPACE");      // 空 = public
            string profile = cfg.Get("NACOS_PROFILE");
            string user = cfg.Get("NACOS_USER");
            string pwd = cfg.Get("NACOS_PWD");

            running = true;
            SetRunButtons(false);
            ClearLog(txtRunLog);
            ShowPage(5);
            Thread th = new Thread(delegate()
            {
                int miss = 0;
                string error = "";
                List<NacosCfg> result = null;
                try
                {
                    RunLog(">>> Nacos  " + baseUrl);
                    RunLog("    命名空间=" + (tenant.Length == 0 ? "public" : tenant) + "   Group=" + group);

                    string token = "";
                    if (user.Length > 0)
                    {
                        try { token = NacosApi.Login(baseUrl, user, pwd); }
                        catch (Exception ex) { RunLog("WARN 登录失败: " + ex.Message); }
                        if (token.Length == 0) RunLog("WARN 未取得 accessToken，按匿名方式继续");
                    }

                    result = FetchNacosConfigs(baseUrl, group, tenant, token, apps, profile, out miss);
                    if (result.Count == 0)
                    {
                        RunLog("命名空间 [" + (tenant.Length == 0 ? "public" : tenant) + "] 没有配置");
                        LogNamespaces(baseUrl, token);
                        if (tenant.Length > 0)
                        {
                            RunLog(">>> 尝试从 public 命名空间读取");
                            List<NacosCfg> r2 = FetchNacosConfigs(baseUrl, group, "", token, apps, profile, out miss);
                            if (r2.Count > 0)
                            {
                                result = r2;
                                RunLog("WARN 以上配置来自 public 命名空间，如非预期请检查 部署参数 - NACOS_NAMESPACE");
                            }
                        }
                    }

                    if (result.Count == 0)
                    {
                        RunLog("");
                        RunLog("未读取到任何配置。请核对 Nacos 地址 / 命名空间 / Group：");
                        RunLog("  控制台: " + baseUrl + "/");
                        RunLog("  当前配置在 部署参数 页: NACOS_PORT / NACOS_NAMESPACE / NACOS_GROUP");
                    }
                }
                catch (Exception ex)
                {
                    error = ex.Message;
                    RunLog("读取失败: " + ex.Message);
                }
                finally
                {
                    SafeBeginInvoke(delegate()
                    {
                        running = false;
                        SetRunButtons(true);
                        if (result != null && result.Count > 0)
                        {
                            nacosCfgs = result;
                            FillNacosCombo(0);
                            ShowPage(3);
                            RunLog("读取结束: 成功 " + result.Count + " 个, 失败 " + miss
                                + " 个。已加载到 YML 配置页，修改后点“保存到 Nacos”即可");
                        }
                        else
                        {
                            RunLog("读取结束: 0 个配置"
                                + (error.Length > 0 ? "，错误: " + error : ""));
                        }
                    });
                }
            });
            th.IsBackground = true;
            th.Start();
        }

        private void FillNacosCombo(int selectIndex)
        {
            if (nacosCfgs.Count == 0)
            {
                nacosIndex = -1;
                btnNacosPick.Text = "Nacos: 未读取  ▾";
                return;
            }
            if (selectIndex < 0 || selectIndex >= nacosCfgs.Count) selectIndex = 0;
            SelectNacosIndex(selectIndex);
        }

        private void SelectNacosIndex(int i)
        {
            if (i < 0 || i >= nacosCfgs.Count) return;
            if (!ConfirmDiscardYml()) return;
            nacosIndex = i;
            btnNacosPick.Text = "Nacos: " + nacosCfgs[i].DataId + "  ▾";
            if (lstCfgFiles != null && lstCfgFiles.SelectedIndex >= 0)
            {
                loadingCfgList = true;
                lstCfgFiles.SelectedIndex = -1;
                loadingCfgList = false;
            }
            ShowNacosConfig(nacosCfgs[i]);
        }

        private void ShowNacosMenu()
        {
            if (nacosCfgs.Count == 0)
            {
                MessageBox.Show("请先点“读取”从 Nacos 加载配置");
                return;
            }
            ContextMenuStrip m = new ContextMenuStrip();
            m.Renderer = new DarkMenuRenderer();
            m.Font = Theme.Small;
            m.BackColor = Theme.Card;
            m.ForeColor = Theme.Text;
            m.ShowImageMargin = false;
            for (int i = 0; i < nacosCfgs.Count; i++)
            {
                int idx = i;
                ToolStripMenuItem it = new ToolStripMenuItem(nacosCfgs[i].ToString());
                it.ForeColor = Theme.Text;
                if (i == nacosIndex) it.Checked = true;
                it.Click += delegate { SelectNacosIndex(idx); };
                m.Items.Add(it);
            }
            m.Closed += delegate { m.Dispose(); };
            m.Show(btnNacosPick, new Point(0, btnNacosPick.Height));
        }

        // 读取命名空间内的全部配置到内存，供在线编辑；不落本地文件
        private List<NacosCfg> FetchNacosConfigs(string baseUrl, string group, string tenant, string token,
            AppsConfig apps, string profile, out int miss)
        {
            miss = 0;
            List<NacosCfg> result = new List<NacosCfg>();
            List<NacosConfigInfo> list = null;
            try { list = NacosApi.ListConfigs(baseUrl, group, tenant, token); }
            catch (Exception ex) { RunLog("WARN 枚举配置失败: " + ex.Message); }

            if (list != null)
            {
                if (list.Count > 0) RunLog("发现 " + list.Count + " 个配置");
                foreach (NacosConfigInfo it in list)
                {
                    string content = null;
                    try { content = NacosApi.GetConfig(baseUrl, it.Group, tenant, it.DataId, token); }
                    catch (Exception ex)
                    {
                        RunLog("  FAIL " + it.DataId + "  " + ex.Message);
                        miss++;
                        continue;
                    }
                    if (content == null)
                    {
                        RunLog("  MISS " + it.DataId + "  [" + it.Group + "]");
                        miss++;
                        continue;
                    }
                    NacosCfg c = new NacosCfg();
                    c.DataId = it.DataId;
                    c.Group = it.Group;
                    c.Tenant = tenant;
                    c.Type = it.Type;
                    c.Content = content;
                    result.Add(c);
                    RunLog("  OK   " + it.DataId + "  [" + it.Group + "]");
                }
                return result;
            }

            // 枚举接口不可用时按服务名猜测 dataId
            RunLog(">>> 枚举接口不可用，改为按服务名尝试");
            foreach (AppEntry e in apps.Items)
            {
                string[] ids = GuessDataIds(e.Name, profile);
                foreach (string id in ids)
                {
                    if (ContainsDataId(result, id)) continue;
                    string content = null;
                    try { content = NacosApi.GetConfig(baseUrl, group, tenant, id, token); }
                    catch (Exception ex) { RunLog("  FAIL " + id + "  " + ex.Message); continue; }
                    if (content == null) continue;
                    NacosCfg c = new NacosCfg();
                    c.DataId = id;
                    c.Group = group;
                    c.Tenant = tenant;
                    c.Type = "yaml";
                    c.Content = content;
                    result.Add(c);
                    RunLog("  OK   " + id);
                    break;
                }
            }
            return result;
        }

        private static bool ContainsDataId(List<NacosCfg> list, string id)
        {
            foreach (NacosCfg c in list)
                if (string.Equals(c.DataId, id, StringComparison.OrdinalIgnoreCase)) return true;
            return false;
        }

        private void LogNamespaces(string baseUrl, string token)
        {
            try
            {
                List<string> list = NacosApi.ListNamespaces(baseUrl, token);
                if (list.Count > 0) RunLog("    可用命名空间: " + string.Join(", ", list.ToArray()));
            }
            catch (Exception ex) { RunLog("WARN 查询命名空间失败: " + ex.Message); }
        }

        private static string[] GuessDataIds(string name, string profile)
        {
            if (profile.Length > 0)
                return new string[] {
                    name + "-" + profile + ".yaml",
                    name + "-" + profile + ".yml",
                    name + ".yaml",
                    name + ".yml" };
            return new string[] { name + ".yaml", name + ".yml" };
        }

        private static NeonButton MakeButton(string text, bool primary)
        {
            NeonButton b = new NeonButton();
            b.Text = text;
            b.Primary = primary;
            b.Height = 32;
            return b;
        }

        private static Button MakeBarButton(FlowLayoutPanel bar, string text, bool primary)
        {
            NeonButton b = MakeButton(text, primary);
            b.Width = 110;
            b.Margin = new Padding(0, 9, 6, 4);
            bar.Controls.Add(b);
            return b;
        }

        private static void AddTextCol(DataGridView g, string name, string header, int width, bool readOnly)
        {
            DataGridViewTextBoxColumn c = new DataGridViewTextBoxColumn();
            c.Name = name;
            c.HeaderText = header;
            c.Width = width;
            c.ReadOnly = readOnly;
            g.Columns.Add(c);
        }

        // ---------------- data ----------------
        private void ReloadAll()
        {
            if (txtTarget != null) txtTarget.Text = workDir;
            if (lblWorkDir != null) lblWorkDir.Text = "工作目录  " + workDir;
            ReloadDeploy();
            ReloadApps();
            LoadConfigList();
            RefreshUnits();
        }

        private void ReloadDeploy()
        {
            DeployConfig cfg = DeployConfig.Load(workDir);
            foreach (string key in DeployConfig.Keys)
                deployBoxes[key].Text = cfg.Get(key);
        }

        private DeployConfig CollectDeploy()
        {
            DeployConfig cfg = new DeployConfig();
            foreach (string key in DeployConfig.Keys)
                cfg.Set(key, deployBoxes[key].Text.Trim());
            return cfg;
        }

        private void ReloadApps()
        {
            dgvApps.Rows.Clear();
            AppsConfig cfg = AppsConfig.Load(workDir);
            foreach (AppEntry e in cfg.Items)
            {
                string jdk = (e.Jdk == "21") ? "21" : "17";
                int i = dgvApps.Rows.Add(e.Name, e.Jar, e.Port, jdk, e.Host, e.Jvm, e.Extra);
                dgvApps.Rows[i].Cells["jdk"].Value = jdk;
            }
            LayoutApps();
        }

        private AppsConfig CollectApps()
        {
            AppsConfig cfg = new AppsConfig();
            foreach (DataGridViewRow row in dgvApps.Rows)
            {
                if (row.IsNewRow) continue;
                string name = Cell(row, "name");
                if (name.Length == 0) continue;
                AppEntry e = new AppEntry();
                e.Name = name;
                e.Jar = Cell(row, "jar");
                e.Port = Cell(row, "port");
                e.Jdk = Cell(row, "jdk");
                if (e.Jdk != "21") e.Jdk = "17";
                e.Jvm = Cell(row, "jvm");
                e.Extra = Cell(row, "extra");
                e.Host = Cell(row, "host");
                cfg.Items.Add(e);
            }
            return cfg;
        }

        private static string Cell(DataGridViewRow row, string name)
        {
            object v = row.Cells[name].Value;
            return v == null ? "" : v.ToString().Trim();
        }

        // CollectApps 会静默丢弃没有服务名的行，保存/安装前先拦住，避免用户以为改动已生效
        private string FindAppNameError()
        {
            foreach (DataGridViewRow row in dgvApps.Rows)
            {
                if (row.IsNewRow) continue;
                if (Cell(row, "name").Length > 0) continue;
                foreach (DataGridViewCell c in row.Cells)
                {
                    object v = c.Value;
                    if (v != null && v.ToString().Trim().Length > 0)
                        return "第 " + (row.Index + 1) + " 行缺少服务名：请填写名称，或删除这一行";
                }
            }
            return "";
        }

        // 保存/安装前统一校验：端口必须是 1-65535 的整数，且基础设施与服务不能撞端口
        private static string ValidateConfigNumbers(DeployConfig dc, AppsConfig ac)
        {
            string jdk = dc.Get("INFRA_JDK").Trim();
            if (jdk.Length > 0 && jdk != "17" && jdk != "21")
                return "INFRA_JDK 只能是 17 或 21，当前为：" + jdk;
            Dictionary<int, string> used = new Dictionary<int, string>();
            foreach (string key in DeployConfig.Keys)
            {
                if (!key.EndsWith("_PORT", StringComparison.OrdinalIgnoreCase)) continue;
                string v = dc.Get(key).Trim();
                if (v.Length == 0) continue;
                int p;
                if (!int.TryParse(v, out p) || p < 1 || p > 65535)
                    return key + " 端口不合法：" + v + "\r\n端口必须是 1-65535 的整数";
                if (used.ContainsKey(p))
                    return key + " 与 " + used[p] + " 端口重复：" + p;
                used[p] = key;
            }
            Dictionary<string, bool> names = new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);
            foreach (AppEntry e in ac.Items)
            {
                if (e.Name.Length == 0) continue;
                if (names.ContainsKey(e.Name))
                    return "服务名重复：" + e.Name;
                names[e.Name] = true;
                string port = e.Port == null ? "" : e.Port.Trim();
                int p;
                if (!int.TryParse(port, out p) || p < 1 || p > 65535)
                    return "服务 " + e.Name + " 端口不合法：" + (port.Length == 0 ? "（空）" : port);
                if (used.ContainsKey(p))
                    return "服务 " + e.Name + " 端口 " + p + " 与 " + used[p] + " 重复";
                used[p] = "服务 " + e.Name;
            }
            return "";
        }

        private bool DeployDirty()
        {
            DeployConfig disk = DeployConfig.Load(workDir);
            foreach (string key in DeployConfig.Keys)
            {
                TextBox box = deployBoxes[key];
                if (box.Text.Trim() != disk.Get(key).Trim()) return true;
            }
            return false;
        }

        private bool AppsDirty()
        {
            AppsConfig disk = AppsConfig.Load(workDir);
            List<AppEntry> ui = CollectApps().Items;
            if (ui.Count != disk.Items.Count) return true;
            for (int i = 0; i < ui.Count; i++)
            {
                AppEntry a = ui[i];
                AppEntry b = disk.Items[i];
                if (a.Name != b.Name || a.Jar != b.Jar || a.Port != b.Port || a.Jdk != b.Jdk ||
                    a.Jvm != b.Jvm || a.Extra != b.Extra || a.Host != b.Host) return true;
            }
            return false;
        }

        // 启停脚本读的是磁盘上的 conf，界面里未保存的修改不会生效，先提醒
        private bool ConfirmUsingSavedConfig()
        {
            if (!DeployDirty() && !AppsDirty()) return true;
            return MessageBox.Show("部署参数 / 服务清单有未保存的修改，本次操作将使用已保存的配置。\r\n建议先点“保存参数 / 保存清单”。\r\n\r\n仍要继续执行？",
                "未保存的配置", MessageBoxButtons.YesNo, MessageBoxIcon.Warning) == DialogResult.Yes;
        }

        private List<YmlRow> CollectYmlRows()
        {
            List<YmlRow> rows = new List<YmlRow>();
            foreach (DataGridViewRow row in dgvYml.Rows)
            {
                YmlRow r = row.Tag as YmlRow;
                if (r == null) continue;
                r.Key = Cell(row, "key");
                object v = row.Cells["value"].Value;
                r.Value = v == null ? "" : v.ToString().Trim();
                rows.Add(r);
            }
            return rows;
        }

        private List<YmlRow> CollectAllYmlRows()
        {
            List<YmlRow> rows = CollectYmlRows();
            rows.AddRange(deletedYmlRows);
            return rows;
        }

        private void SaveYml()
        {
            int n = 0;
            if (!SaveCurrentYml(out n)) return;
            MessageBox.Show(currentNacos != null ? "已更新在线配置（尚未写入 Nacos）" : "已保存 " + n + " 项修改");
        }

        private bool SaveCurrentYml(out int count)
        {
            count = 0;
            if (currentNacos != null)
            {
                dgvYml.EndEdit();
                if (!ValidateYmlKeys()) return false;
                string text = YmlEditor.BuildText(currentNacos.Content, CollectAllYmlRows(), out count);
                currentNacos.Content = text;
                deletedYmlRows.Clear();
                ymlDirty = false;
                ShowNacosConfig(currentNacos);
                return true;
            }
            if (currentCfgRel.Length == 0) { MessageBox.Show("请先在左侧选择本地文件，或读取 Nacos 配置"); return false; }
            string f = Path.IsPathRooted(currentCfgRel) ? currentCfgRel : Path.Combine(workDir, currentCfgRel);
            if (txtCfgFile.Visible)
            {
                try
                {
                    File.WriteAllText(f, txtCfgFile.Text, new UTF8Encoding(false));
                    count = 1;
                    ymlDirty = false;
                    return true;
                }
                catch (Exception ex)
                {
                    MessageBox.Show("保存失败: " + ex.Message);
                    return false;
                }
            }
            dgvYml.EndEdit();
            if (!ValidateYmlKeys()) return false;
            count = YmlEditor.Save(workDir, CollectAllYmlRows());
            deletedYmlRows.Clear();
            ymlDirty = false;
            ShowConfigFile(currentCfgRel);
            return true;
        }

        // 属性名清空后 BuildText 会拼出 ": value" 这种坏行，所有行（不只新增行）都要校验
        private bool ValidateYmlKeys()
        {
            foreach (DataGridViewRow row in dgvYml.Rows)
            {
                YmlRow r = row.Tag as YmlRow;
                if (r == null) continue;
                if (Cell(row, "key").Length == 0)
                {
                    MessageBox.Show("属性名不能为空（第 " + (row.Index + 1) + " 行）", "无法保存");
                    dgvYml.CurrentCell = row.Cells["key"];
                    return false;
                }
            }
            return true;
        }

        private void SaveYmlToNacos()
        {
            if (running) { MessageBox.Show("有任务正在执行，请稍候"); return; }
            bool online = currentNacos != null;
            if (!online && currentCfgRel.Length == 0)
            {
                MessageBox.Show("请先在左侧选择本地文件，或读取 Nacos 配置");
                return;
            }

            string full = "";
            string ext = "";
            if (!online)
            {
                full = Path.IsPathRooted(currentCfgRel) ? currentCfgRel : Path.Combine(workDir, currentCfgRel);
                string nacosDir = Path.GetFullPath(Path.Combine(workDir, @"conf\nacos")).TrimEnd('\\') + "\\";
                if (!Path.GetFullPath(full).TrimEnd('\\').StartsWith(nacosDir, StringComparison.OrdinalIgnoreCase))
                {
                    MessageBox.Show("本地文件只有 conf\\nacos 下的配置才能写回 Nacos；在线配置请先用“读取”加载。");
                    return;
                }
                ext = Path.GetExtension(full).ToLowerInvariant();
                if (ext != ".yaml" && ext != ".yml" && ext != ".properties")
                {
                    MessageBox.Show("当前文件类型不支持写入 Nacos，只支持 yaml / yml / properties。");
                    return;
                }
            }
            else
            {
                ext = currentNacos.Type == "properties" ? ".properties" : ".yaml";
            }

            DeployConfig cfg = CollectDeploy();
            string baseUrl = NacosApi.BaseUrl(cfg);
            string user = cfg.Get("NACOS_USER");
            string pwd = cfg.Get("NACOS_PWD");

            string fileName = "";
            string dataId;
            string group;
            string tenant;
            bool probe = false;
            if (online)
            {
                dataId = currentNacos.DataId;
                group = currentNacos.Group;
                tenant = currentNacos.Tenant;
            }
            else
            {
                fileName = Path.GetFileName(full);
                NacosMetaEntry me = null;
                Dictionary<string, NacosMetaEntry> meta = NacosMeta.Load(workDir);
                if (meta.ContainsKey(fileName)) me = meta[fileName];
                dataId = (me != null && me.DataId.Length > 0) ? me.DataId : fileName;
                group = (me != null && me.Group.Length > 0) ? me.Group : cfg.Get("NACOS_GROUP");
                if (group.Length == 0) group = "DEFAULT_GROUP";
                tenant = (me != null && me.Tenant.Length > 0) ? me.Tenant : cfg.Get("NACOS_NAMESPACE");
                probe = me == null;
            }

            string tip = "保存并写入 Nacos？\r\n\r\ndataId = " + dataId
                + "\r\nGroup = " + group
                + "\r\n命名空间 = " + (tenant.Length == 0 ? "public" : tenant)
                + (probe ? "\r\n\r\n首次写入会探测 Nacos 上已存在的 dataId" : "");
            if (MessageBox.Show(tip, "确认", MessageBoxButtons.YesNo) != DialogResult.Yes) return;

            int n = 0;
            if (!SaveCurrentYml(out n)) return;
            string content = online ? currentNacos.Content : File.ReadAllText(full, Encoding.UTF8);

            string type = ext == ".properties" ? "properties" : "yaml";
            string did = dataId;
            string grp = group;
            string ten = tenant;
            string file = fileName;
            string usr = user;
            string pass = pwd;
            bool needProbe = probe;
            string msg = "";
            running = true;
            SetRunButtons(false);
            Thread th = new Thread(delegate()
            {
                try
                {
                    // 登录和 dataId 探测都会访问 Nacos（单次最长 15s），必须放到后台线程，否则界面假死
                    string tok = "";
                    if (usr.Length > 0)
                    {
                        try { tok = NacosApi.Login(baseUrl, usr, pass); }
                        catch { }
                    }
                    if (needProbe)
                    {
                        try
                        {
                            string got = NacosApi.GetConfig(baseUrl, grp, ten, did, tok);
                            if (got == null)
                            {
                                string bare = Path.GetFileNameWithoutExtension(file);
                                if (bare.Length > 0 && !string.Equals(bare, did, StringComparison.OrdinalIgnoreCase))
                                {
                                    string got2 = NacosApi.GetConfig(baseUrl, grp, ten, bare, tok);
                                    if (got2 != null) did = bare;
                                }
                            }
                        }
                        catch { }
                        try { NacosMeta.Set(workDir, file, did, grp, ten); }
                        catch { }
                    }
                    bool ok = NacosApi.Publish(baseUrl, grp, ten, did, type, content, tok);
                    msg = ok ? "已保存并写入 Nacos: " + did : "写入失败，Nacos 返回 false";
                }
                catch (Exception ex)
                {
                    msg = "写入失败: " + ex.Message;
                }
                finally
                {
                    SafeBeginInvoke(delegate()
                    {
                        running = false;
                        SetRunButtons(true);
                        MessageBox.Show(msg);
                    });
                }
            });
            th.IsBackground = true;
            th.Start();
        }

        // ---------------- install ----------------
        private void OnInstall()
        {
            if (running) { MessageBox.Show("有任务正在执行，请稍候"); return; }
            string target = txtTarget.Text.Trim();
            if (target.Length == 0) { MessageBox.Show("请选择安装目录"); return; }
            if (target.IndexOfAny(new char[] { ' ', '%', '!', '^', '&', '"', '|' }) >= 0)
            {
                MessageBox.Show("安装路径不能包含空格或 % ! ^ & \" | 字符");
                return;
            }
            try { target = Path.GetFullPath(target).TrimEnd('\\'); }
            catch { MessageBox.Show("安装路径不合法"); return; }

            string src = PathHelper.Root;
            string srcFull;
            try { srcFull = Path.GetFullPath(src).TrimEnd('\\'); }
            catch { srcFull = src; }
            if (!string.Equals(target, srcFull, StringComparison.OrdinalIgnoreCase) &&
                target.StartsWith(srcFull + "\\", StringComparison.OrdinalIgnoreCase))
            {
                MessageBox.Show("安装目录不能位于当前目录内部，请选择其他路径");
                return;
            }
            if (!Directory.Exists(Path.Combine(src, "runtime")) ||
                !Directory.Exists(Path.Combine(src, "infra")))
            {
                if (MessageBox.Show("当前目录缺少 runtime 或 infra，仍然继续？", "提示",
                    MessageBoxButtons.YesNo) != DialogResult.Yes) return;
            }

            string badName = FindAppNameError();
            if (badName.Length > 0)
            {
                MessageBox.Show(badName, "配置有误");
                return;
            }
            DeployConfig dc = CollectDeploy();
            AppsConfig ac = CollectApps();
            string bad = ValidateConfigNumbers(dc, ac);
            if (bad.Length > 0)
            {
                MessageBox.Show(bad, "配置有误");
                return;
            }
            dgvYml.EndEdit();
            // dgvYml 此时可能是 Nacos 在线配置（FilePath = dataId），不能当本地文件写进目标目录
            List<YmlRow> yr = currentNacos != null ? new List<YmlRow>() : CollectAllYmlRows();
            for (int i = 0; i < yr.Count; i++)
            {
                if (yr[i].RelPath.Length > 0 && !Path.IsPathRooted(yr[i].RelPath))
                    yr[i].FilePath = Path.Combine(target, yr[i].RelPath);
            }
            bool doInit = chkInit.Checked;
            bool mkLink = chkShortcut.Checked;

            running = true;
            SetRunButtons(false);
            ClearLog(txtInstallLog);
            Thread th = new Thread(delegate()
            {
                try
                {
                    InstallLog("源目录  : " + src);
                    InstallLog("目标目录: " + target);
                    if (string.Equals(srcFull, target, StringComparison.OrdinalIgnoreCase))
                    {
                        InstallLog("目标目录就是当前目录，跳过文件复制");
                    }
                    else
                    {
                        if (File.Exists(PathHelper.DeployPath(target)))
                        {
                            HashSet<int> listening = GetListeningPorts();
                            List<string> busy = new List<string>();
                            string[] infraPorts = new string[] { "MYSQL_PORT", "PG_PORT", "REDIS_PORT",
                                "MINIO_PORT", "MQ_NAMESRV_PORT", "MQ_BROKER_PORT", "NACOS_PORT",
                                "GEOSERVER_PORT", "NGINX_PORT" };
                            DeployConfig oldDc = DeployConfig.Load(target);
                            foreach (string key in infraPorts)
                            {
                                int p;
                                if (int.TryParse(oldDc.Get(key), out p) && listening.Contains(p))
                                    busy.Add(key + "=" + p);
                            }
                            AppsConfig oldAc = AppsConfig.Load(target);
                            foreach (AppEntry e in oldAc.Items)
                            {
                                int p;
                                if (int.TryParse(e.Port, out p) && listening.Contains(p))
                                    busy.Add(e.Name + "=" + p);
                            }
                            if (busy.Count > 0)
                            {
                                InstallLog("目标目录已有部署正在运行: " + string.Join(", ", busy.ToArray()));
                                InstallLog("请先执行 " + Path.Combine(target, "stop-all.bat") + " 后重新安装");
                                SafeBeginInvoke(delegate()
                                {
                                    running = false;
                                    SetRunButtons(true);
                                    MessageBox.Show("目标目录已有服务在运行，请先停止后再安装。");
                                });
                                return;
                            }
                            string bak = Path.Combine(target, "conf.bak-" + DateTime.Now.ToString("yyyyMMdd-HHmmss"));
                            FileOps.CopyDir(PathHelper.ConfDir(target), bak, InstallLog);
                            InstallLog("已备份原配置: " + bak);
                        }
                        FileOps.CopyPayload(src, target, InstallLog);
                    }
                    dc.Save(target);
                    ac.Save(target);
                    YmlEditor.Save(target, yr);
                    InstallLog("配置已写入 " + PathHelper.ConfDir(target));
                    if (mkLink)
                    {
                        try { CreateShortcuts(target); InstallLog("桌面快捷方式已创建"); }
                        catch (Exception ex) { InstallLog("快捷方式失败: " + ex.Message); }
                    }
                    int initRc = 0;
                    if (doInit)
                    {
                        InstallLog("开始初始化数据目录 ...");
                        initRc = RunProcess(@"bin\0-init.bat", target, InstallLog);
                        if (initRc != 0)
                            InstallLog("FAIL 初始化数据失败（退出码 " + initRc + "），请查看上方日志");
                    }
                    SafeBeginInvoke(delegate()
                    {
                        workDir = target;
                        running = false;
                        SetRunButtons(true);
                        ymlDirty = false;
                        lastCfgIndex = -1;
                        ReloadAll();
                        InstallLog(initRc != 0 ? "安装完成，但初始化数据失败" : "安装完成");
                        if (initRc != 0 && lblStatus != null)
                        {
                            lblStatus.Text = "●  有失败";
                            statusColor = Color.FromArgb(248, 113, 113);
                            lblStatus.ForeColor = statusColor;
                        }
                    });
                }
                catch (Exception ex)
                {
                    SafeBeginInvoke(delegate()
                    {
                        running = false;
                        SetRunButtons(true);
                        InstallLog("安装失败: " + ex.Message);
                        MessageBox.Show("安装失败: " + ex.Message);
                    });
                }
            });
            th.IsBackground = true;
            th.Start();
        }

        private static void CreateShortcuts(string dir)
        {
            object shell = Type.GetTypeFromProgID("WScript.Shell");
            if (shell == null) return;
            string desktop = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
            CreateShortcut(shell, desktop, "启动 智能部署中心", Path.Combine(dir, "start-all.bat"), dir);
            CreateShortcut(shell, desktop, "停止 智能部署中心", Path.Combine(dir, "stop-all.bat"), dir);
        }

        private static void CreateShortcut(object shell, string desktop, string name, string target, string workDir)
        {
            string path = Path.Combine(desktop, name + ".lnk");
            object lnk = shell.GetType().InvokeMember("CreateShortcut", BindingFlags.InvokeMethod,
                null, shell, new object[] { path });
            lnk.GetType().InvokeMember("TargetPath", BindingFlags.SetProperty, null, lnk, new object[] { target });
            lnk.GetType().InvokeMember("WorkingDirectory", BindingFlags.SetProperty, null, lnk, new object[] { workDir });
            try
            {
                lnk.GetType().InvokeMember("IconLocation", BindingFlags.SetProperty, null, lnk,
                    new object[] { Path.Combine(workDir, "Setup.exe") + ",0" });
            }
            catch { }
            lnk.GetType().InvokeMember("Save", BindingFlags.InvokeMethod, null, lnk, null);
        }

        // ---------------- run ----------------
        // 统一的“后台执行 + 按钮/光标恢复 + 失败提示”模板
        private void RunTask(string title, Func<int> work, Action uiDone)
        {
            if (running) { MessageBox.Show("有任务正在执行，请稍候"); return; }
            running = true;
            SetRunButtons(false);
            ClearLog(txtRunLog);
            ShowPage(5);
            Thread th = new Thread(delegate()
            {
                int rc = 0;
                try { rc = work(); }
                catch (Exception ex)
                {
                    rc = 1;
                    RunLog("执行异常: " + ex.Message);
                }
                finally
                {
                    SafeBeginInvoke(delegate()
                    {
                        running = false;
                        SetRunButtons(true);
                        if (uiDone != null) uiDone();
                        if (rc != 0)
                        {
                            RunLog(title + " 失败，详见上方日志");
                            if (lblStatus != null)
                            {
                                lblStatus.Text = "●  有失败";
                                statusColor = Color.FromArgb(248, 113, 113);
                                lblStatus.ForeColor = statusColor;
                            }
                        }
                        RunLog("任务结束");
                    });
                }
            });
            th.IsBackground = true;
            th.Start();
        }

        // 窗口关闭后 BeginInvoke 会抛异常；后台线程的 finally 必须走这里
        private void SafeBeginInvoke(Action action)
        {
            try
            {
                if (IsHandleCreated && !IsDisposed) BeginInvoke(action);
            }
            catch { }
        }

        private void RunScripts(string[] scripts)
        {
            if (!ConfirmUsingSavedConfig()) return;
            RunTask("执行脚本", delegate()
            {
                foreach (string s in scripts)
                {
                    RunLog("");
                    RunLog(">>> " + s);
                    if (RunProcess(s, workDir, RunLog) != 0)
                    {
                        RunLog("脚本执行失败，已停止后续脚本: " + s);
                        return 1;
                    }
                }
                return 0;
            }, null);
        }

        private static int RunProcess(string rel, string dir, Action<string> log)
        {
            return RunProcessArgs(rel, "auto", dir, log);
        }

        private static int RunProcessArgs(string rel, string extraArgs, string dir, Action<string> log)
        {
            string path = Path.Combine(dir, rel);
            if (!File.Exists(path)) { log("缺少脚本: " + path); return 1; }
            ProcessStartInfo psi = new ProcessStartInfo("cmd.exe");
            psi.Arguments = "/c \"\"" + path + "\" " + extraArgs + "\"";
            psi.WorkingDirectory = dir;
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            psi.RedirectStandardInput = true;
            psi.RedirectStandardOutput = true;
            psi.RedirectStandardError = true;
            psi.StandardOutputEncoding = Encoding.Default;
            psi.StandardErrorEncoding = Encoding.Default;
            Process p = Process.Start(psi);
            p.StandardInput.Close();
            p.OutputDataReceived += delegate(object s, DataReceivedEventArgs e)
            {
                if (e.Data != null) log(e.Data);
            };
            p.ErrorDataReceived += delegate(object s, DataReceivedEventArgs e)
            {
                if (e.Data != null) log(e.Data);
            };
            p.BeginOutputReadLine();
            p.BeginErrorReadLine();
            p.WaitForExit();
            return p.ExitCode;
        }

        private void SetRunButtons(bool enabled)
        {
            btnInstall.Enabled = enabled;
            btnStart.Enabled = enabled;
            btnStop.Enabled = enabled;
            btnStatus.Enabled = enabled;
            btnInitNow.Enabled = enabled;
            btnSqlInit.Enabled = enabled;
            btnImport.Enabled = enabled;
            if (lblStatus != null)
            {
                lblStatus.Text = enabled ? "●  就绪" : "●  执行中...";
                statusColor = enabled ? Theme.Ok : Theme.Neon;
                lblStatus.ForeColor = statusColor;
            }
            Cursor = enabled ? Cursors.Default : Cursors.WaitCursor;
        }

        private void InstallLog(string s) { Append(txtInstallLog, s); }
        private void RunLog(string s) { Append(txtRunLog, s); }

        // 日志先入队，由 UI 线程一次性合并写入，避免每行一次跨线程投递拖慢界面
        private class LogQueue
        {
            public List<string> Lines = new List<string>();
            public bool Scheduled;
            public int LineCount;   // 已写入控件的行数，避免每次刷写都用 r.Lines.Length 全量统计
        }

        private static readonly object LogSync = new object();
        private static readonly Dictionary<RichTextBox, LogQueue> LogQueues =
            new Dictionary<RichTextBox, LogQueue>();
        private const int MaxLogLines = 5000;
        private const int LogTrimSlack = 300;

        private static void ClearLog(RichTextBox r)
        {
            lock (LogSync)
            {
                LogQueue q;
                if (LogQueues.TryGetValue(r, out q))
                {
                    q.Lines.Clear();
                    q.LineCount = 0;
                    q.Scheduled = false;
                }
            }
            r.Clear();
        }

        private static void Append(RichTextBox r, string s)
        {
            LogQueue q;
            lock (LogSync)
            {
                LogQueue found;
                if (LogQueues.TryGetValue(r, out found)) q = found;
                else { q = new LogQueue(); LogQueues[r] = q; }
                q.Lines.Add(s);
                if (q.Scheduled) return;
                q.Scheduled = true;
            }
            try
            {
                r.BeginInvoke(new Action<RichTextBox>(FlushLog), r);
            }
            catch
            {
                lock (LogSync) { q.Scheduled = false; }
            }
        }

        private static void FlushLog(RichTextBox r)
        {
            List<string> batch;
            LogQueue q;
            lock (LogSync)
            {
                q = LogQueues[r];
                batch = q.Lines;
                q.Lines = new List<string>();
                q.Scheduled = false;
            }
            if (r.IsDisposed || batch.Count == 0) return;

            bool stick = IsLogAtBottom(r);      // 用户往上翻看时不抢滚动条
            int anchor = stick ? -1 : FirstVisibleChar(r);
            int oldSelStart = r.SelectionStart;
            int oldSelLen = r.SelectionLength;
            r.SelectionStart = r.TextLength;
            r.SelectionLength = 0;
            int current = -1;
            StringBuilder sb = new StringBuilder();
            foreach (string s in batch)
            {
                int kind = LogKind(s);
                if (kind != current)
                {
                    if (sb.Length > 0)
                    {
                        r.SelectionColor = LogColor(current);
                        r.AppendText(sb.ToString());
                        sb.Length = 0;
                    }
                    current = kind;
                }
                sb.Append(s).Append(Environment.NewLine);
            }
            if (sb.Length > 0)
            {
                r.SelectionColor = LogColor(current);
                r.AppendText(sb.ToString());
            }
            r.SelectionColor = Color.FromArgb(209, 230, 245);
            lock (LogSync) { q.LineCount += batch.Count; }
            int cut = TrimLog(r, q);
            if (cut > 0)
            {
                if (anchor > 0) anchor = Math.Max(1, anchor - cut);
                oldSelStart = Math.Max(0, oldSelStart - cut);
            }
            if (stick)
            {
                r.SelectionStart = r.TextLength;
                r.SelectionLength = 0;
                r.ScrollToCaret();
            }
            else
            {
                // AppendText 会把视图带到末尾：把追加前底部可见的位置滚回去
                if (anchor > 0 && anchor < r.TextLength)
                {
                    r.SelectionStart = anchor;
                    r.SelectionLength = 0;
                    r.ScrollToCaret();
                }
                if (oldSelStart > r.TextLength) oldSelStart = r.TextLength;
                if (oldSelStart + oldSelLen > r.TextLength) oldSelLen = r.TextLength - oldSelStart;
                r.Select(oldSelStart, oldSelLen);
            }
        }

        private static bool IsLogAtBottom(RichTextBox r)
        {
            if (r.TextLength == 0) return true;
            try
            {
                Point p = r.GetPositionFromCharIndex(r.TextLength - 1);
                return p.Y >= 0 && p.Y < r.ClientSize.Height;
            }
            catch { return true; }
        }

        private static int FirstVisibleChar(RichTextBox r)
        {
            try
            {
                int h = r.ClientSize.Height;
                if (h <= 2) return -1;
                return r.GetCharIndexFromPosition(new Point(2, h - 2));
            }
            catch { return -1; }
        }

        private static int LogKind(string s)
        {
            if (s.StartsWith(">>>")) return 0;
            if (s.IndexOf("FAIL") >= 0 || s.IndexOf("失败") >= 0) return 1;
            if (s.IndexOf("OK") >= 0 || s.IndexOf("完成") >= 0) return 2;
            return 3;
        }

        private static Color LogColor(int kind)
        {
            if (kind == 0) return Theme.Accent;
            if (kind == 1) return Color.FromArgb(248, 113, 113);
            if (kind == 2) return Theme.Ok;
            return Color.FromArgb(209, 230, 245);
        }

        // 只读 RichTextBox 上 SelectedText 赋值是空操作，裁剪前要临时关掉 ReadOnly；返回删掉的字符数
        private static int TrimLog(RichTextBox r, LogQueue q)
        {
            int count;
            lock (LogSync) count = q.LineCount;
            if (count <= MaxLogLines + LogTrimSlack) return 0;
            int remove = count - MaxLogLines;
            int index = r.GetFirstCharIndexFromLine(remove);
            if (index <= 0) return 0;
            r.ReadOnly = false;
            try
            {
                r.Select(0, index);
                r.SelectedText = "";
            }
            finally
            {
                r.ReadOnly = true;
            }
            lock (LogSync) q.LineCount = count - remove;
            return index;
        }
    }
}
