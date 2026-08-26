# 更新记录

本项目使用 `主版本.次版本.修订号` 的版本格式。

## [1.6.1] - 2026-08-26

### 调整

- 移除全部自动备份功能；
- 移除 `rustdesk-backup` 管理命令；
- 更新镜像、重复安装和卸载前均不再自动创建备份；
- 首次安装时记录脚本新增的软件包；
- `rustdesk-uninstall` 改为完整卸载模式；
- 完整卸载将删除 RustDesk、Docker、containerd、全部 Docker 容器/镜像/卷/网络、Docker 数据目录、软件源及本脚本新增的依赖；
- 卸载前显示不可恢复的高风险提示，并列出检测到的非 RustDesk 容器；
- 安装 RustDesk 前已经存在 Docker 时，卸载界面会增加额外警告；
- 必须准确输入 `REMOVE-ALL` 才会执行完整卸载。

## [1.6.0] - 2026-08-26

### 新增

- 正式支持 Debian 11、12、13；
- 支持 Ubuntu 22.04、24.04、26.04；
- 根据系统自动配置 Ubuntu 或 Debian 的 Docker 官方软件源；
- 新增 `rustdesk-backup`、`rustdesk-restart`、`rustdesk-logs`、`rustdesk-help`；
- 覆盖旧配置和更新镜像前自动备份；
- GitHub Actions 自动执行 Bash 语法检查和 ShellCheck 错误检查。

### 优化

- 使用更严格的 Bash 错误处理；
- Docker Hub 请求加入失败检查、超时和重试；
- 支持使用域名或公网 IPv4，并将地址写入 `hbbs` 的 Relay 配置；
- Compose 配置先验证、拉取成功后再替换；
- 重复运行时保留 `/opt/rustdesk/data` 中的数据库和 Key；
- 卸载前默认创建备份，卸载后保留备份和 Docker。

### 兼容说明

- 可从 v1.5.4 直接重新运行升级；
- 原始 v1.5.4 文件保存在 `legacy/` 目录，仅用于对照，不建议新安装使用。

## [1.5.4]

- 初始完整安装版；
- 支持 Docker 部署 `hbbs` / `hbbr`；
- 提供状态、更新和卸载命令；
- 仅使用 Ubuntu Docker 软件源，不兼容标准 Debian 安装流程。
