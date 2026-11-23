# Cloudflare Tunnels for Asuswrt-Merlin (ASUSGO softcenter)

Cloudflare Tunnel 内网穿透插件，面向 NETGEAR RAX50（Asuswrt-Merlin 386.7_2 + ASUSGO 软件中心）。

**完全独立，无需 Entware / opkg**：插件包内置匹配 RAX50（博通 BCM6755，armv7l 32 位）的 `cloudflared` 静态二进制，安装即用。通过 Token 远程管理隧道，将局域网服务安全暴露到公网，无需公网 IP。

## 仓库结构

```
.
├── dist/
│   └── cloudflaretunnel.tar.gz          # 软件中心可直接安装的插件包（含内置二进制）
└── plugin/                               # 插件源码
    ├── config.json                       # 插件元数据
    ├── install.sh                        # 安装/卸载入口
    ├── uninstall.sh                      # 独立卸载入口
    ├── bin/
    │   └── cloudflared-linux-arm         # 内置 armv7l 静态二进制
    ├── scripts/
    │   └── cloudflaretunnel.sh           # 控制脚本
    ├── webs/
    │   └── Module_cloudflaretunnel.asp   # Web 管理页面
    ├── init.d/
    │   └── S99cloudflaretunnel.sh        # 开机自启
    └── README.md                         # 插件详细说明
```

## 快速安装

1. 下载 [dist/cloudflaretunnel.tar.gz](dist/cloudflaretunnel.tar.gz)（约 17.5MB）。
2. 路由器 Web 管理页 → 软件中心 → 本地安装 → 选择该包。
3. 安装后在「Cloudflare Tunnel」页面启用插件、粘贴 Zero Trust 的隧道 Token、启动。
4. Cloudflare 面板将隧道状态显示为 HEALTHY 即成功。

> 确认 JFFS 有足够空间（内置二进制约 37MB，压缩后约 17.5MB）。本插件不写入 /opt，不调用 opkg。

## 命令行控制

```sh
/koolshare/scripts/cloudflaretunnel.sh start|stop|restart|status|log 100|config|version
```

详细配置与排错见 [plugin/README.md](plugin/README.md)。

## 说明

插件按 ASUSGO/koolshare softcenter 通用规范实现（`/koolshare` 路径 + dbus 配置）。
不同固件的 cgi 接口可能略有差异，如遇 Web 页按钮无反应，请按实际固件调整 asp 中的接口地址。
