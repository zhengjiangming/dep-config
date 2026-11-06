using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Text;
using System.Text.RegularExpressions;

namespace BatAppSetup
{
    public static class PathHelper
    {
        public static string Root
        {
            get
            {
                string p = AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\');
                if (Path.GetFileName(p).ToLowerInvariant() == "installer")
                    p = Path.GetDirectoryName(p);
                return p;
            }
        }
        public static string ConfDir(string dir) { return Path.Combine(dir, "conf"); }
        public static string DeployPath(string dir) { return Path.Combine(ConfDir(dir), "deploy.properties"); }
        public static string DefaultsPath(string dir) { return Path.Combine(ConfDir(dir), "deploy-defaults.properties"); }
        public static string ComponentsPath(string dir) { return Path.Combine(ConfDir(dir), "components.properties"); }
        public static string InstallStepsPath(string dir) { return Path.Combine(ConfDir(dir), "install-steps.cfg"); }
        public static string AppsPath(string dir) { return Path.Combine(ConfDir(dir), "apps.cfg"); }
        public static string ServiceHostsPath(string dir) { return Path.Combine(ConfDir(dir), "service-hosts.cfg"); }
        public static string NginxPath(string dir) { return Path.Combine(ConfDir(dir), @"nginx\nginx.conf"); }
    }

    public class KeyGroup
    {
        public string Title;
        public string[] Keys;
        public KeyGroup(string title, string[] keys) { Title = title; Keys = keys; }
    }

    public class DeployConfig
    {
        // 界面分组，同时决定 deploy.properties 的写入顺序
        public static readonly KeyGroup[] Groups = new KeyGroup[]
        {
            new KeyGroup("基础", new string[] { "DEPLOY_HOST", "INFRA_JDK" }),
            new KeyGroup("端口", new string[] { "MYSQL_PORT", "PG_PORT", "REDIS_PORT",
                "MINIO_PORT", "MINIO_CONSOLE_PORT", "MQ_NAMESRV_PORT", "MQ_BROKER_PORT", "MQ_HA_PORT",
                "NACOS_PORT", "GEOSERVER_PORT", "NGINX_PORT" }),
            new KeyGroup("账号密码", new string[] { "MYSQL_USER", "MYSQL_PWD", "PG_USER", "PG_PWD",
                "REDIS_PWD", "MINIO_USER", "MINIO_PWD", "NACOS_USER", "NACOS_PWD" }),
            new KeyGroup("Nacos 命名", new string[] { "NACOS_NAMESPACE", "NACOS_GROUP", "NACOS_PROFILE" }),
            new KeyGroup("组件主机（空 = DEPLOY_HOST）", new string[] { "MYSQL_HOST", "PG_HOST",
                "REDIS_HOST", "MINIO_HOST", "MQ_HOST", "NACOS_HOST", "GEOSERVER_HOST", "NGINX_HOST" }),
            new KeyGroup("本机启动开关（1 本机 / 0 远程）", new string[] { "START_MYSQL", "START_PG",
                "START_REDIS", "START_MINIO", "START_MQ", "START_NACOS", "START_GEOSERVER", "START_NGINX" }),
            new KeyGroup("数据目录（空 = 安装目录\\data）", new string[] { "DATA_DIR", "LOG_DIR",
                "MYSQL_DATA_DIR", "PG_DATA_DIR", "MQ_DATA_DIR", "MINIO_DATA_DIR", "GEOSERVER_DATA_DIR",
                "NODE_OUT_DIR" }),
            new KeyGroup("配置文件（空 = 组件自带路径）", new string[] { "MYSQL_CNF", "REDIS_CNF",
                "MQ_BROKER_CNF", "NGINX_CONF", "NACOS_CONF_DIR",
                "CURL_EXE", "VCREDIST_EXE", "POWERSHELL_EXE", "FIREWALL_RULE_NAME" }),
            new KeyGroup("等待超时（秒）", new string[] { "WAIT_MYSQL_SEC", "WAIT_PG_SEC", "WAIT_REDIS_SEC",
                "WAIT_MINIO_SEC", "WAIT_MQ_NS_SEC", "WAIT_MQ_BROKER_SEC", "WAIT_NACOS_SEC",
                "WAIT_GEOSERVER_SEC", "WAIT_NGINX_SEC", "WAIT_APP_SEC", "WAIT_NACOS_HTTP_SEC",
                "HTTP_TIMEOUT_SEC", "IMPORT_TIMEOUT_SEC", "SCRIPT_TIMEOUT_SEC" }),
            new KeyGroup("JVM", new string[] { "JVM_BASE", "JDK17_OPENS", "NACOS_JVM_XMS", "NACOS_JVM_XMX",
                "NACOS_JVM_XMN", "NACOS_JAVA_TOOL_OPTIONS", "NACOS_EXTRA_OPTS" }),
            new KeyGroup("运行", new string[] { "KILL_PROC_LIST" })
        };

        // 界面在键名后面显示的中文说明，避免只看英文键名看不懂
        private static readonly Dictionary<string, string> Hints = BuildHints();
        private static Dictionary<string, string> BuildHints()
        {
            Dictionary<string, string> d = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            d["DEPLOY_HOST"] = "部署主机 IP 或域名";
            d["INFRA_JDK"] = "基础设施 JDK 版本（17/21）";
            d["MYSQL_PORT"] = "MySQL 端口";
            d["PG_PORT"] = "PostgreSQL 端口";
            d["REDIS_PORT"] = "Redis 端口";
            d["MINIO_PORT"] = "MinIO 服务端口";
            d["MINIO_CONSOLE_PORT"] = "MinIO 控制台端口";
            d["MQ_NAMESRV_PORT"] = "RocketMQ NameServer 端口";
            d["MQ_BROKER_PORT"] = "RocketMQ Broker 端口";
            d["MQ_HA_PORT"] = "RocketMQ 主从同步端口";
            d["NACOS_PORT"] = "Nacos 端口";
            d["GEOSERVER_PORT"] = "GeoServer 端口";
            d["NGINX_PORT"] = "Nginx 端口";
            d["MYSQL_USER"] = "MySQL 用户名";
            d["MYSQL_PWD"] = "MySQL 密码";
            d["PG_USER"] = "PostgreSQL 用户名";
            d["PG_PWD"] = "PostgreSQL 密码";
            d["REDIS_PWD"] = "Redis 密码（空 = 不启用认证）";
            d["MINIO_USER"] = "MinIO 账号";
            d["MINIO_PWD"] = "MinIO 密码";
            d["NACOS_USER"] = "Nacos 用户名";
            d["NACOS_PWD"] = "Nacos 密码";
            d["NACOS_NAMESPACE"] = "Nacos 命名空间";
            d["NACOS_GROUP"] = "Nacos 分组";
            d["NACOS_PROFILE"] = "Nacos 环境标识";
            d["MYSQL_HOST"] = "MySQL 主机";
            d["PG_HOST"] = "PostgreSQL 主机";
            d["REDIS_HOST"] = "Redis 主机";
            d["MINIO_HOST"] = "MinIO 主机";
            d["MQ_HOST"] = "RocketMQ 主机";
            d["NACOS_HOST"] = "Nacos 主机";
            d["GEOSERVER_HOST"] = "GeoServer 主机";
            d["NGINX_HOST"] = "Nginx 主机";
            d["START_MYSQL"] = "本机启动 MySQL";
            d["START_PG"] = "本机启动 PostgreSQL";
            d["START_REDIS"] = "本机启动 Redis";
            d["START_MINIO"] = "本机启动 MinIO";
            d["START_MQ"] = "本机启动 RocketMQ";
            d["START_NACOS"] = "本机启动 Nacos";
            d["START_GEOSERVER"] = "本机启动 GeoServer";
            d["START_NGINX"] = "本机启动 Nginx";
            d["DATA_DIR"] = "数据根目录";
            d["LOG_DIR"] = "日志根目录";
            d["MYSQL_DATA_DIR"] = "MySQL 数据目录";
            d["PG_DATA_DIR"] = "PostgreSQL 数据目录";
            d["MQ_DATA_DIR"] = "RocketMQ 数据目录";
            d["MINIO_DATA_DIR"] = "MinIO 数据目录";
            d["GEOSERVER_DATA_DIR"] = "GeoServer 数据目录";
            d["NODE_OUT_DIR"] = "节点产物目录";
            d["MYSQL_CNF"] = "MySQL 配置文件";
            d["REDIS_CNF"] = "Redis 配置文件";
            d["MQ_BROKER_CNF"] = "Broker 配置模板";
            d["NGINX_CONF"] = "Nginx 配置模板";
            d["NACOS_CONF_DIR"] = "Nacos 配置目录";
            d["CURL_EXE"] = "curl.exe 路径";
            d["VCREDIST_EXE"] = "VC++ 运行库安装包";
            d["POWERSHELL_EXE"] = "PowerShell 路径";
            d["FIREWALL_RULE_NAME"] = "防火墙规则名称";
            d["WAIT_MYSQL_SEC"] = "等待 MySQL 启动（秒）";
            d["WAIT_PG_SEC"] = "等待 PostgreSQL 启动（秒）";
            d["WAIT_REDIS_SEC"] = "等待 Redis 启动（秒）";
            d["WAIT_MINIO_SEC"] = "等待 MinIO 启动（秒）";
            d["WAIT_MQ_NS_SEC"] = "等待 NameServer 启动（秒）";
            d["WAIT_MQ_BROKER_SEC"] = "等待 Broker 启动（秒）";
            d["WAIT_NACOS_SEC"] = "等待 Nacos 启动（秒）";
            d["WAIT_GEOSERVER_SEC"] = "等待 GeoServer 启动（秒）";
            d["WAIT_NGINX_SEC"] = "等待 Nginx 启动（秒）";
            d["WAIT_APP_SEC"] = "等待微服务启动（秒）";
            d["WAIT_NACOS_HTTP_SEC"] = "等待 Nacos HTTP 就绪（秒）";
            d["HTTP_TIMEOUT_SEC"] = "HTTP 检查超时（秒）";
            d["IMPORT_TIMEOUT_SEC"] = "导入配置超时（秒）";
            d["SCRIPT_TIMEOUT_SEC"] = "安装脚本超时（秒，超时强制结束）";
            d["JVM_BASE"] = "通用 JVM 参数";
            d["JDK17_OPENS"] = "JDK17 模块开放参数";
            d["NACOS_JVM_XMS"] = "Nacos 初始堆大小";
            d["NACOS_JVM_XMX"] = "Nacos 最大堆大小";
            d["NACOS_JVM_XMN"] = "Nacos 新生代大小";
            d["NACOS_JAVA_TOOL_OPTIONS"] = "Nacos 工具参数";
            d["NACOS_EXTRA_OPTS"] = "Nacos 其他参数";
            d["KILL_PROC_LIST"] = "允许强制结束的进程名";
            d["JDK17_HOME"] = "JDK17 目录";
            d["JDK21_HOME"] = "JDK21 目录";
            d["MYSQL_HOME"] = "MySQL 目录";
            d["PG_HOME"] = "PostgreSQL 目录";
            d["REDIS_HOME"] = "Redis 目录";
            d["ROCKETMQ_HOME"] = "RocketMQ 目录";
            d["MINIO_HOME"] = "MinIO 目录";
            d["NACOS_HOME"] = "Nacos 目录";
            d["GEOSERVER_HOME"] = "GeoServer 目录";
            d["NGINX_HOME"] = "Nginx 目录";
            d["APPS_DIR"] = "微服务 jar 目录";
            d["ENGINE_JAR"] = "规则引擎 jar";
            return d;
        }

        public static string Hint(string key)
        {
            return Hints.ContainsKey(key) ? Hints[key] : "";
        }

        public static readonly string[] Keys = FlattenKeys();

        // 目录类参数：浏览按钮选择文件夹
        public static readonly string[] DirKeys = new string[] { "DATA_DIR", "LOG_DIR", "MYSQL_DATA_DIR",
            "PG_DATA_DIR", "MQ_DATA_DIR", "MINIO_DATA_DIR", "GEOSERVER_DATA_DIR", "NODE_OUT_DIR",
            "NACOS_CONF_DIR" };

        // 文件类参数：浏览按钮选择文件
        public static readonly string[] FileKeys = new string[] { "MYSQL_CNF", "REDIS_CNF",
            "MQ_BROKER_CNF", "NGINX_CONF",
            "CURL_EXE", "VCREDIST_EXE", "POWERSHELL_EXE" };

        private static string[] FlattenKeys()
        {
            List<string> list = new List<string>();
            foreach (KeyGroup g in Groups)
                foreach (string k in g.Keys) list.Add(k);
            return list.ToArray();
        }

        private static readonly HashSet<string> KeySet = BuildKeySet();
        private static HashSet<string> BuildKeySet()
        {
            HashSet<string> set = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (string k in Keys) set.Add(k);
            return set;
        }

        private Dictionary<string, string> map = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        private List<string> extras = new List<string>();

        public string Get(string key) { return map.ContainsKey(key) ? map[key] : ""; }
        public void Set(string key, string val) { map[key] = val == null ? "" : val; }

        // 把文件里的自定义键（非界面可编辑项）原样带过去，避免保存时丢失
        public void CopyExtrasFrom(DeployConfig src)
        {
            if (src == null) return;
            foreach (string key in src.extras)
            {
                Set(key, src.Get(key));
                if (!extras.Contains(key)) extras.Add(key);
            }
        }

        private static DeployConfig LoadFile(string file)
        {
            DeployConfig cfg = new DeployConfig();
            if (!File.Exists(file)) return cfg;
            foreach (string raw in File.ReadAllLines(file))
            {
                string line = raw.Trim();
                if (line.Length == 0 || line.StartsWith("#")) continue;
                int i = line.IndexOf('=');
                if (i <= 0) continue;
                string key = line.Substring(0, i).Trim();
                cfg.Set(key, line.Substring(i + 1).Trim());
                if (!KeySet.Contains(key)) cfg.extras.Add(key);
            }
            return cfg;
        }

        // 只读本机覆盖值（可能为空），用于比较磁盘上的实际配置
        public static DeployConfig Load(string dir)
        {
            return LoadFile(PathHelper.DeployPath(dir));
        }

        // 默认值：conf\deploy-defaults.properties
        public static DeployConfig LoadDefaults(string dir)
        {
            return LoadFile(PathHelper.DefaultsPath(dir));
        }

        // 界面显示用：默认值 + 本机覆盖（空值视为使用默认值）
        public static DeployConfig LoadEffective(string dir)
        {
            DeployConfig cfg = LoadDefaults(dir);
            DeployConfig dep = Load(dir);
            foreach (KeyValuePair<string, string> kv in dep.map)
            {
                if (kv.Value.Trim().Length == 0) continue;
                cfg.Set(kv.Key, kv.Value);
            }
            foreach (string k in dep.extras)
                if (!cfg.extras.Contains(k)) cfg.extras.Add(k);
            return cfg;
        }

        // 空值不写入文件：删除键即恢复 deploy-defaults.properties 中的默认值
        public void Save(string dir)
        {
            StringBuilder sb = new StringBuilder();
            sb.AppendLine("# generated by Setup.exe " + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"));
            sb.AppendLine("# blank value = use conf\\deploy-defaults.properties");
            foreach (string key in Keys)
            {
                string v = Get(key).Trim();
                if (v.Length > 0) sb.AppendLine(key + "=" + v);
            }
            foreach (string key in extras)
            {
                string v = Get(key).Trim();
                if (v.Length > 0) sb.AppendLine(key + "=" + v);
            }
            string file = PathHelper.DeployPath(dir);
            FileOps.WriteAllTextAtomic(file, sb.ToString());
        }
    }

    public class ComponentPath
    {
        public string Key;
        public string Label;
        public string Bundled;
        public ComponentPath(string key, string label, string bundled)
        {
            Key = key;
            Label = label;
            Bundled = bundled;
        }
    }

    public class ComponentsConfig
    {
        public static readonly ComponentPath[] Items = new ComponentPath[]
        {
            new ComponentPath("JDK17_HOME", "JDK 17", @"runtime\jdk17"),
            new ComponentPath("JDK21_HOME", "JDK 21", @"runtime\jdk21"),
            new ComponentPath("MYSQL_HOME", "MySQL", @"infra\mysql"),
            new ComponentPath("PG_HOME", "PostgreSQL", @"infra\postgres"),
            new ComponentPath("REDIS_HOME", "Redis", @"infra\redis"),
            new ComponentPath("ROCKETMQ_HOME", "RocketMQ", @"infra\rocketmq"),
            new ComponentPath("MINIO_HOME", "MinIO", @"infra\minio"),
            new ComponentPath("NACOS_HOME", "Nacos", @"infra\nacos"),
            new ComponentPath("GEOSERVER_HOME", "GeoServer", @"infra\geoserver"),
            new ComponentPath("NGINX_HOME", "Nginx", @"infra\nginx"),
            new ComponentPath("APPS_DIR", "服务 jar 目录（仅 assemble）", @"apps"),
            new ComponentPath("ENGINE_JAR", "规则引擎 jar（仅 assemble）", @"qrule.jar")
        };

        private Dictionary<string, string> map = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

        public string Get(string key) { return map.ContainsKey(key) ? map[key] : ""; }
        public void Set(string key, string val) { map[key] = val == null ? "" : val; }

        // 路径以 \ 结尾时塞进 "..." 会转义掉收尾引号，统一去掉
        public static string TrimSep(string v)
        {
            if (v.Length <= 3) return v;
            return v.TrimEnd('\\', '/');
        }

        public static ComponentsConfig Load(string dir)
        {
            ComponentsConfig cfg = new ComponentsConfig();
            string file = PathHelper.ComponentsPath(dir);
            if (!File.Exists(file)) return cfg;
            foreach (string raw in File.ReadAllLines(file))
            {
                string line = raw.Trim();
                if (line.Length == 0 || line.StartsWith("#")) continue;
                int i = line.IndexOf('=');
                if (i <= 0) continue;
                cfg.Set(line.Substring(0, i).Trim(), TrimSep(line.Substring(i + 1).Trim()));
            }
            return cfg;
        }

        // 保留原有注释和示例行，只替换已填写的键；空值表示使用内置目录
        public void Save(string dir)
        {
            string file = PathHelper.ComponentsPath(dir);
            List<string> outLines = new List<string>();
            HashSet<string> written = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            if (File.Exists(file))
            {
                foreach (string raw in File.ReadAllLines(file))
                {
                    string line = raw.Trim();
                    if (line.Length == 0 || line.StartsWith("#"))
                    {
                        outLines.Add(raw);
                        continue;
                    }
                    int i = line.IndexOf('=');
                    if (i <= 0) { outLines.Add(raw); continue; }
                    string key = line.Substring(0, i).Trim();
                    if (!written.Contains(key) && KnownKey(key))
                    {
                        written.Add(key);
                        string v = TrimSep(Get(key).Trim());
                        if (v.Length == 0) continue;
                        outLines.Add(key + "=" + v);
                    }
                    else
                    {
                        outLines.Add(raw);
                    }
                }
            }
            if (outLines.Count == 0)
            {
                outLines.Add("# =====================================================================");
                outLines.Add("#  Component locations. Empty = bundled folder, spaces in paths are allowed.");
                outLines.Add("# =====================================================================");
            }
            List<string> pending = new List<string>();
            foreach (ComponentPath it in Items)
                if (!written.Contains(it.Key) && Get(it.Key).Trim().Length > 0)
                    pending.Add(it.Key + "=" + TrimSep(Get(it.Key).Trim()));
            if (pending.Count > 0)
            {
                outLines.Add("");
                outLines.Add("# ---------- set by Setup.exe ----------");
                foreach (string l in pending) outLines.Add(l);
            }
            Directory.CreateDirectory(Path.GetDirectoryName(file));
            FileOps.WriteAllTextAtomic(file, string.Join("\r\n", outLines.ToArray()) + "\r\n");
        }

        private static bool KnownKey(string key)
        {
            foreach (ComponentPath it in Items)
                if (string.Equals(it.Key, key, StringComparison.OrdinalIgnoreCase)) return true;
            return false;
        }
    }

    public class InstallStep
    {
        public string Name = "";
        public string Script = "";
        public bool Enabled = true;
        public bool StopOnFail = true;
        public string Description = "";

        public override string ToString()
        {
            return Name + "   " + Script;
        }
    }

    public static class InstallStepsConfig
    {
        // 名称|脚本|默认勾选(1/0)|失败即停止(1/0)|说明
        public static List<InstallStep> Load(string dir)
        {
            List<InstallStep> list = new List<InstallStep>();
            string file = PathHelper.InstallStepsPath(dir);
            if (!File.Exists(file)) return list;
            foreach (string raw in File.ReadAllLines(file))
            {
                string line = raw.Trim();
                if (line.Length == 0 || line.StartsWith("#")) continue;
                string[] p = line.Split('|');
                if (p.Length < 2) continue;
                InstallStep s = new InstallStep();
                s.Name = p[0].Trim();
                s.Script = p[1].Trim();
                if (s.Script.Length == 0) continue;
                s.Enabled = p.Length > 2 ? p[2].Trim() != "0" : true;
                s.StopOnFail = p.Length > 3 ? p[3].Trim() != "0" : true;
                s.Description = p.Length > 4 ? p[4].Trim() : "";
                if (s.Name.Length == 0) s.Name = s.Script;
                list.Add(s);
            }
            return list;
        }
    }

    public class AppEntry
    {
        public string Name = "";
        public string Jar = "";
        public string Port = "";
        public string Jdk = "17";
        public string Jvm = "-Xms256m -Xmx512m";
        public string Extra = "";
        public string Host = "";   // empty = local machine, otherwise node host for distributed services

        public string ToLine()
        {
            return Name + "|" + Jar + "|" + Port + "|" + Jdk + "|" + Jvm + "|" + Extra;
        }
    }

    public class AppsConfig
    {
        public List<AppEntry> Items = new List<AppEntry>();

        public static AppsConfig Load(string dir)
        {
            AppsConfig cfg = new AppsConfig();
            string file = PathHelper.AppsPath(dir);
            if (!File.Exists(file)) return cfg;
            foreach (string raw in File.ReadAllLines(file))
            {
                string line = raw.Trim();
                if (line.Length == 0 || line.StartsWith("#")) continue;
                string[] p = line.Split('|');
                AppEntry e = new AppEntry();
                e.Name = p.Length > 0 ? p[0].Trim() : "";
                e.Jar = p.Length > 1 ? p[1].Trim() : "";
                e.Port = p.Length > 2 ? p[2].Trim() : "";
                e.Jdk = p.Length > 3 ? p[3].Trim() : "17";
                e.Jvm = p.Length > 4 ? p[4].Trim() : "";
                e.Extra = p.Length > 5 ? p[5].Trim() : "";
                e.Host = p.Length > 6 ? p[6].Trim() : "";
                if (e.Jdk.Length == 0) e.Jdk = "17";
                cfg.Items.Add(e);
            }
            string hf = PathHelper.ServiceHostsPath(dir);
            if (File.Exists(hf))
            {
                foreach (string raw in File.ReadAllLines(hf))
                {
                    string line = raw.Trim();
                    if (line.Length == 0 || line.StartsWith("#")) continue;
                    string[] p = line.Split('|');
                    if (p.Length < 2) continue;
                    string name = p[0].Trim();
                    string host = p[1].Trim();
                    foreach (AppEntry e in cfg.Items)
                        if (string.Equals(e.Name, name, StringComparison.OrdinalIgnoreCase))
                        {
                            e.Host = host;
                            break;
                        }
                }
            }
            return cfg;
        }

        public void Save(string dir)
        {
            StringBuilder sb = new StringBuilder();
            sb.AppendLine("# name|jar|port|jdk|jvm opts|extra args");
            sb.AppendLine("# jdk: 17 or 21; order matters");
            foreach (AppEntry e in Items) sb.AppendLine(e.ToLine());

            StringBuilder hb = new StringBuilder();
            hb.AppendLine("# service|host    empty/not listed = this machine; IP/hostname = distributed service node");
            foreach (AppEntry e in Items)
                if (e.Host != null && e.Host.Trim().Length > 0)
                    hb.AppendLine(e.Name + "|" + e.Host.Trim());

            Directory.CreateDirectory(PathHelper.ConfDir(dir));
            FileOps.WriteAllTextAtomic(PathHelper.AppsPath(dir), sb.ToString());
            FileOps.WriteAllTextAtomic(PathHelper.ServiceHostsPath(dir), hb.ToString());
        }
    }

    public class YmlRow
    {
        public string FilePath;
        public string RelPath;
        public int LineIndex;
        public string Indent;
        public string Key;
        public string Value;
        public string Comment;
        public string Original;
        public string Separator = ":";
        public bool IsNew;
        public bool IsDeleted;
    }

    public class CfgItem
    {
        public string Name = "";
        public string Path = "";
        public override string ToString() { return Name.Length > 0 ? Name : Path; }
    }

    public static class ConfigList
    {
        public static string FileOf(string dir) { return Path.Combine(PathHelper.ConfDir(dir), "config-files.cfg"); }

        public static string LoadName(string dir)
        {
            string file = FileOf(dir);
            if (!File.Exists(file)) return "配置文件清单";
            foreach (string raw in File.ReadAllLines(file))
            {
                string line = raw.Trim();
                if (!line.StartsWith("#")) continue;
                int i = line.IndexOf("NAME=", StringComparison.OrdinalIgnoreCase);
                if (i < 0) continue;
                string name = line.Substring(i + 5).Trim();
                if (name.Length > 0) return name;
            }
            return "配置文件清单";
        }

        public static List<CfgItem> LoadItems(string dir)
        {
            string file = FileOf(dir);
            List<CfgItem> list = new List<CfgItem>();
            if (File.Exists(file))
            {
                foreach (string raw in File.ReadAllLines(file))
                {
                    string line = raw.Trim();
                    if (line.Length == 0 || line.StartsWith("#")) continue;
                    CfgItem it = new CfgItem();
                    int bar = line.IndexOf('|');
                    if (bar > 0)
                    {
                        it.Name = line.Substring(0, bar).Trim();
                        it.Path = line.Substring(bar + 1).Trim();
                    }
                    else
                    {
                        it.Path = line;
                    }
                    if (it.Path.Length == 0) continue;
                    bool dup = false;
                    foreach (CfgItem e in list)
                        if (string.Equals(e.Path, it.Path, StringComparison.OrdinalIgnoreCase)) { dup = true; break; }
                    if (!dup) list.Add(it);
                }
            }
            if (list.Count == 0)
            {
                foreach (string s in AutoDetect(dir))
                {
                    CfgItem it = new CfgItem();
                    it.Path = s;
                    list.Add(it);
                }
                SaveItems(dir, "配置文件清单", list);
            }
            return list;
        }

        public static void SaveItems(string dir, string name, List<CfgItem> items)
        {
            StringBuilder sb = new StringBuilder();
            sb.AppendLine("# NAME=" + (name == null ? "" : name.Trim()));
            sb.AppendLine("# config files managed by Setup.exe, first line = default selection");
            sb.AppendLine("# format: 名称|路径   (名称可省略，只写路径)");
            foreach (CfgItem it in items)
            {
                // “名称|路径”只有第一个竖线是分隔符，名称里的竖线会让路径解析错位
                string nm = it.Name == null ? "" : it.Name.Replace("|", "").Trim();
                if (nm.Length > 0)
                    sb.AppendLine(nm + "|" + it.Path);
                else
                    sb.AppendLine(it.Path);
            }
            Directory.CreateDirectory(PathHelper.ConfDir(dir));
            FileOps.WriteAllTextAtomic(FileOf(dir), sb.ToString());
        }

        public static void SaveName(string dir, string name)
        {
            SaveItems(dir, name, LoadItems(dir));
        }

        public static List<string> AutoDetect(string dir)
        {
            List<string> list = new List<string>();
            string conf = PathHelper.ConfDir(dir);
            if (!Directory.Exists(conf)) return list;
            string[] files = Directory.GetFiles(conf, "*.*", SearchOption.AllDirectories);
            foreach (string f in files)
            {
                string ext = Path.GetExtension(f).ToLowerInvariant();
                if (ext != ".yml" && ext != ".yaml" && ext != ".properties" &&
                    ext != ".conf" && ext != ".js" && ext != ".json" &&
                    ext != ".ini" && ext != ".xml") continue;
                list.Add(f.Substring(dir.Length).TrimStart('\\'));
            }
            list.Sort(StringComparer.OrdinalIgnoreCase);
            string rootYml = @"conf\application.yml";
            for (int i = 0; i < list.Count; i++)
            {
                if (string.Equals(list[i], rootYml, StringComparison.OrdinalIgnoreCase))
                {
                    string t = list[i];
                    list.RemoveAt(i);
                    list.Insert(0, t);
                    break;
                }
            }
            return list;
        }
    }

    public static class YmlEditor
    {
        private static readonly Regex LineRx = new Regex(
            @"^(?<ind>[ \t]*)(?<key>[A-Za-z0-9_.\-]+)[ \t]*:[ \t]*(?<val>[^#]*?)(?<cmt>[#].*)?$",
            RegexOptions.Compiled);

        private static readonly Regex PropRx = new Regex(
            @"^(?<ind>[ \t]*)(?<key>[A-Za-z0-9_.\-]+)[ \t]*[=:][ \t]*(?<val>[^#]*?)(?<cmt>[#].*)?$",
            RegexOptions.Compiled);

        public static List<YmlRow> ScanFile(string dir, string rel)
        {
            List<YmlRow> list = new List<YmlRow>();
            if (rel == null || rel.Length == 0) return list;
            string f = Path.IsPathRooted(rel) ? rel : Path.Combine(dir, rel);
            if (!File.Exists(f)) return list;
            bool props = Path.GetExtension(f).ToLowerInvariant() == ".properties";
            string[] lines;
            try { lines = File.ReadAllLines(f); }
            catch { return list; }
            for (int i = 0; i < lines.Length; i++)
            {
                Match m = props ? PropRx.Match(lines[i]) : LineRx.Match(lines[i]);
                if (!m.Success) continue;
                string val = m.Groups["val"].Value.Trim();
                if (!props)
                {
                    if (val.Length == 0) continue;
                    if (val.StartsWith("|") || val.StartsWith(">") || val.StartsWith("{") ||
                        val.StartsWith("[") || val.StartsWith("&") || val.StartsWith("*") ||
                        val.StartsWith("- ")) continue;
                }
                YmlRow r = new YmlRow();
                r.FilePath = f;
                r.RelPath = rel;
                r.LineIndex = i;
                r.Indent = m.Groups["ind"].Value;
                r.Key = m.Groups["key"].Value;
                r.Value = val;
                r.Comment = m.Groups["cmt"].Success ? m.Groups["cmt"].Value : "";
                r.Original = val;
                r.Separator = props ? "=" : ":";
                list.Add(r);
            }
            return list;
        }

        // parse config content held in memory (Nacos online editing, no local file)
        public static List<YmlRow> ScanText(string content, string tag)
        {
            List<YmlRow> list = new List<YmlRow>();
            string[] lines = SplitLines(content);
            bool props = tag != null && tag.ToLowerInvariant().EndsWith(".properties");
            for (int i = 0; i < lines.Length; i++)
            {
                Match m = props ? PropRx.Match(lines[i]) : LineRx.Match(lines[i]);
                if (!m.Success) continue;
                string val = m.Groups["val"].Value.Trim();
                if (!props)
                {
                    if (val.Length == 0) continue;
                    if (val.StartsWith("|") || val.StartsWith(">") || val.StartsWith("{") ||
                        val.StartsWith("[") || val.StartsWith("&") || val.StartsWith("*") ||
                        val.StartsWith("- ")) continue;
                }
                YmlRow r = new YmlRow();
                r.FilePath = tag;
                r.RelPath = tag;
                r.LineIndex = i;
                r.Indent = m.Groups["ind"].Value;
                r.Key = m.Groups["key"].Value;
                r.Value = val;
                r.Comment = m.Groups["cmt"].Success ? m.Groups["cmt"].Value : "";
                r.Original = val;
                r.Separator = props ? "=" : ":";
                list.Add(r);
            }
            return list;
        }

        private static string[] SplitLines(string s)
        {
            if (s == null || s.Length == 0) return new string[0];
            return s.Replace("\r\n", "\n").Replace('\r', '\n').Split('\n');
        }

        public static List<YmlRow> Scan(string dir)
        {
            List<YmlRow> list = new List<YmlRow>();
            string conf = PathHelper.ConfDir(dir);
            if (!Directory.Exists(conf)) return list;
            string[] files = Directory.GetFiles(conf, "*.*", SearchOption.AllDirectories);
            Array.Sort(files, StringComparer.OrdinalIgnoreCase);
            foreach (string f in files)
            {
                string ext = Path.GetExtension(f).ToLowerInvariant();
                if (ext != ".yml" && ext != ".yaml") continue;
                string[] lines;
                try { lines = File.ReadAllLines(f); }
                catch { continue; }
                for (int i = 0; i < lines.Length; i++)
                {
                    Match m = LineRx.Match(lines[i]);
                    if (!m.Success) continue;
                    string val = m.Groups["val"].Value.Trim();
                    if (val.Length == 0) continue;
                    if (val.StartsWith("|") || val.StartsWith(">") || val.StartsWith("{") ||
                        val.StartsWith("[") || val.StartsWith("&") || val.StartsWith("*") ||
                        val.StartsWith("- ")) continue;
                    YmlRow r = new YmlRow();
                    r.FilePath = f;
                    r.RelPath = f.Substring(dir.Length).TrimStart('\\');
                    r.LineIndex = i;
                    r.Indent = m.Groups["ind"].Value;
                    r.Key = m.Groups["key"].Value;
                    r.Value = val;
                    r.Comment = m.Groups["cmt"].Success ? m.Groups["cmt"].Value : "";
                    r.Original = val;
                    list.Add(r);
                }
            }
            return list;
        }

        public static int Save(string dir, List<YmlRow> rows)
        {
            Dictionary<string, List<YmlRow>> byFile = new Dictionary<string, List<YmlRow>>();
            foreach (YmlRow r in rows)
            {
                if (!r.IsNew && !r.IsDeleted && r.Value == r.Original) continue;
                if (!byFile.ContainsKey(r.FilePath)) byFile[r.FilePath] = new List<YmlRow>();
                byFile[r.FilePath].Add(r);
            }
            int count = 0;
            foreach (string f in byFile.Keys)
            {
                string srcText = File.Exists(f) ? File.ReadAllText(f) : "";
                int c = 0;
                string text = BuildText(srcText, byFile[f], out c);
                FileOps.WriteAllTextAtomic(f, text);
                count += c;
            }
            return count;
        }

        // rebuild config content in memory; used by Nacos online editing (no local file)
        public static string BuildText(string content, List<YmlRow> rows, out int count)
        {
            count = 0;
            string[] src = SplitLines(content);
            if (src.Length > 0 && src[src.Length - 1].Length == 0)
            {
                string[] t = new string[src.Length - 1];
                Array.Copy(src, t, t.Length);
                src = t;
            }
            bool[] del = new bool[src.Length];
            Dictionary<int, YmlRow> upd = new Dictionary<int, YmlRow>();
            List<YmlRow> news = new List<YmlRow>();
            foreach (YmlRow r in rows)
            {
                if (!r.IsNew && !r.IsDeleted && r.Value == r.Original) continue;
                if (r.IsDeleted)
                {
                    if (r.LineIndex >= 0 && r.LineIndex < src.Length) del[r.LineIndex] = true;
                    continue;
                }
                if (r.IsNew) { news.Add(r); continue; }
                if (r.LineIndex >= 0 && r.LineIndex < src.Length) upd[r.LineIndex] = r;
            }
            List<string> outLines = new List<string>();
            for (int i = 0; i < src.Length; i++)
            {
                if (del[i]) continue;
                YmlRow r = upd.ContainsKey(i) ? upd[i] : null;
                if (r == null) { outLines.Add(src[i]); continue; }
                string tail = r.Comment.Length > 0 ? " " + r.Comment : "";
                string sep = r.Separator == "=" ? "=" : ": ";
                outLines.Add(r.Indent + r.Key + sep + r.Value + tail);
                r.Original = r.Value;
                count++;
            }
            foreach (YmlRow r in news)
            {
                if (r.Key.Length == 0) continue;
                string sep = r.Separator == "=" ? "=" : ": ";
                outLines.Add(r.Indent + r.Key + sep + r.Value);
                r.IsNew = false;
                r.Original = r.Value;
                count++;
            }
            return string.Join("\r\n", outLines.ToArray()) + "\r\n";
        }
    }

    public class NacosConfigInfo
    {
        public string DataId;
        public string Group;
        public string Type;
    }

    public static class NacosApi
    {
        // 由 Setup.exe 按 deploy.properties 的 IMPORT_TIMEOUT_SEC 设置
        public static int HttpTimeoutMs = 15000;

        public static string BaseUrl(DeployConfig cfg)
        {
            string host = cfg.Get("NACOS_HOST");
            if (host.Length == 0) host = cfg.Get("DEPLOY_HOST");
            if (host.Length == 0) host = "127.0.0.1";
            int port = 8848;
            try { int p = int.Parse(cfg.Get("NACOS_PORT")); if (p > 0) port = p; }
            catch { }
            return "http://" + host + ":" + port + "/nacos";
        }

        public static string Login(string baseUrl, string user, string pwd)
        {
            if (user.Length == 0) return "";
            string resp = Post(baseUrl + "/v1/auth/login",
                "username=" + Uri.EscapeDataString(user) + "&password=" + Uri.EscapeDataString(pwd));
            Match m = Regex.Match(resp, "\"accessToken\"\\s*:\\s*\"([^\"]+)\"");
            return m.Success ? m.Groups[1].Value : "";
        }

        // list all configs in the namespace; group can be empty to search every group
        public static List<NacosConfigInfo> ListConfigs(string baseUrl, string group, string tenant, string token)
        {
            List<NacosConfigInfo> list = new List<NacosConfigInfo>();
            int pageNo = 1;
            while (pageNo <= 20)
            {
                string url = baseUrl + "/v1/cs/configs?search=accurate&dataId=&group="
                    + Uri.EscapeDataString(group) + "&pageNo=" + pageNo + "&pageSize=100";
                if (tenant.Length > 0) url += "&tenant=" + Uri.EscapeDataString(tenant);
                if (token.Length > 0) url += "&accessToken=" + Uri.EscapeDataString(token);
                string json = Get(url);
                if (json == null || json.Length == 0) break;

                MatchCollection ids = Regex.Matches(json, "\"dataId\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"");
                MatchCollection grps = Regex.Matches(json, "\"group\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"");
                MatchCollection types = Regex.Matches(json, "\"type\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"");
                if (ids.Count == 0) break;
                for (int i = 0; i < ids.Count; i++)
                {
                    NacosConfigInfo it = new NacosConfigInfo();
                    it.DataId = Regex.Unescape(ids[i].Groups[1].Value);
                    it.Group = i < grps.Count ? Regex.Unescape(grps[i].Groups[1].Value) : group;
                    it.Type = i < types.Count ? Regex.Unescape(types[i].Groups[1].Value) : "";
                    list.Add(it);
                }

                Match tm = Regex.Match(json, "\"totalCount\"\\s*:\\s*(\\d+)");
                int total = tm.Success ? int.Parse(tm.Groups[1].Value) : 0;
                if (list.Count >= total || ids.Count == 0) break;
                pageNo++;
            }
            return list;
        }

        // "public(1)" or "prod(12) [id=prod]"
        public static List<string> ListNamespaces(string baseUrl, string token)
        {
            List<string> list = new List<string>();
            string url = baseUrl + "/v1/console/namespaces";
            if (token.Length > 0) url += "?accessToken=" + Uri.EscapeDataString(token);
            string json = Get(url);
            if (json == null) return list;
            MatchCollection ids = Regex.Matches(json, "\"namespace\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"");
            MatchCollection names = Regex.Matches(json, "\"namespaceShowName\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"");
            MatchCollection counts = Regex.Matches(json, "\"configCount\"\\s*:\\s*(\\d+)");
            for (int i = 0; i < ids.Count; i++)
            {
                string id = Regex.Unescape(ids[i].Groups[1].Value);
                string name = i < names.Count ? Regex.Unescape(names[i].Groups[1].Value) : id;
                int cnt = i < counts.Count ? int.Parse(counts[i].Groups[1].Value) : 0;
                string s = (name.Length > 0 ? name : "public") + "(" + cnt + ")";
                if (id.Length > 0) s += " [id=" + id + "]";
                list.Add(s);
            }
            return list;
        }

        public static string GetConfig(string baseUrl, string group, string tenant, string dataId, string token)
        {
            string url = baseUrl + "/v1/cs/configs?dataId=" + Uri.EscapeDataString(dataId)
                + "&group=" + Uri.EscapeDataString(group);
            if (tenant.Length > 0) url += "&tenant=" + Uri.EscapeDataString(tenant);
            if (token.Length > 0) url += "&accessToken=" + Uri.EscapeDataString(token);
            return Get(url);
        }

        public static bool Publish(string baseUrl, string group, string tenant, string dataId,
            string type, string content, string token)
        {
            StringBuilder body = new StringBuilder();
            body.Append("dataId=").Append(Uri.EscapeDataString(dataId));
            body.Append("&group=").Append(Uri.EscapeDataString(group));
            body.Append("&content=").Append(Uri.EscapeDataString(content));
            if (type.Length > 0) body.Append("&type=").Append(Uri.EscapeDataString(type));
            if (tenant.Length > 0) body.Append("&tenant=").Append(Uri.EscapeDataString(tenant));
            if (token.Length > 0) body.Append("&accessToken=").Append(Uri.EscapeDataString(token));
            string resp = Post(baseUrl + "/v1/cs/configs", body.ToString());
            return resp != null && resp.Trim().ToLowerInvariant().StartsWith("true");
        }

        private static string Get(string url)
        {
            HttpWebRequest req = (HttpWebRequest)WebRequest.Create(url);
            req.Method = "GET";
            req.Timeout = HttpTimeoutMs;
            req.ReadWriteTimeout = HttpTimeoutMs;
            try
            {
                using (HttpWebResponse resp = (HttpWebResponse)req.GetResponse())
                using (Stream s = resp.GetResponseStream())
                using (StreamReader r = new StreamReader(s, Encoding.UTF8))
                    return r.ReadToEnd();
            }
            catch (WebException ex)
            {
                HttpWebResponse hr = ex.Response as HttpWebResponse;
                if (hr != null && (int)hr.StatusCode == 404) return null;
                throw;
            }
        }

        private static string Post(string url, string body)
        {
            HttpWebRequest req = (HttpWebRequest)WebRequest.Create(url);
            req.Method = "POST";
            req.ContentType = "application/x-www-form-urlencoded";
            req.Timeout = HttpTimeoutMs;
            req.ReadWriteTimeout = HttpTimeoutMs;
            byte[] data = Encoding.UTF8.GetBytes(body);
            req.ContentLength = data.Length;
            using (Stream s = req.GetRequestStream()) s.Write(data, 0, data.Length);
            using (HttpWebResponse resp = (HttpWebResponse)req.GetResponse())
            using (Stream s = resp.GetResponseStream())
            using (StreamReader r = new StreamReader(s, Encoding.UTF8))
                return r.ReadToEnd();
        }
    }

    public class NacosMetaEntry
    {
        public string FileName = "";
        public string DataId = "";
        public string Group = "";
        public string Tenant = "";
    }

    // remembers the original Nacos dataId/group/tenant for every file under conf\nacos
    public static class NacosMeta
    {
        public static string FileOf(string dir)
        {
            return Path.Combine(PathHelper.ConfDir(dir), @"nacos\nacos-meta.cfg");
        }

        public static Dictionary<string, NacosMetaEntry> Load(string dir)
        {
            Dictionary<string, NacosMetaEntry> map =
                new Dictionary<string, NacosMetaEntry>(StringComparer.OrdinalIgnoreCase);
            string file = FileOf(dir);
            if (!File.Exists(file)) return map;
            foreach (string raw in File.ReadAllLines(file))
            {
                string line = raw.Trim();
                if (line.Length == 0 || line.StartsWith("#")) continue;
                string[] p = line.Split('|');
                if (p.Length < 2) continue;
                NacosMetaEntry e = new NacosMetaEntry();
                e.FileName = p[0].Trim();
                e.DataId = p[1].Trim();
                e.Group = p.Length > 2 ? p[2].Trim() : "";
                e.Tenant = p.Length > 3 ? p[3].Trim() : "";
                if (e.FileName.Length > 0) map[e.FileName] = e;
            }
            return map;
        }

        public static void Set(string dir, string fileName, string dataId, string group, string tenant)
        {
            Dictionary<string, NacosMetaEntry> map = Load(dir);
            NacosMetaEntry e = new NacosMetaEntry();
            e.FileName = fileName;
            e.DataId = dataId;
            e.Group = group;
            e.Tenant = tenant;
            map[fileName] = e;
            StringBuilder sb = new StringBuilder();
            sb.AppendLine("# file|dataId|group|tenant");
            foreach (NacosMetaEntry it in map.Values)
                sb.AppendLine(it.FileName + "|" + it.DataId + "|" + it.Group + "|" + it.Tenant);
            string file = FileOf(dir);
            FileOps.WriteAllTextAtomic(file, sb.ToString());
        }
    }

    public static class FileOps
    {
        // do not ship runtime data, build output or the git checkout into an install target
        private static readonly string[] SkipTopDirs = new string[] { "data", "logs", "release", "installer", "nodes" };

        // 先写临时文件再原子替换，避免断电/异常时留下半截配置
        public static void WriteAllTextAtomic(string file, string text)
        {
            if (file == null || file.Length == 0) return;
            string dir = Path.GetDirectoryName(file);
            if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
            string tmp = file + ".tmp";
            File.WriteAllText(tmp, text, new UTF8Encoding(false));
            if (File.Exists(file))
            {
                try { File.Replace(tmp, file, null); }
                catch (Exception)
                {
                    // FAT/网络盘不支持 Replace 时退化为复制替换
                    File.Copy(tmp, file, true);
                    File.Delete(tmp);
                }
            }
            else File.Move(tmp, file);
        }

        public static void CopyPayload(string src, string dst, Action<string> log)
        {
            Directory.CreateDirectory(dst);
            foreach (string d in Directory.GetDirectories(src))
            {
                string name = Path.GetFileName(d);
                if (IsSkipDir(name)) { log("SKIP " + name + @"\"); continue; }
                CopyDir(d, Path.Combine(dst, name), log);
            }
            foreach (string f in Directory.GetFiles(src))
            {
                string name = Path.GetFileName(f);
                if (IsSkipFile(name)) continue;
                File.Copy(f, Path.Combine(dst, name), true);
            }
        }

        private static bool IsSkipDir(string name)
        {
            // .git / .vs / .trae 等隐藏目录不进入安装包
            if (name.StartsWith(".", StringComparison.Ordinal)) return true;
            foreach (string s in SkipTopDirs)
                if (name.Equals(s, StringComparison.OrdinalIgnoreCase)) return true;
            return false;
        }

        private static bool IsSkipFile(string name)
        {
            if (name.EndsWith(".bak", StringComparison.OrdinalIgnoreCase)) return true;
            if (name.Equals("setup_selftest.txt", StringComparison.OrdinalIgnoreCase)) return true;
            if (name.Equals("setup_uittest.txt", StringComparison.OrdinalIgnoreCase)) return true;
            if (name.StartsWith("setup_uicap", StringComparison.OrdinalIgnoreCase)) return true;
            if (name.Equals("Setup_preview.exe", StringComparison.OrdinalIgnoreCase)) return true;
            return false;
        }

        public static void CopyDir(string s, string d, Action<string> log)
        {
            Directory.CreateDirectory(d);
            foreach (string f in Directory.GetFiles(s))
            {
                string name = Path.GetFileName(f);
                if (name.EndsWith(".bak", StringComparison.OrdinalIgnoreCase)) continue;
                if (name.Equals("deploy.properties", StringComparison.OrdinalIgnoreCase) &&
                    File.Exists(Path.Combine(d, name))) continue;
                if (name.Equals("components.properties", StringComparison.OrdinalIgnoreCase) &&
                    File.Exists(Path.Combine(d, name))) continue;
                if (name.Equals("install-steps.cfg", StringComparison.OrdinalIgnoreCase) &&
                    File.Exists(Path.Combine(d, name))) continue;
                if (name.Equals("config-files.cfg", StringComparison.OrdinalIgnoreCase) &&
                    File.Exists(Path.Combine(d, name))) continue;
                if (name.Equals("service-hosts.cfg", StringComparison.OrdinalIgnoreCase) &&
                    File.Exists(Path.Combine(d, name))) continue;
                // 服务清单也属于目标机配置，覆盖安装时保留
                if (name.Equals("apps.cfg", StringComparison.OrdinalIgnoreCase) &&
                    File.Exists(Path.Combine(d, name))) continue;
                // 重装/升级时保留已配置的 Nacos 元数据与 nginx 占位符结果
                if (name.Equals("nacos-meta.cfg", StringComparison.OrdinalIgnoreCase) &&
                    File.Exists(Path.Combine(d, name))) continue;
                if (name.Equals("nginx.conf", StringComparison.OrdinalIgnoreCase) &&
                    File.Exists(Path.Combine(d, name))) continue;
                File.Copy(f, Path.Combine(d, name), true);
            }
            foreach (string sub in Directory.GetDirectories(s))
                CopyDir(sub, Path.Combine(d, Path.GetFileName(sub)), log);
        }
    }
}
