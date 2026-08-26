#!/bin/bash
# ==========================================================
# RustDesk-VPS-OneClick.sh v1.5.4 Full Installer Edition
#
# Features:
# - Complete fresh installation
# - Stable/Beta selection
# - Domain input
# - Docker installation
# - Persistent Key
# - hbbs/hbbr deployment
# - rustdesk-status
# - smart rustdesk-update
# - complete uninstall
# ==========================================================

set -e

INSTALL_DIR="/opt/rustdesk"
DATA_DIR="$INSTALL_DIR/data"

if [ "$EUID" -ne 0 ]; then
    echo "请使用 root 运行"
    exit 1
fi

echo "================================="
echo " RustDesk VPS OneClick v1.5.4"
echo " Full Installer Edition"
echo "================================="

echo "[1/8] 系统检测"
. /etc/os-release
echo "系统: $PRETTY_NAME"
echo "架构: $(uname -m)"

echo
echo "[2/8] RustDesk版本检测"

LATEST=$(curl -s https://registry.hub.docker.com/v2/repositories/rustdesk/rustdesk-server/tags?page_size=100 \
| grep -o '"name":"[^"]*"' \
| sed 's/"name":"//;s/"//' \
| grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' \
| sort -V | tail -1)

echo "Stable: $LATEST"
echo "Beta: latest"

read -p "选择版本 1 Stable  2 Beta [默认1]: " CHOICE
CHOICE=${CHOICE:-1}

if [ "$CHOICE" = "2" ]; then
TAG="latest"
else
TAG="$LATEST"
fi

read -p "请输入RustDesk域名: " DOMAIN

if [ -z "$DOMAIN" ]; then
 echo "域名不能为空"
 exit 1
fi

echo
echo "[3/8] Docker安装"

if ! command -v docker >/dev/null 2>&1; then
apt update
apt install -y ca-certificates curl gnupg lsb-release

install -m 0755 -d /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
| gpg --dearmor -o /etc/apt/keyrings/docker.gpg

chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
> /etc/apt/sources.list.d/docker.list

apt update

apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

systemctl enable docker
systemctl start docker

echo
echo "[4/8] 部署RustDesk"

mkdir -p "$DATA_DIR"

cd "$INSTALL_DIR"

echo "$DOMAIN" > domain.txt

cat > docker-compose.yml <<EOF
services:
  hbbs:
    container_name: hbbs
    image: rustdesk/rustdesk-server:$TAG
    command: hbbs
    volumes:
      - ./data:/root
    network_mode: host
    restart: unless-stopped

  hbbr:
    container_name: hbbr
    image: rustdesk/rustdesk-server:$TAG
    command: hbbr
    volumes:
      - ./data:/root
    network_mode: host
    restart: unless-stopped
EOF

docker compose pull
docker compose up -d


echo
echo "[5/8] 创建管理命令"

cat >/usr/local/bin/rustdesk-status <<'EOF'
#!/bin/bash
echo "================================="
echo " RustDesk Server Status"
echo "================================="

echo
echo "Docker:"
systemctl is-active docker

echo
echo "Container:"
docker ps --filter name=hbbs --filter name=hbbr

echo
echo "Ports:"
for p in 21115 21116 21117 21118 21119; do
 ss -lnt | grep -q ":$p " && echo "$p TCP ✓" || echo "$p TCP ✗"
done

ss -lun | grep -q ":21116 " && echo "21116 UDP ✓" || echo "21116 UDP ✗"

echo
echo "Domain:"
cat /opt/rustdesk/domain.txt

echo
echo "Key:"
cat /opt/rustdesk/data/id_ed25519.pub
EOF
chmod +x /usr/local/bin/rustdesk-status


cat >/usr/local/bin/rustdesk-update <<'EOF'
#!/bin/bash
cd /opt/rustdesk

CURRENT=$(grep "image:" docker-compose.yml | head -1 | sed 's/.*://' | tr -d '\r\n ')
LATEST=$(curl -s https://registry.hub.docker.com/v2/repositories/rustdesk/rustdesk-server/tags?page_size=100 \
| grep -o '"name":"[^"]*"' | sed 's/"name":"//;s/"//' \
| grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1 | tr -d '\r\n ')

echo "当前版本: $CURRENT"
echo "最新Stable: $LATEST"

if [ "$CURRENT" = "$LATEST" ]; then
echo "当前已经是最新版本"
exit 0
fi

read -p "发现新版本，是否升级? [y/N]: " C

[ "$C" = "y" ] || exit 0

sed -i -E "s|(rustdesk-server:)[^ ]+|\1$LATEST|g" docker-compose.yml

docker compose pull
docker compose up -d

echo "升级完成，Key保持不变"
EOF
chmod +x /usr/local/bin/rustdesk-update


cat >/usr/local/bin/rustdesk-uninstall <<'EOF'
#!/bin/bash
read -p "输入YES确认完整删除: " C
[ "$C" = "YES" ] || exit 0

cd /opt/rustdesk 2>/dev/null || true
docker compose down 2>/dev/null || true
docker rm -f hbbs hbbr 2>/dev/null || true
rm -rf /opt/rustdesk

rm -f /usr/local/bin/rustdesk-status
rm -f /usr/local/bin/rustdesk-update
rm -f /usr/local/bin/rustdesk-uninstall

echo "RustDesk卸载完成"
EOF
chmod +x /usr/local/bin/rustdesk-uninstall


echo
echo "[6/8] 防火墙"

command -v ufw >/dev/null && {
ufw allow 21115/tcp
ufw allow 21116/tcp
ufw allow 21116/udp
ufw allow 21117/tcp
ufw allow 21118/tcp
ufw allow 21119/tcp
}


echo
echo "[7/8] 状态检测"

docker ps

echo
echo "[8/8] 完成"

echo "管理命令:"
echo "rustdesk-status"
echo "rustdesk-update"
echo "rustdesk-uninstall"
