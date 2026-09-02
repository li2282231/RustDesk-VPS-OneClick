#!/usr/bin/env bash
# RustDesk VPS OneClick v1.6.2
# Supports officially maintained Ubuntu and Debian releases.

set -Eeuo pipefail

readonly SCRIPT_VERSION="1.6.2"
readonly INSTALL_DIR="/opt/rustdesk"
readonly DATA_DIR="${INSTALL_DIR}/data"
readonly COMPOSE_FILE="${INSTALL_DIR}/docker-compose.yml"
readonly PRIMARY_DOCKER_IMAGE="ghcr.io/rustdesk/rustdesk-server"
readonly FALLBACK_DOCKER_IMAGE="rustdesk/rustdesk-server"
DOCKER_IMAGE=""

PACKAGE_TRACKING_ACTIVE="0"

trap 'printf "\n[错误] 第 %s 行执行失败，安装已停止。\n" "$LINENO" >&2' ERR

info() {
    printf '\n\033[1;34m[%s]\033[0m %s\n' "$1" "$2"
}

success() {
    printf '\033[1;32m[完成]\033[0m %s\n' "$1"
}

warn() {
    printf '\033[1;33m[注意]\033[0m %s\n' "$1" >&2
}

fail() {
    printf '\033[1;31m[失败]\033[0m %s\n' "$1" >&2
    exit 1
}

prompt() {
    local message="$1"
    if [[ -r /dev/tty ]]; then
        IFS= read -r -p "$message" REPLY </dev/tty
    else
        IFS= read -r -p "$message" REPLY
    fi
}

require_root() {
    [[ "${EUID}" -eq 0 ]] || fail "请使用 root 运行。可先执行 sudo -i，再运行安装命令。"
}

detect_system() {
    [[ -r /etc/os-release ]] || fail "找不到 /etc/os-release，无法识别系统。"
    # shellcheck disable=SC1091
    . /etc/os-release

    OS_ID="${ID:-}"
    OS_VERSION="${VERSION_ID:-}"
    OS_NAME="${PRETTY_NAME:-${OS_ID} ${OS_VERSION}}"

    case "${OS_ID}:${OS_VERSION}" in
        ubuntu:22.04|ubuntu:24.04|ubuntu:26.04|debian:11|debian:12|debian:13)
            ;;
        ubuntu:*|debian:*)
            fail "${OS_NAME} 不在本脚本的官方兼容范围内。"
            ;;
        *)
            fail "仅支持 Ubuntu 22.04/24.04/26.04 或 Debian 11/12/13。当前系统：${OS_NAME}"
            ;;
    esac

    OS_CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
    [[ -n "${OS_CODENAME}" ]] || fail "无法读取系统代号 VERSION_CODENAME。"

    ARCH="$(dpkg --print-architecture)"
    case "${ARCH}" in
        amd64|arm64)
            ;;
        *)
            warn "当前架构为 ${ARCH}。Docker 可能支持，但请先确认 RustDesk Server 镜像提供此架构。"
            ;;
    esac
}

list_installed_packages() {
    dpkg-query -W -f='${db:Status-Abbrev} ${binary:Package}\n' 2>/dev/null \
        | awk '$1 ~ /^ii/ {print $2}' \
        | sort -u
}

prepare_install_state() {
    install -d -m 0755 "${INSTALL_DIR}"

    if [[ ! -f "${INSTALL_DIR}/docker-origin.txt" ]]; then
        if command -v docker >/dev/null 2>&1; then
            printf 'pre-existing\n' >"${INSTALL_DIR}/docker-origin.txt"
        else
            printf 'installed-by-script\n' >"${INSTALL_DIR}/docker-origin.txt"
        fi
    fi

    if [[ ! -f "${INSTALL_DIR}/installer-packages.txt" ]]; then
        if [[ ! -f "${INSTALL_DIR}/packages-before-install.txt" ]]; then
            list_installed_packages >"${INSTALL_DIR}/packages-before-install.txt"
            chmod 0600 "${INSTALL_DIR}/packages-before-install.txt"
        fi
        PACKAGE_TRACKING_ACTIVE="1"
    fi
}

record_installed_packages() {
    [[ "${PACKAGE_TRACKING_ACTIVE}" == "1" ]] || return 0

    list_installed_packages >"${INSTALL_DIR}/packages-after-install.txt"
    comm -13 \
        "${INSTALL_DIR}/packages-before-install.txt" \
        "${INSTALL_DIR}/packages-after-install.txt" \
        >"${INSTALL_DIR}/installer-packages.txt"
    chmod 0600 "${INSTALL_DIR}/installer-packages.txt"
    rm -f -- \
        "${INSTALL_DIR}/packages-before-install.txt" \
        "${INSTALL_DIR}/packages-after-install.txt"
    PACKAGE_TRACKING_ACTIVE="0"
}

install_prerequisites() {
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y ca-certificates curl iproute2
}

configure_docker_repository() {
    local repo_codename="${OS_CODENAME}"

    install -m 0755 -d /etc/apt/keyrings
    curl -4 -fsSL --retry 3 --connect-timeout 15 \
        "https://download.docker.com/linux/${OS_ID}/gpg" \
        -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    cat >/etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/${OS_ID}
Suites: ${repo_codename}
Components: stable
Architectures: ${ARCH}
Signed-By: /etc/apt/keyrings/docker.asc
EOF
}

install_docker() {
    if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
        success "检测到可用的 Docker 和 Docker Compose，跳过安装。"
    else
        configure_docker_repository
        apt-get update
        if command -v docker >/dev/null 2>&1; then
            apt-get install -y docker-compose-plugin
        else
            apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        fi
    fi

    if command -v systemctl >/dev/null 2>&1; then
        systemctl enable --now docker
    else
        service docker start
    fi

    docker info >/dev/null 2>&1 || fail "Docker 服务没有正常运行。"
    docker compose version >/dev/null 2>&1 || fail "Docker Compose 插件不可用。"
}

select_docker_image() {
    local candidate
    local -a candidates=(
        "${PRIMARY_DOCKER_IMAGE}"
        "${FALLBACK_DOCKER_IMAGE}"
    )

    for candidate in "${candidates[@]}"; do
        printf '正在尝试官方镜像：%s:%s\n' "${candidate}" "${RUSTDESK_TAG}"
        if docker pull "${candidate}:${RUSTDESK_TAG}"; then
            DOCKER_IMAGE="${candidate}"
            success "镜像拉取成功：${DOCKER_IMAGE}:${RUSTDESK_TAG}"
            return 0
        fi
        warn "无法从 ${candidate} 拉取镜像，将尝试下一个官方来源。"
    done

    fail "GHCR 与 Docker Hub 均无法拉取 RustDesk 镜像。请检查 VPS 的出站网络、DNS 和 TCP 443。"
}

fetch_latest_stable() {
    local response latest
    response="$(curl -4 -fsSL --retry 3 --retry-delay 2 \
        --connect-timeout 15 --max-time 60 \
        -H 'Accept: application/vnd.github+json' \
        'https://api.github.com/repos/rustdesk/rustdesk-server/releases/latest')" || return 1

    latest="$(
        printf '%s' "${response}" \
            | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"v?[^"]+"' \
            | head -n 1 \
            | sed -E 's/^.*:[[:space:]]*"v?([^"]+)".*$/\1/'
    )" || true

    [[ "${latest}" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9]+)?$ ]] || return 1
    printf '%s' "${latest}"
}

choose_rustdesk_version() {
    local latest_stable=""

    if latest_stable="$(fetch_latest_stable)"; then
        printf '最新稳定版：%s\n' "${latest_stable}"
    else
        warn "暂时无法从 GitHub Releases 获取稳定版号，可选择滚动版 latest。"
    fi

    printf '1) 稳定版（推荐）\n'
    printf '2) 滚动版 latest（更新更快，风险较高）\n'
    prompt "请选择 [默认 1]: "
    CHANNEL_CHOICE="${REPLY:-1}"

    case "${CHANNEL_CHOICE}" in
        1)
            [[ -n "${latest_stable}" ]] || fail "未取得稳定版号，请稍后重试或选择 2。"
            RUSTDESK_CHANNEL="stable"
            RUSTDESK_TAG="${latest_stable}"
            ;;
        2)
            RUSTDESK_CHANNEL="latest"
            RUSTDESK_TAG="latest"
            ;;
        *)
            fail "版本选项只能输入 1 或 2。"
            ;;
    esac
}

choose_server_address() {
    prompt "请输入已解析到本 VPS 的域名，或公网 IP: "
    SERVER_ADDRESS="${REPLY}"

    [[ -n "${SERVER_ADDRESS}" ]] || fail "域名或公网 IP 不能为空。"
    [[ "${SERVER_ADDRESS}" =~ ^[A-Za-z0-9.-]+$ ]] \
        || fail "地址格式不正确。请只输入域名或 IPv4 地址，不要包含 http://、端口、斜杠或空格。"
    [[ "${SERVER_ADDRESS}" != -* && "${SERVER_ADDRESS}" != *- ]] \
        || fail "地址格式不正确。"
}

write_compose_file() {
    local candidate="${COMPOSE_FILE}.new"

    install -d -m 0755 "${INSTALL_DIR}"
    install -d -m 0700 "${DATA_DIR}"

    cat >"${candidate}" <<EOF
services:
  hbbs:
    container_name: hbbs
    image: ${DOCKER_IMAGE}:${RUSTDESK_TAG}
    command: ["hbbs", "-r", "${SERVER_ADDRESS}:21117"]
    volumes:
      - ./data:/root
    network_mode: host
    depends_on:
      - hbbr
    restart: unless-stopped

  hbbr:
    container_name: hbbr
    image: ${DOCKER_IMAGE}:${RUSTDESK_TAG}
    command: ["hbbr"]
    volumes:
      - ./data:/root
    network_mode: host
    restart: unless-stopped
EOF

    docker compose -f "${candidate}" config >/dev/null
    mv "${candidate}" "${COMPOSE_FILE}"
    printf '%s\n' "${SERVER_ADDRESS}" >"${INSTALL_DIR}/domain.txt"
    printf '%s\n' "${RUSTDESK_CHANNEL}" >"${INSTALL_DIR}/channel.txt"
    printf '%s\n' "${DOCKER_IMAGE}" >"${INSTALL_DIR}/image-source.txt"
    printf '%s\n' "${SCRIPT_VERSION}" >"${INSTALL_DIR}/installer-version.txt"
}

deploy_rustdesk() {
    docker compose -f "${COMPOSE_FILE}" up -d --remove-orphans

    local count
    for ((count = 0; count < 30; count++)); do
        [[ -s "${DATA_DIR}/id_ed25519.pub" ]] && break
        sleep 1
    done

    [[ -s "${DATA_DIR}/id_ed25519.pub" ]] \
        || warn "公钥尚未生成。请稍后运行 rustdesk-status 查看。"
}

create_management_commands() {
    cat >/usr/local/bin/rustdesk-status <<'STATUS_EOF'
#!/usr/bin/env bash
set -u

readonly install_dir="/opt/rustdesk"
readonly compose_file="${install_dir}/docker-compose.yml"

printf '=================================\n'
printf ' RustDesk Server Status\n'
printf '=================================\n\n'

printf 'Docker：'
if command -v systemctl >/dev/null 2>&1; then
    systemctl is-active docker 2>/dev/null || true
else
    docker info >/dev/null 2>&1 && printf 'active\n' || printf 'inactive\n'
fi

printf '\n容器：\n'
docker compose -f "${compose_file}" ps 2>/dev/null || true

printf '\n端口：\n'
if command -v ss >/dev/null 2>&1; then
    for port in 21115 21116 21117 21118 21119; do
        if ss -lnt | grep -qE ":${port}([[:space:]]|$)"; then
            printf '%s TCP ✓\n' "${port}"
        else
            printf '%s TCP ✗\n' "${port}"
        fi
    done
    if ss -lun | grep -qE ':21116([[:space:]]|$)'; then
        printf '21116 UDP ✓\n'
    else
        printf '21116 UDP ✗\n'
    fi
else
    printf '未安装 ss，无法检查端口。\n'
fi

printf '\nID Server：\n'
cat "${install_dir}/domain.txt" 2>/dev/null || printf '未找到\n'

printf '\nKey：\n'
cat "${install_dir}/data/id_ed25519.pub" 2>/dev/null || printf '尚未生成\n'
STATUS_EOF

    cat >/usr/local/bin/rustdesk-update <<'UPDATE_EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

readonly install_dir="/opt/rustdesk"
readonly compose_file="${install_dir}/docker-compose.yml"
readonly primary_image="ghcr.io/rustdesk/rustdesk-server"
readonly fallback_image="rustdesk/rustdesk-server"

fail() {
    printf '[失败] %s\n' "$1" >&2
    exit 1
}

warn() {
    printf '[注意] %s\n' "$1" >&2
}

prompt() {
    if [[ -r /dev/tty ]]; then
        IFS= read -r -p "$1" REPLY </dev/tty
    else
        IFS= read -r -p "$1" REPLY
    fi
}

fetch_latest_stable() {
    local response latest
    response="$(curl -4 -fsSL --retry 3 --retry-delay 2 \
        --connect-timeout 15 --max-time 60 \
        -H 'Accept: application/vnd.github+json' \
        'https://api.github.com/repos/rustdesk/rustdesk-server/releases/latest')" || return 1

    latest="$(
        printf '%s' "${response}" \
            | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"v?[^"]+"' \
            | head -n 1 \
            | sed -E 's/^.*:[[:space:]]*"v?([^"]+)".*$/\1/'
    )" || true

    [[ "${latest}" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9]+)?$ ]] || return 1
    printf '%s' "${latest}"
}

select_image_source() {
    local candidate
    for candidate in "${primary_image}" "${fallback_image}"; do
        printf '正在尝试官方镜像：%s:%s\n' "${candidate}" "${target}"
        if docker pull "${candidate}:${target}"; then
            selected_image="${candidate}"
            printf '镜像拉取成功：%s:%s\n' "${selected_image}" "${target}"
            return 0
        fi
        warn "无法从 ${candidate} 拉取镜像，将尝试下一个官方来源。"
    done
    fail "GHCR 与 Docker Hub 均无法拉取 RustDesk 镜像，原配置未修改。"
}

[[ "${EUID}" -eq 0 ]] || fail "请使用 root 运行。"
[[ -f "${compose_file}" ]] || fail "找不到 RustDesk 配置。"

channel="$(cat "${install_dir}/channel.txt" 2>/dev/null || printf 'stable')"
current_ref="$(sed -nE 's/^[[:space:]]*image:[[:space:]]*([^[:space:]]+).*$/\1/p' "${compose_file}" | head -n 1)"
[[ -n "${current_ref}" ]] || fail "无法从 Docker Compose 配置读取当前镜像。"
current_image="${current_ref%:*}"
current="${current_ref##*:}"
target="${current}"
selected_image="${current_image}"

if [[ "${channel}" == "latest" ]]; then
    target="latest"
    printf '当前使用滚动版 latest，将拉取最新镜像。\n'
else
    target="$(fetch_latest_stable)" || fail "无法从 GitHub Releases 取得最新稳定版号，请稍后再试。"
    printf '当前版本：%s\n最新稳定版：%s\n' "${current}" "${target}"
    if [[ "${current}" == "${target}" ]]; then
        printf '当前已经是最新稳定版。\n'
        exit 0
    fi
fi

prompt "确认升级？[y/N]: "
[[ "${REPLY:-}" =~ ^[Yy]$ ]] || exit 0

select_image_source

candidate="${compose_file}.new"
cp -a "${compose_file}" "${candidate}"
sed -i -E "s|(^[[:space:]]*image:[[:space:]]*)[^[:space:]]+|\\1${selected_image}:${target}|g" "${candidate}"

docker compose -f "${candidate}" config >/dev/null
mv "${candidate}" "${compose_file}"
printf '%s\n' "${selected_image}" >"${install_dir}/image-source.txt"
docker compose -f "${compose_file}" up -d --remove-orphans

printf '升级完成，当前镜像：%s:%s\n' "${selected_image}" "${target}"
printf '数据和 Key 保持不变。\n'
UPDATE_EOF

    cat >/usr/local/bin/rustdesk-restart <<'RESTART_EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "${EUID}" -eq 0 ]] || { printf '[失败] 请使用 root 运行。\n' >&2; exit 1; }
docker compose -f /opt/rustdesk/docker-compose.yml restart
docker compose -f /opt/rustdesk/docker-compose.yml ps
RESTART_EOF

    cat >/usr/local/bin/rustdesk-logs <<'LOGS_EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
docker compose -f /opt/rustdesk/docker-compose.yml logs --tail=200 -f
LOGS_EOF

    cat >/usr/local/bin/rustdesk-uninstall <<'UNINSTALL_EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

[[ "${EUID}" -eq 0 ]] || { printf '[失败] 请使用 root 运行。\n' >&2; exit 1; }

readonly install_dir="/opt/rustdesk"
readonly package_file="${install_dir}/installer-packages.txt"
readonly ufw_rule_file="${install_dir}/ufw-rules-added.txt"

declare -a tracked_packages=()
declare -a other_containers=()
declare -a all_containers=()
declare -a packages_to_purge=()
docker_inspection_failed="0"

if [[ -f "${package_file}" ]]; then
    mapfile -t tracked_packages < <(sed '/^[[:space:]]*$/d' "${package_file}")
fi

docker_origin="$(cat "${install_dir}/docker-origin.txt" 2>/dev/null || printf 'unknown')"

if command -v docker >/dev/null 2>&1; then
    if docker info >/dev/null 2>&1; then
        mapfile -t other_containers < <(
            docker ps -a --format '{{.Names}}\t{{.Image}}' \
                | awk '$1 != "hbbs" && $1 != "hbbr"'
        )
    else
        docker_inspection_failed="1"
    fi
fi

printf '\n\033[1;31m============================================================\033[0m\n'
printf '\033[1;31m 高风险操作：完整卸载 RustDesk 及 Docker\033[0m\n'
printf '\033[1;31m============================================================\033[0m\n'
printf '继续操作将永久删除：\n'
printf '  1. RustDesk Server、数据库、密钥和全部配置；\n'
printf '  2. Docker Engine、Docker Compose、containerd 及相关依赖；\n'
printf '  3. 本机全部 Docker 容器、镜像、网络和数据卷；\n'
printf '  4. /var/lib/docker、/var/lib/containerd 及 Docker 软件源；\n'
printf '  5. 本脚本新增的 UFW 端口规则。\n\n'
printf '本卸载过程不会创建备份，删除后无法恢复。\n'

if [[ "${docker_origin}" == "pre-existing" ]]; then
    printf '\n\033[1;33m警告：安装 RustDesk 前，本机已经存在 Docker。\033[0m\n'
fi

if ((${#other_containers[@]} > 0)); then
    printf '\n\033[1;33m检测到以下非 RustDesk 容器，它们也会被永久删除：\033[0m\n'
    printf '  - %s\n' "${other_containers[@]}"
fi

if [[ "${docker_inspection_failed}" == "1" ]]; then
    printf '\n\033[1;33m警告：Docker 服务当前不可用，无法列出已有容器。\033[0m\n'
    printf 'Docker 数据目录中仍可能存在其他服务的数据，继续后也会被删除。\n'
fi

printf '\n如果其他网站、数据库、面板或应用正在使用 Docker，\n'
printf '继续卸载会导致这些服务立即停止并丢失其 Docker 数据。\n'
printf '只有在确认本 VPS 的 Docker 专供 RustDesk 使用时，才应继续。\n\n'

if [[ -r /dev/tty ]]; then
    IFS= read -r -p '输入 REMOVE-ALL 确认永久删除以上全部内容，其他输入取消：' confirm </dev/tty
else
    IFS= read -r -p '输入 REMOVE-ALL 确认永久删除以上全部内容，其他输入取消：' confirm
fi
[[ "${confirm}" == "REMOVE-ALL" ]] || { printf '已取消卸载。\n'; exit 0; }

if command -v docker >/dev/null 2>&1; then
    cd "${install_dir}" 2>/dev/null || true
    docker compose down --remove-orphans 2>/dev/null || true

    mapfile -t all_containers < <(docker ps -aq 2>/dev/null || true)
    if ((${#all_containers[@]} > 0)); then
        docker rm -f "${all_containers[@]}" 2>/dev/null || true
    fi

    docker system prune -a --volumes -f 2>/dev/null || true
fi

if command -v systemctl >/dev/null 2>&1; then
    systemctl disable --now docker.service docker.socket containerd.service 2>/dev/null || true
fi

if command -v ufw >/dev/null 2>&1 && [[ -f "${ufw_rule_file}" ]]; then
    while IFS= read -r rule; do
        [[ -n "${rule}" ]] || continue
        ufw --force delete allow "${rule}" 2>/dev/null || true
    done <"${ufw_rule_file}"
fi

known_docker_packages=(
    docker-ce
    docker-ce-cli
    docker-ce-rootless-extras
    docker-buildx-plugin
    docker-compose-plugin
    docker.io
    docker-compose
    docker-compose-v2
    docker-doc
    podman-docker
    containerd.io
    containerd
    runc
)

for package in "${known_docker_packages[@]}" "${tracked_packages[@]}"; do
    if dpkg-query -W -f='${db:Status-Abbrev}' "${package}" 2>/dev/null | grep -q '^ii'; then
        packages_to_purge+=("${package}")
    fi
done

if ((${#packages_to_purge[@]} > 0)); then
    mapfile -t packages_to_purge < <(printf '%s\n' "${packages_to_purge[@]}" | sort -u)
    apt-get purge -y "${packages_to_purge[@]}"
fi

rm -rf -- \
    /opt/rustdesk \
    /opt/rustdesk-backups \
    /var/lib/docker \
    /var/lib/containerd \
    /etc/docker \
    /etc/systemd/system/docker.service.d

rm -f -- \
    /etc/apt/sources.list.d/docker.sources \
    /etc/apt/sources.list.d/docker.list \
    /etc/apt/keyrings/docker.asc \
    /etc/apt/keyrings/docker.gpg \
    /var/run/docker.sock

rm -f -- \
    /usr/local/bin/rustdesk-status \
    /usr/local/bin/rustdesk-update \
    /usr/local/bin/rustdesk-backup \
    /usr/local/bin/rustdesk-restart \
    /usr/local/bin/rustdesk-logs \
    /usr/local/bin/rustdesk-uninstall \
    /usr/local/bin/rustdesk-help

if getent group docker >/dev/null 2>&1; then
    groupdel docker 2>/dev/null || true
fi

if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload
fi

printf '\n完整卸载完成：RustDesk、Docker 及本脚本新增的依赖已删除。\n'
printf '建议重启 VPS，使残留的临时网络状态完全清除。\n'
printf 'VPS 服务商控制台中的安全组规则需要手动删除。\n'
UNINSTALL_EOF

    cat >/usr/local/bin/rustdesk-help <<'HELP_EOF'
#!/usr/bin/env bash
cat <<'COMMANDS'
RustDesk 管理命令：
  rustdesk-status     查看状态、端口、ID Server 和 Key
  rustdesk-update     更新 RustDesk Server 镜像
  rustdesk-restart    重启 hbbs/hbbr
  rustdesk-logs       实时查看日志，按 Ctrl+C 退出
  rustdesk-uninstall  完整删除 RustDesk、Docker 及相关依赖
  rustdesk-help       显示本帮助
COMMANDS
HELP_EOF

    rm -f -- /usr/local/bin/rustdesk-backup

    chmod 0755 \
        /usr/local/bin/rustdesk-status \
        /usr/local/bin/rustdesk-update \
        /usr/local/bin/rustdesk-restart \
        /usr/local/bin/rustdesk-logs \
        /usr/local/bin/rustdesk-uninstall \
        /usr/local/bin/rustdesk-help
}

configure_firewall() {
    if command -v ufw >/dev/null 2>&1; then
        local rule rule_file="${INSTALL_DIR}/ufw-rules-added.txt"
        touch "${rule_file}"
        chmod 0600 "${rule_file}"

        for rule in 21115/tcp 21116/tcp 21116/udp 21117/tcp 21118/tcp 21119/tcp; do
            if ufw show added 2>/dev/null | grep -Fqx "ufw allow ${rule}"; then
                continue
            fi
            ufw allow "${rule}"
            printf '%s\n' "${rule}" >>"${rule_file}"
        done
        success "已添加 UFW 规则；若 UFW 尚未启用，脚本不会擅自启用。"
    else
        warn "未检测到 UFW。请在 VPS 控制台/安全组中手动放行 21115-21119/TCP 和 21116/UDP。"
    fi
}

show_result() {
    local public_key="尚未生成，请稍后运行 rustdesk-status"
    if [[ -s "${DATA_DIR}/id_ed25519.pub" ]]; then
        public_key="$(cat "${DATA_DIR}/id_ed25519.pub")"
    fi

    printf '\n\033[1;32m=========================================\033[0m\n'
    printf '\033[1;32m RustDesk Server 安装完成\033[0m\n'
    printf '\033[1;32m=========================================\033[0m\n'
    printf '系统：%s (%s)\n' "${OS_NAME}" "${ARCH}"
    printf '镜像：%s:%s\n' "${DOCKER_IMAGE}" "${RUSTDESK_TAG}"
    printf 'ID Server：%s\n' "${SERVER_ADDRESS}"
    printf 'Relay Server：留空（客户端会使用默认端口）\n'
    printf 'Key：%s\n' "${public_key}"
    printf '\n运行 rustdesk-help 查看全部管理命令。\n'
    printf '还需确认 VPS 服务商的安全组/云防火墙已放行相应端口。\n'
}

main() {
    require_root

    printf '=========================================\n'
    printf ' RustDesk VPS OneClick v%s\n' "${SCRIPT_VERSION}"
    printf ' Ubuntu + Debian / Docker Compose\n'
    printf '=========================================\n'

    info "1/9" "检测操作系统"
    detect_system
    printf '系统：%s\n架构：%s\n' "${OS_NAME}" "${ARCH}"
    prepare_install_state

    info "2/9" "安装基础工具"
    install_prerequisites

    info "3/9" "选择 RustDesk Server 版本"
    choose_rustdesk_version

    info "4/9" "设置服务器地址"
    choose_server_address

    info "5/9" "检查并安装 Docker"
    install_docker
    record_installed_packages

    info "6/9" "选择镜像源并生成服务配置"
    select_docker_image
    write_compose_file

    info "7/9" "启动 RustDesk Server"
    deploy_rustdesk

    info "8/9" "创建管理命令并配置防火墙"
    create_management_commands
    configure_firewall

    info "9/9" "输出客户端配置"
    show_result
}

main "$@"
