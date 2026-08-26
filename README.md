<div align="center">

# 🖥️ RustDesk VPS OneClick

**在 Ubuntu / Debian 系统的VPS 上一键部署 RustDesk Server OSS**

![Version](https://img.shields.io/badge/version-1.6.1-2563eb?style=flat-square)
![Ubuntu](https://img.shields.io/badge/Ubuntu-22.04%20%7C%2024.04%20%7C%2026.04-E95420?style=flat-square&logo=ubuntu&logoColor=white)
![Debian](https://img.shields.io/badge/Debian-11%20%7C%2012%20%7C%2013-A81D33?style=flat-square&logo=debian&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?style=flat-square&logo=docker&logoColor=white)

✅简单、✅方便、✅可维护。自动安装RustDesk所需的所有依赖，包括 `Docker`/ `hbbs` / `hbbr`，持久保存密钥，并提供状态、升级、重启、日志和完整卸载命令。

</div>

## 目录

- [RustDesk 是什么](#rustdesk-是什么)
- [功能特点](#功能特点)
- [适用系统](#适用系统)
- [安装前准备](#安装前准备)
- [一键安装](#一键安装)
- [配置 RustDesk 客户端](#配置-rustdesk-客户端)
- [管理命令](#管理命令)
- [升级与维护](#升级与维护)
- [完整卸载](#完整卸载)
- [常见问题](#常见问题)

## RustDesk 是什么

[RustDesk](https://rustdesk.com/) 是一款开源远程桌面软件，可作为 TeamViewer、AnyDesk 等工具的替代方案。自行部署 RustDesk Server 后，设备注册与中继流量可经过自己的 VPS，便于掌控服务地址、密钥和运行数据。

本项目部署的是免费的 **RustDesk Server OSS**：

- `hbbs`：ID 注册、在线状态与连接协调服务；
- `hbbr`：无法建立直连时使用的中继服务；
- Docker Compose：负责容器启动、重启与版本升级；
- `data` 目录：持久保存数据库和服务器密钥。

## 功能特点

- 自动识别 Ubuntu 或 Debian，并使用对应的 Docker 官方软件源；
- 可选择稳定版本或滚动版 `latest`；
- 域名和公网 IPv4 均可使用【✅推荐使用域名部署】；
- 自动部署 `hbbs` / `hbbr`，服务器重启后自动恢复运行；
- 重复安装或升级时保留数据库和 Key；
- 自动添加 UFW 端口规则，但不会擅自启用 UFW；
- 记录首次安装时新增的软件包，便于卸载时一并清理；
- 提供状态、升级、重启、日志和完整卸载命令；
- 完整卸载可删除 RustDesk、Docker、全部 Docker 数据及相关依赖；
- GitHub Actions 自动检查脚本语法。

## 适用系统

| 系统 | 支持版本 | 常用架构 | 说明 |
|---|---|---|---|
| Ubuntu | 22.04 / 24.04 / 26.04 | `amd64`、`arm64` | 推荐使用 LTS |
| Debian | 11 / 12 / 13 | `amd64`、`arm64` | 推荐使用当前稳定版 |

以下系统不会自动安装：CentOS、Rocky Linux、AlmaLinux、Fedora、OpenWrt、Alpine、Kali、Linux Mint，以及不在上表中的 Ubuntu / Debian 版本。

## 安装前准备

你需要：

1. 一台具有公网 IPv4 的全新或可用 VPS；
2. `root` 权限，或者可使用 `sudo` 的账号；
3. 一个已解析到 VPS 公网 IP 的域名；没有域名时也可直接填写公网 IP；
4. 在 VPS 服务商的“安全组 / 云防火墙”中放行下面的端口。

| 端口 | 协议 | 用途 |
|---|---|---|
| 21115 | TCP | NAT 类型测试 |
| 21116 | TCP / UDP | ID 注册、心跳、连接协调与打洞 |
| 21117 | TCP | 中继服务 |
| 21118 | TCP | Web 客户端支持，可选 |
| 21119 | TCP | Web 客户端中继支持，可选 |

> [!NOTE]
> 脚本能配置 VPS 内的 UFW，但无法代替云厂商控制台中的安全组设置。若不用 Web 客户端，可在确认普通客户端工作正常后关闭 21118/TCP 和 21119/TCP。

## 一键安装

先登录 VPS，然后取得 root 权限：

```bash
sudo -i
```

执行一键安装：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/li2282231/RustDesk-VPS-OneClick/main/install.sh)
```

安装时会依次询问：

1. 选择稳定版或滚动版 `latest`，建议直接按回车选稳定版；
2. 输入 RustDesk 域名或 VPS 公网 IPv4；
3. 等待 Docker 和 RustDesk Server 部署完成。

## 配置 RustDesk 客户端

安装结束会显示 `ID Server` 和 `Key`，也可以随时在 VPS 中运行查看：

```bash
rustdesk-status
```

然后打开 RustDesk 客户端的 **设置 → 网络 → ID/中继服务器**：

| 客户端项目 | 填写内容 |
|---|---|
| ID服务器 | 安装时输入的域名或公网 IP |
| 中继服务器 | 可留空 |
| API服务器 | 留空；OSS 版本不需要 |
| Key | `rustdesk-status` 显示的公钥 |

所有需要通过自建服务器互联的 RustDesk 客户端，都必须使用相同的 ID服务器 和 Key。

## 管理命令

所有管理操作建议用 `root` 执行。

| 命令 | 作用 |
|---|---|
| `rustdesk-help` | 显示管理命令帮助 |
| `rustdesk-status` | 查看 Docker、容器、端口、ID Server 和 Key |
| `rustdesk-update` | 检测并更新 RustDesk Server 镜像 |
| `rustdesk-restart` | 重启 `hbbs` / `hbbr` |
| `rustdesk-logs` | 实时查看最近 200 行日志，按 `Ctrl+C` 退出 |
| `rustdesk-uninstall` | 完整删除 RustDesk、Docker、Docker 数据和相关依赖 |

主要文件位置：

| 路径 | 内容 |
|---|---|
| `/opt/rustdesk/docker-compose.yml` | Docker Compose 配置 |
| `/opt/rustdesk/data/` | 数据库与密钥，最重要 |
| `/opt/rustdesk/domain.txt` | ID Server 地址 |
| `/opt/rustdesk/installer-packages.txt` | 本次安装新增的软件包记录 |

## 升级与维护

### 1. 更新 VPS 上的 RustDesk Server

执行：

```bash
rustdesk-update
```

更新只替换 Docker 镜像，不会删除 `/opt/rustdesk/data`，所以服务器 Key 和数据库保持不变。

### 2. 更新 Docker Engine

脚本安装的是 Docker 官方软件源。系统日常更新时，Docker 会随软件包一起更新：

```bash
apt-get update
apt-get upgrade
```

生产环境建议在业务空闲时更新。

### 3. 更新一键安装脚本本身

`rustdesk-update` 只更新 RustDesk Server，不会自动替换 GitHub 中的 `install.sh`。当仓库发布新版脚本后：

1. 查看新版的 `CHANGELOG.md`；
2. 重新运行一键安装命令；
3. 重新选择版本并输入原来的域名或 IP。

重新运行会重建服务配置和管理命令，但不会主动删除 `data` 目录及 Key。

## 完整卸载

运行：

```bash
rustdesk-uninstall
```

这不是普通的“只删 RustDesk”操作。执行后将永久删除：

- RustDesk Server、数据库、密钥和配置；
- Docker Engine、Docker Compose、containerd；
- 本机全部 Docker 容器、镜像、网络和数据卷；
- `/var/lib/docker`、`/var/lib/containerd`、Docker 软件源；
- 本脚本新增的 UFW 端口规则；
- 安装器记录的本次安装新增依赖。

以“尽量恢复到安装前的干净状态”为设计目标。安装器会在安装前后比较系统软件包，并记录本次新增项目，卸载时只针对这些新增依赖和明确的 Docker 软件包进行清理。

卸载前脚本会列出检测到的非 RustDesk 容器。如果安装 RustDesk 之前已经存在 Docker，也会额外提示。只有准确输入 `REMOVE-ALL` 才会继续，其他任何输入都会取消。

> [!CAUTION]
> 完整卸载不会创建备份。如果其他网站、数据库、面板或应用也在使用 Docker，它们会一起停止，相关 Docker 数据也会永久删除。只有确认这台 VPS 的 Docker 专供 RustDesk 使用时才能继续。

VPS 服务商控制台中的安全组/云防火墙不属于系统内部配置，脚本无法替你删除；完整卸载后需要回到服务商控制台手动撤销此前放行的 RustDesk 端口。

## 常见问题

### 安装成功，但客户端连不上

依次检查：

1. `rustdesk-status` 中两个容器是否为运行状态；
2. 21115-21119/TCP 与 21116/UDP 是否已在 VPS 安全组放行；
3. 域名是否解析到当前 VPS 的公网 IP；
4. 客户端的 ID Server 与 Key 是否完全一致；
5. 用 `rustdesk-logs` 查看是否有报错。

### 是否需要 HTTPS 证书？

RustDesk OSS 的核心连接使用自己的端口和协议，不是普通网站，故不需要 TLS 证书。

### 卸载会删除 Docker 吗？

会，`rustdesk-uninstall` 的用途是让一台只为 RustDesk 安装 Docker 的干净 VPS 尽量恢复到安装前状态，因此会删除 Docker 及全部 Docker 数据。执行前会显示高风险提示、列出其他容器，并要求输入 `REMOVE-ALL` 明确确认。

## 参考资料与声明

- [RustDesk Server OSS 官方 Docker 文档](https://rustdesk.com/docs/en/self-host/rustdesk-server-oss/docker/)
- [Docker Engine 官方 Ubuntu 安装文档](https://docs.docker.com/engine/install/ubuntu/)
- [Docker Engine 官方 Debian 安装文档](https://docs.docker.com/engine/install/debian/)
- [GitHub 官方上传文件说明](https://docs.github.com/zh/repositories/working-with-files/managing-files/adding-a-file-to-a-repository)

本项目是非官方社区安装脚本，与 RustDesk 官方无隶属关系。执行任何以 root 权限运行的远程脚本前，请先阅读源码，尤其要理解完整卸载会删除本机全部 Docker 数据。
