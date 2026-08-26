<div align="center">

# 🖥️ RustDesk VPS OneClick

**在 Ubuntu / Debian VPS 上一键部署 RustDesk Server OSS**

![Version](https://img.shields.io/badge/version-1.6.1-2563eb?style=flat-square)
![Ubuntu](https://img.shields.io/badge/Ubuntu-22.04%20%7C%2024.04%20%7C%2026.04-E95420?style=flat-square&logo=ubuntu&logoColor=white)
![Debian](https://img.shields.io/badge/Debian-11%20%7C%2012%20%7C%2013-A81D33?style=flat-square&logo=debian&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?style=flat-square&logo=docker&logoColor=white)

简单、可重复、方便维护。自动安装 Docker，部署 `hbbs` / `hbbr`，持久保存密钥，并提供状态、升级、重启、日志和完整卸载命令。

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
- [上传到 GitHub](#上传到-github)
- [以后如何维护仓库](#以后如何维护仓库)
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
- 域名和公网 IPv4 均可使用；
- 自动部署 `hbbs` / `hbbr`，服务器重启后自动恢复；
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

1. 选择稳定版或滚动版 `latest`，新手直接按回车选稳定版；
2. 输入 RustDesk 域名或 VPS 公网 IPv4；
3. 等待 Docker 和 RustDesk Server 部署完成。

### 更稳妥的运行方式

远程脚本会以 root 权限安装软件。正式使用前，建议先下载并查看内容：

```bash
curl -fsSL https://raw.githubusercontent.com/li2282231/RustDesk-VPS-OneClick/main/install.sh -o install.sh
less install.sh
sudo bash install.sh
```

## 配置 RustDesk 客户端

安装结束会显示 `ID Server` 和 `Key`。也可以随时在 VPS 中运行：

```bash
rustdesk-status
```

然后打开 RustDesk 客户端的 **设置 → 网络 → ID/中继服务器**：

| 客户端项目 | 填写内容 |
|---|---|
| ID Server | 安装时输入的域名或公网 IP |
| Relay Server | 留空 |
| API Server | 留空；OSS 版本不需要 |
| Key | `rustdesk-status` 显示的公钥 |

所有需要通过自建服务器互联的 RustDesk 客户端，都应使用相同的 ID Server 和 Key。

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

“尽量恢复到安装前的干净状态”以 **全新 VPS 首次使用 v1.6.1 安装** 为设计目标。安装器会在安装前后比较系统软件包，并记录本次新增项目，卸载时只针对这些新增依赖和明确的 Docker 软件包进行清理。

卸载前脚本会列出检测到的非 RustDesk 容器。如果安装 RustDesk 之前已经存在 Docker，也会额外提示。只有准确输入 `REMOVE-ALL` 才会继续，其他任何输入都会取消。

> [!CAUTION]
> 完整卸载不会创建备份。如果其他网站、数据库、面板或应用也在使用 Docker，它们会一起停止，相关 Docker 数据也会永久删除。只有确认这台 VPS 的 Docker 专供 RustDesk 使用时才能继续。

VPS 服务商控制台中的安全组/云防火墙不属于系统内部配置，脚本无法替你删除；完整卸载后需要回到服务商控制台手动撤销此前放行的 RustDesk 端口。

## 上传到 GitHub

### 哪种方式更简单？

- **第一次上传：GitHub 网页版更简单。** 本项目文件少，拖入网页即可；
- **以后经常更新：VS Code 更方便。** 可以同时编辑脚本和 README、查看修改记录，再一次提交；
- 如果不熟悉 Git 命令，不必使用终端。VS Code 的“源代码管理”界面已经足够。

### 方法 A：GitHub 网页版，适合第一次上传

1. 登录 GitHub，点击右上角 `+` → **New repository**；
2. 仓库名填写 `RustDesk-VPS-OneClick`；
3. 选择 `Public`；只有公开仓库的 Raw 地址才能让未登录的 VPS 直接下载；
4. 不要勾选自动创建 README、`.gitignore` 或 License；
5. 创建仓库后，点击 **Add file → Upload files**；
6. 把本项目文件拖到上传区，提交说明填写 `Initial release v1.6.1`；
7. 再打开 Raw 安装网址，确认页面显示的是脚本文本，而不是 `404`。

### 方法 B：VS Code，适合长期维护

1. 在 VS Code 中打开整个 `RustDesk-VPS-OneClick` 文件夹；
2. 点击左侧 **源代码管理** 图标；
3. 选择 **初始化存储库**；
4. 暂存全部文件，提交信息填写 `Initial release v1.6.1`；
5. 点击 **发布到 GitHub**，登录账号并选择公开仓库；
6. 以后修改后，在源代码管理中填写本次修改说明，再点提交和同步即可。

GitHub 官方也支持直接在网页中上传文件；网页单文件上传限制为 25 MiB，本项目远小于该限制。

## 以后如何维护仓库

建议采用“小版本、先测试、再发布”的方式：

1. 修改 `install.sh` 顶部的 `SCRIPT_VERSION`，例如 `1.6.1` → `1.6.2`；
2. 同步修改 README 顶部版本徽章；
3. 在 `CHANGELOG.md` 顶部写清楚改了什么；
4. 检查语法：`bash -n install.sh`；
5. 提交到 GitHub 后，确认仓库的 **Actions** 页面显示绿色通过；
6. 先在临时 VPS 上全新安装，再在已有 VPS 上测试重复安装与升级；
7. 测试通过后，在 GitHub 的 **Releases** 页面创建同名版本，例如 `v1.6.1`。

### `main` 与版本标签的区别

- `main` 始终指向最新脚本，适合自己随时获取新版；
- `v1.6.1` 这样的标签内容固定，更适合稳定环境和故障排查。

固定版本安装命令示例：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/li2282231/RustDesk-VPS-OneClick/v1.6.1/install.sh)
```

## 常见问题

### 安装成功，但客户端连不上

依次检查：

1. `rustdesk-status` 中两个容器是否为运行状态；
2. 21115-21119/TCP 与 21116/UDP 是否已在 VPS 安全组放行；
3. 域名是否解析到当前 VPS 的公网 IP；
4. 客户端的 ID Server 与 Key 是否完全一致；
5. 用 `rustdesk-logs` 查看是否有报错。

### 为什么输入了域名，却没有 HTTPS 证书？

RustDesk OSS 的核心连接使用自己的端口和协议，不是普通网站。本脚本会把域名配置为 ID / Relay 服务地址，但不会安装网站、反向代理或 TLS 证书。

### 卸载会删除 Docker 吗？

会。`rustdesk-uninstall` 的用途是让一台只为 RustDesk 安装 Docker 的干净 VPS 尽量恢复到安装前状态，因此会删除 Docker 及全部 Docker 数据。执行前会显示高风险提示、列出其他容器，并要求输入 `REMOVE-ALL` 明确确认。

### 可以从旧版 v1.5.4 直接运行新版吗？

可以。新版继续使用 `/opt/rustdesk/data`，重新运行安装器时会保留原有 Key。新版不会自动创建备份。但旧版没有记录安装前的软件包状态，因此从 v1.5.4 升级的 VPS 在完整卸载后，可能仍留下少量无法安全判断来源的系统依赖；精准清理由 v1.6.1 全新安装开始生效。

## 参考资料与声明

- [RustDesk Server OSS 官方 Docker 文档](https://rustdesk.com/docs/en/self-host/rustdesk-server-oss/docker/)
- [Docker Engine 官方 Ubuntu 安装文档](https://docs.docker.com/engine/install/ubuntu/)
- [Docker Engine 官方 Debian 安装文档](https://docs.docker.com/engine/install/debian/)
- [GitHub 官方上传文件说明](https://docs.github.com/zh/repositories/working-with-files/managing-files/adding-a-file-to-a-repository)

本项目是非官方社区安装脚本，与 RustDesk 官方无隶属关系。执行任何以 root 权限运行的远程脚本前，请先阅读源码，尤其要理解完整卸载会删除本机全部 Docker 数据。
