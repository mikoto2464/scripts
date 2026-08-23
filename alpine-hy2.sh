#!/bin/sh
# 交互式 Hysteria 2 一键安装脚本 for Alpine Linux (OpenRC)

set -e

# 终端颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# 1. 权限检查
if [ "$(id -u)" != "0" ]; then
    echo -e "${RED}错误: 必须以 root 身份运行此脚本。${NC}"
    exit 1
fi

# 2. 基础依赖安装 (前置安装以获取 uuidgen)
echo -e "${GREEN}==> 正在更新系统包并安装基础依赖...${NC}"
apk update >/dev/null 2>&1
apk add --no-cache wget curl openssl uuidgen ca-certificates >/dev/null 2>&1

# 3. 交互式参数配置
echo -e "${GREEN}==> 请配置 Hysteria 2 参数 (直接回车将使用默认值)${NC}"

# 配置端口
printf "${YELLOW}请输入监听端口 (UDP) [默认: 443]: ${NC}"
read INPUT_PORT
PORT=${INPUT_PORT:-443}

# 配置密码
DEFAULT_PASS=$(uuidgen)
printf "${YELLOW}请输入连接密码 [默认: ${DEFAULT_PASS}]: ${NC}"
read INPUT_PASS
PASSWORD=${INPUT_PASS:-$DEFAULT_PASS}

# 配置 SNI
printf "${YELLOW}请输入伪装 SNI 域名 [默认: bing.com]: ${NC}"
read INPUT_SNI
SNI=${INPUT_SNI:-bing.com}

echo -e "\n${GREEN}==> 您的配置选项：端口=${PORT}, 密码=${PASSWORD}, SNI=${SNI}${NC}"

# 4. 系统架构检测与核心程序下载
ARCH=$(uname -m)
case "$ARCH" in
    x86_64) HY2_ARCH="amd64" ;;
    aarch64) HY2_ARCH="arm64" ;;
    armv7l) HY2_ARCH="armv7" ;;
    s390x) HY2_ARCH="s390x" ;;
    *) echo -e "${RED}错误: 不支持的系统架构 $ARCH ${NC}"; exit 1 ;;
esac

echo -e "${GREEN}==> 正在下载 Hysteria 2 核心程序...${NC}"
DOWNLOAD_URL="https://download.hysteria.network/app/latest/hysteria-linux-${HY2_ARCH}"
wget -q -O /usr/local/bin/hysteria "$DOWNLOAD_URL"
chmod +x /usr/local/bin/hysteria

# 5. 证书与配置生成
echo -e "${GREEN}==> 正在生成基于 ${SNI} 的自签名证书...${NC}"
mkdir -p /etc/hysteria

# 根据用户输入的 SNI 动态生成证书
openssl ecparam -genkey -name prime256v1 -out /etc/hysteria/private.key
openssl req -new -x509 -days 3650 -key /etc/hysteria/private.key -out /etc/hysteria/cert.crt -subj "/CN=${SNI}" >/dev/null 2>&1

cat > /etc/hysteria/config.yaml <<EOF
listen: :${PORT}

tls:
  cert: /etc/hysteria/cert.crt
  key: /etc/hysteria/private.key

auth:
  type: password
  password: ${PASSWORD}

masquerade:
  type: proxy
  proxy:
    url: https://${SNI}
    rewriteHost: true
EOF

# 6. 配置 OpenRC 守护进程
echo -e "${GREEN}==> 正在配置 OpenRC 守护进程...${NC}"
cat > /etc/init.d/hysteria <<'EOF'
#!/sbin/openrc-run

name="hysteria"
description="Hysteria 2 Server"
command="/usr/local/bin/hysteria"
command_args="server -c /etc/hysteria/config.yaml"
command_background="yes"
pidfile="/run/${RC_SVCNAME}.pid"
output_log="/var/log/${RC_SVCNAME}.log"
error_log="/var/log/${RC_SVCNAME}.err"

depend() {
    need net
    use dns
}
EOF

chmod +x /etc/init.d/hysteria

# 7. 启动服务
echo -e "${GREEN}==> 启动 Hysteria 2 服务并设置开机自启...${NC}"
rc-update add hysteria default >/dev/null 2>&1
rc-service hysteria restart >/dev/null 2>&1

# 8. 输出结果
SERVER_IP=$(curl -s --ipv4 ifconfig.me || echo "未获取到IP")

echo -e "\n======================================="
echo -e "${GREEN}Hysteria 2 已成功安装并运行！${NC}"
echo -e "配置文件路径: /etc/hysteria/config.yaml"
echo -e "服务管理: rc-service hysteria {start|stop|restart|status}"
echo -e "\n${YELLOW}【客户端连接信息】${NC}"
echo -e "服务器地址: ${SERVER_IP}:${PORT}"
echo -e "密      码: ${PASSWORD}"
echo -e "伪装 SNI  : ${SNI}"
echo -e "协议      : udp"
echo -e "\n${RED}⚠️ 注意: 客户端必须开启 '跳过证书验证' (insecure: true) 才能连接！${NC}"
echo -e "======================================="
