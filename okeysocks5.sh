cat << 'EOF' > install_fast_sk5.sh && bash install_fast_sk5.sh
#!/bin/bash
if [ "$EUID" -ne 0 ]; then echo "请以 root 权限运行此脚本"; exit 1; fi

# 定义颜色和信息保存路径
GREEN='\033[1;32m'
NC='\033[0m'
INFO_FILE="/etc/gost_sk5.info"

# ==== 优化：防重复运行检测 ====
# 如果检测到配置记录文件存在，直接高亮输出信息并退出
if [ -f "$INFO_FILE" ]; then
    echo -e "\n${GREEN}检测到该 VPS 已搭建 SOCKS5 节点，直接输出配置信息：${NC}"
    echo "=========================================="
    echo -e "${GREEN}$(cat $INFO_FILE)${NC}"
    echo "=========================================="
    exit 0
fi

echo "==== 1. 开始优化网络 (开启 BBR + FQ) ===="
if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf; then echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf; fi
if ! grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf; then echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf; fi
sysctl -p

echo "==== 2. 拉取预编译核心 (秒级完成) ===="
apt update -y && apt install -y curl wget gzip

ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    URL="https://github.com/ginuerzh/gost/releases/download/v2.11.5/gost-linux-amd64-2.11.5.gz"
elif [ "$ARCH" = "aarch64" ]; then
    URL="https://github.com/ginuerzh/gost/releases/download/v2.11.5/gost-linux-armv8-2.11.5.gz"
else
    echo "不支持的架构: $ARCH"; exit 1;
fi

wget -qO gost.gz $URL
gzip -d -f gost.gz
mv gost /usr/local/bin/gost
chmod +x /usr/local/bin/gost

echo "==== 3. 生成随机配置参数 ===="
PORT=$(shuf -i 10000-60000 -n 1)
USER=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1)
PASS=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 12 | head -n 1)
IP=$(curl -s4 api.ipify.org || curl -s4 ifconfig.me || curl -s4 ip.sb)

# 将生成的节点信息持久化保存
echo "$IP:$PORT:$USER:$PASS" > $INFO_FILE

echo "==== 4. 创建 Systemd 守护进程 ===="
cat > /etc/systemd/system/gost.service <<EOL
[Unit]
Description=GOST SOCKS5 Proxy Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/gost -L=socks5://$USER:$PASS@:$PORT
Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOL

echo "==== 5. 启动服务并设置开机自启 ===="
systemctl daemon-reload
systemctl restart gost
systemctl enable gost

echo -e "\n=========================================="
echo "节点搭建完成！以下绿色的就是节点信息"
echo "=========================================="
echo -e "${GREEN}$IP:$PORT:$USER:$PASS${NC}"
echo "=========================================="
EOF
