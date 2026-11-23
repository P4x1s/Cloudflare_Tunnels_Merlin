# Cloudflare Tunnel 插件（ASUSGO / koolshare softcenter 版 · 独立版）

面向 **NETGEAR RAX50（Asuswrt-Merlin 386.7_2，带 ASUSGO 软件中心）** 的 Cloudflare Tunnel 内网穿透插件。

**完全独立，无需 Entware / opkg**：插件包内置了匹配 RAX50（博通 BCM6755，armv7l 32 位）的 `cloudflared` 静态二进制，安装即用。通过 Token 远程管理隧道，把局域网服务安全暴露到公网，无需公网 IP。

---

## 一、目录结构（softcenter 标准）

```
cloudflare-tunnel/
├── config.json                          # 插件元数据（软件中心读取）
├── install.sh                           # 安装/卸载入口（软件中心调用，参数 1/0）
├── uninstall.sh                         # 独立卸载入口
├── bin/
│   └── cloudflared-linux-arm            # 内置 armv7l 静态二进制（约 37MB）
├── scripts/
│   └── cloudflaretunnel.sh              # 后台服务与控制脚本
├── webs/
│   └── Module_cloudflaretunnel.asp      # Web 管理页面
├── init.d/
│   └── S99cloudflaretunnel.sh           # 开机自启钩子
└── README.md
```

安装到路由器后的落点：

| 源 | 目标路径 | 说明 |
|----|----------|------|
| `bin/cloudflared-linux-arm` | `/koolshare/bin/cloudflared` | 内置二进制（chmod 755） |
| `scripts/cloudflaretunnel.sh` | `/koolshare/scripts/cloudflaretunnel.sh` | 控制脚本 |
| `webs/Module_cloudflaretunnel.asp` | `/koolshare/webs/Module_cloudflaretunnel.asp` | Web 页面 |
| `init.d/S99cloudflaretunnel.sh` | `/koolshare/init.d/S99cloudflaretunnel.sh` | 开机自启 |
| — | `/koolshare/configs/cloudflaretunnel.conf` | 配置（权限 600） |
| — | `/koolshare/configs/cloudflaretunnel.token` | 隧道 Token 凭证文件（权限 600，仅 root 可读；停止/卸载时自动清理） |
| — | `/koolshare/logs/cloudflared.log` | 运行日志（超过 2MB 自动轮转保留尾部） |
| — | `/var/run/cloudflaretunnel.pid` | PID 文件 |
| — | `/var/spool/cron/crontabs/root` | 追加一条看门狗任务（带 `# cloudflaretunnel-watchdog` 标记，卸载时清除） |
| — | `/tmp/cloudflaretunnel.health` / `.lastrestart` | 健康计数与重启退避时间戳（卸载时清除） |

> **安全说明（v1.1.1+）**：Token 通过 `--token-file` 从凭证文件读取，**不会出现在进程命令行**（避免被 `ps` 窃取）；配置文件回显已做转义，保存优先走 POST，命令请求带 CSRF 缓解头。需 cloudflared ≥ 2025.4.0（内置 2026.11.1 已满足）。

> **稳定性说明（v1.2.2）**：新增看门狗（cron 每 2 分钟执行 `check`），进程退出或隧道持续不健康时自动重启（带 5 分钟冷却，避免重启风暴）；`is_running` 校验进程名防 PID 复用误判；开机等待时间/网络就绪后再启动。日志在 `start` 与每次 `check` 都轮转，长期健康不重启也会被限制在 2MB（可配）以内。覆盖安装/升级会保留 dbus 中已保存的 Token 与开关，旧 local 模式自动迁移为 remote。

> 本插件 **不写入 `/opt`**，也不调用 `opkg`，不依赖任何 Entware 组件。**v1.2.0 起仅支持远程 Token 模式**（原 local 模式未实现，已移除）。

---

## 二、工作原理

```
公网用户 --HTTPS--> Cloudflare Edge ===隧道===> cloudflared @ RAX50 --> LAN 服务
```

1. 在 Cloudflare Zero Trust 创建 **Remotely-managed tunnel**，拿到 Token。
2. 插件把 Token 写入 600 权限凭证文件，用内置二进制执行 `cloudflared tunnel --no-autoupdate run --token-file <file>`，主动连到边缘建立出站隧道（Token 不进入命令行）。
3. 面板配置 Public Hostname（如 `nas.example.com -> http://192.168.50.10:5000`）。
4. 软件中心 Web 页负责启停与状态；配置存于 dbus。
5. 开机脚本等待时间/网络就绪后启动，并安装看门狗 cron；运行中每 2 分钟自检，异常自动恢复。

---

## 三、前置条件

1. RAX50 已刷带 **ASUSGO 软件中心** 的梅林 386.7_2 固件。
2. JFFS 分区有足够空间：内置二进制约 37MB（tar.gz 压缩后约 17.5MB），请确认 `/koolshare` 剩余空间足够。
3. 有 Cloudflare 账号与已接入的域名。

---

## 四、Cloudflare 面板配置

1. <https://one.dash.cloudflare.com/> → **Networks → Tunnels → Create a tunnel**。
2. 类型选 **Cloudflared**（Remotely managed），命名如 `rax50`。
3. 复制 Token（`eyJ...`）。
4. 隧道 → **Public Hostname** 添加路由：
   - Subdomain: `router`；Domain: 你的域名；Service: `HTTP` → `192.168.50.1:80`
5. （可选）**Access → Applications** 加邮件 OTP 认证。

---

## 五、安装与使用

### 方式 A：通过软件中心（推荐）

下载打包好的 `cloudflaretunnel.tar.gz`，在软件中心选择本地安装；安装器 `install.sh` 会被调用（传参 `1`）。

### 方式 B：手动安装

```sh
scp -r cloudflare-tunnel admin@192.168.50.1:/tmp/
ssh admin@192.168.50.1
cd /tmp/cloudflare-tunnel
chmod +x install.sh scripts/cloudflaretunnel.sh init.d/S99cloudflaretunnel.sh bin/cloudflared-linux-arm
./install.sh 1
```

初始化后，在 Web 管理页（软件中心 → Cloudflare Tunnel）中：

- 打开插件开关；粘贴 Token；点“保存并应用”，确认重启即生效；
- 在“运行状态”查看连通性徽标：`HEALTHY`（已连通）、`CONNECTING`（连接中）、`DOWN`（未运行）。

### 命令行控制

```sh
/koolshare/scripts/cloudflaretunnel.sh start|stop|restart|status|health|check|log 100|config|version
```

- `health`：输出隧道连通性（HEALTHY / CONNECTING / ERROR / UNKNOWN / DOWN）。
- `check`：执行一次看门狗检查（供 cron 调用；进程异常或隧道持续不健康时自动重启，带冷却；同时执行日志轮转）。
- `status`：含 `TUNNEL=`、`VERSION=` 字段，便于脚本化监控。

---

## 六、配置存储

用户配置以 dbus 为主（Web 页写入），文件 `/koolshare/configs/cloudflaretunnel.conf` 为辅：

| dbus key | 含义 |
|----------|------|
| `cloudflaretunnel_enable` | 总开关/自启 0/1 |
| `cloudflaretunnel_token` | 远程隧道 Token（敏感） |
| `cloudflaretunnel_loglevel` | 日志级别 |
| `cloudflaretunnel_extra` | 附加参数 |

可选运行参数（写入 `/koolshare/configs/cloudflaretunnel.conf` 覆盖默认值）：
`LOG_MAX_KB`（日志轮转阈值，默认 2048）、`UNHEALTHY_RESTART_MIN`（连续不健康检查次数阈值，默认 5）、`RESTART_COOLDOWN_SEC`（自动重启冷却秒数，默认 300）。

---

## 七、排错

- 面板不健康：先看 `status` 的 `TUNNEL=` 字段，再看 `health` 与 `log 100`；常见原因 Token 错、时间不同步、DNS 被劫持。
- 自动重启过于频繁：调大 `RESTART_COOLDOWN_SEC`，或检查是否 Token 失效导致隧道反复 `ERROR`。
- 看门狗未生效：确认 cron 中存在带 `# cloudflaretunnel-watchdog` 标记的任务（`crontab -l`），且 cron 守护进程在运行；部分固件 cron 路径不同需调整 `CRON_FILE`。
- 二进制无法执行：`ls -l /koolshare/bin/cloudflared`，确认权限为 755；`file` 确认是 32 位 ARM（若你的机器实际为 arm64，需换 arm64 二进制）。
- 空间不足：内置二进制约 37MB，日志已限制轮转（默认 2MB，启动与看门狗自检都会检查）；若 JFFS 仍不够，需清理或其他方案。
- Web 页按钮无反应：不同 ASUSGO 固件的 cgi 接口可能不同，asp 已对 `dbus_set.cgi` 做 POST→GET 回退；如仍失败按实际固件调整 ajax URL。

---

## 八、版本记录

- **v1.2.2**：覆盖安装/升级保留已保存的 Token、开关、日志级别与附加参数；旧 local 模式迁移为 remote；继承 v1.2.1 日志轮转补丁。
- **v1.2.1**：修复日志轮转盲点——`check()` 每次自检也轮转日志，覆盖隧道长期健康不重启的场景；版本统一为 1.2.1。
- **v1.2.0**：看门狗自愈、进程身份校验、隧道健康检测、日志轮转、时间/网络就绪等待、配置保存后可选立即生效、状态页连通性展示；移除未实现的 local 模式。
- **v1.1.1**：Token 凭证文件化、XSS/CSRF 加固、凭证脱敏。
- **v1.1.0**：首发，内置二进制、远程 Token 隧道。

> 说明：多隧道管理、本地管理（config.yml）、Access 策略对接、升级机制属于功能扩展，当前版本未包含。
