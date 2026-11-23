# Cloudflare Tunnel 插件（ASUSGO / koolshare softcenter 版）

面向 **NETGEAR RAX50（Asuswrt-Merlin 386.7_2，带 ASUSGO 软件中心）** 的 Cloudflare Tunnel 内网穿透插件。按 softcenter 标准插件规范组织，安装后可在路由器 Web 管理页（软件中心）里配置 Token、启停隧道、查看状态与日志。

> 本版本已按 ASUSGO/koolshare softcenter 通用规范重构。参考帖第 2 楼为登录可见内容、无法读取，因此采用社区通用的 `/koolshare` 路径 + dbus 配置体系。若你的固件有专属差异，请在 Web 页/脚本里微调路径与 cgi 接口。

---

## 一、目录结构（softcenter 标准）

```
cloudflare-tunnel/
├── config.json                          # 插件元数据（软件中心读取）
├── install.sh                           # 安装/卸载入口（软件中心调用，参数 1/0）
├── scripts/
│   └── cloudflaretunnel.sh              # 后台服务与控制脚本
├── webs/
│   └── Module_cloudflaretunnel.asp      # Web 管理页面
└── init.d/
    └── S99cloudflaretunnel.sh           # 开机自启钩子
```

安装到路由器后的落点：

| 源 | 目标路径 | 说明 |
|----|----------|------|
| `install.sh` | 软件中心临时目录 | 安装器 |
| `scripts/cloudflaretunnel.sh` | `/koolshare/scripts/cloudflaretunnel.sh` | 控制脚本 |
| `webs/Module_cloudflaretunnel.asp` | `/koolshare/webs/Module_cloudflaretunnel.asp` | Web 页面 |
| `init.d/S99cloudflaretunnel.sh` | `/koolshare/init.d/S99cloudflaretunnel.sh` | 开机自启 |
| — | `/koolshare/configs/cloudflaretunnel.conf` | 配置（权限 600） |
| — | `/var/run/cloudflaretunnel.pid` | PID 文件 |
| — | `/opt/var/log/cloudflared.log` | 运行日志 |
| — | `/opt/bin/cloudflared` | opkg 安装的隧道程序 |

---

## 二、工作原理

```
公网用户 --HTTPS--> Cloudflare Edge ===隧道===> cloudflared @ RAX50 --> LAN 服务
```

1. 在 Cloudflare Zero Trust 创建 **Remotely-managed tunnel**，拿到 Token。
2. 插件在路由器上执行 `cloudflared tunnel run --token <TOKEN>`，主动连到边缘建立出站隧道。
3. 面板配置 Public Hostname（如 `nas.example.com -> http://192.168.50.10:5000`）。
4. 软件中心 Web 页负责启停与状态；`config.json` 描述元数据；dbus 存用户配置。

---

## 三、前置条件

1. RAX50 已刷带 **ASUSGO 软件中心** 的梅林 386.7_2 固件。
2. 已安装 **Entware**（`/opt` 可写，`opkg` 可用）。插件会尝试 `opkg install cloudflared`。
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

将整个 `cloudflare-tunnel/` 目录打包为 `cloudflaretunnel.tar.gz`，在软件中心选择本地安装；安装器 `install.sh` 会被调用（传参 `1`）。

### 方式 B：手动 installation

```sh
scp -r cloudflare-tunnel admin@192.168.50.1:/tmp/
ssh admin@192.168.50.1
cd /tmp/cloudflare-tunnel
chmod +x install.sh scripts/cloudflaretunnel.sh init.d/S99cloudflaretunnel.sh
./install.sh 1
```

初始化后，在 Web 管理页（软件中心 → Cloudflare Tunnel）中：

- 打开插件开关；
- 选“远程管理（Token）”；
- 粘贴 Token；
- 保存 → 启动；
- 在“运行状态”查看，面板隧道显示 HEALTHY 即成功。

### 命令行控制

```sh
/koolshare/scripts/cloudflaretunnel.sh start|stop|restart|status|log 100|config|version
```

---

## 六、配置存储

用户配置以 dbus 为主（Web 页写入），文件 `/koolshare/configs/cloudflaretunnel.conf` 为辅（脚本读取时 dbus 覆盖文件）：

| dbus key | 含义 |
|----------|------|
| `cloudflaretunnel_enable` | 总开关/自启 0/1 |
| `cloudflaretunnel_mode` | `remote` / `local` |
| `cloudflaretunnel_token` | 远程隧道 Token（敏感） |
| `cloudflaretunnel_name` | 本地模式隧道名 |
| `cloudflaretunnel_loglevel` | 日志级别 |
| `cloudflaretunnel_extra` | 附加参数 |

---

## 七、排错

- 面板不健康：先看 `status`，再看 `log 100`；常见原因 Token 错、时间不同步、DNS 被劫持。
- `opkg install cloudflared` 失败：先 `opkg update`，确认 Entware 源支持 armv7。
- Web 页按钮无反应：不同 ASUSGO 固件的 cgi 接口可能不同（如 `softcenter_cmd.cgi` / `dbus_set.cgi`），按实际固件调整 `Module_cloudflaretunnel.asp` 中的 ajax URL。

---

## 八、后续可优化（待你反馈）

- 适配你固件实际的 cgi 接口与菜单注册字段（需你提供真实插件的 config.json / asp 片段）。
- 本地管理隧道（config.yml + credentials JSON）。
- 多隧道管理、断线看门狗、Access 策略对接。
- 打包为软件中心可直接安装的 tar.gz 并补图标。
