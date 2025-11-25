bash -c '
# ============================================
# Fail2ban 自动安装配置脚本
# 功能：自动检测SSH端口并配置防护规则
# ============================================

# 输出脚本标题
echo -e "\n\033[1;36m╔══════════════════════════════════════════════╗\033[0m"
echo -e "\033[1;36m║        Fail2ban 自动安装配置脚本 v2.0        ║\033[0m"
echo -e "\033[1;36m╚══════════════════════════════════════════════╝\033[0m\n"

# ========== 步骤1: 系统检测 ==========
OS_TYPE=$(grep -E "^ID=" /etc/os-release | cut -d= -f2 | tr -d "\"")
echo -e "\033[1;32m▶ 系统检测\033[0m"
echo -e "  \033[1;33m● 操作系统: $OS_TYPE\033[0m"
echo -e "  \033[1;33m● 系统时间: $(date)\033[0m\n"

# ========== 步骤2: 根据系统类型执行安装 ==========
if [[ "$OS_TYPE" =~ ^(debian|ubuntu)$ ]]; then
    # Debian/Ubuntu 系统
    echo -e "\033[1;32m▶ 准备安装环境\033[0m"
    
    # 清理有问题的软件源
    echo -e "  \033[90m○ 清理问题源...\033[0m"
    rm -f /etc/apt/sources.list.d/ookla_speedtest-cli.list 2>/dev/null
    
    # 更新软件包列表
    echo -e "  \033[90m○ 更新软件源...\033[0m"
    apt-get update --allow-insecure-repositories >/dev/null 2>&1 || true
    echo -e "  \033[1;32m✓ 环境准备完成\033[0m\n"
    
    # 安装 fail2ban
    echo -e "\033[1;32m▶ 安装 Fail2ban\033[0m"
    apt-get install -y --allow-unauthenticated fail2ban >/dev/null 2>&1 && \
        echo -e "  \033[1;32m✓ 安装成功\033[0m\n" || \
        { echo -e "  \033[1;31m✗ 安装失败\033[0m\n"; exit 1; }

elif [[ "$OS_TYPE" =~ ^(centos|rhel|fedora|rocky|almalinux)$ ]]; then
    # RedHat 系列系统
    echo -e "\033[1;32m▶ 安装 Fail2ban\033[0m"
    yum install -y epel-release >/dev/null 2>&1 && \
    yum install -y fail2ban >/dev/null 2>&1 && \
        echo -e "  \033[1;32m✓ 安装成功\033[0m\n" || \
        { echo -e "  \033[1;31m✗ 安装失败\033[0m\n"; exit 1; }

else
    # 不支持的系统
    echo -e "\033[1;31m✗ 不支持的操作系统: $OS_TYPE\033[0m"
    exit 1
fi

# ========== 步骤3: 检测SSH端口 ==========
echo -e "\033[1;32m▶ 检测SSH配置\033[0m"

# 方法1: 从sshd_config配置文件读取
SSH_PORT=$(grep -E "^[[:space:]]*Port" /etc/ssh/sshd_config 2>/dev/null | \
           awk "{print \$2}" | head -1)

# 方法2: 如果配置文件中没有，检查实际监听端口
[ -z "$SSH_PORT" ] && \
    SSH_PORT=$(ss -tlnp 2>/dev/null | grep sshd | \
               awk "{print \$4}" | grep -oE "[0-9]+$" | head -1)

# 方法3: 如果仍未检测到，使用默认端口
[ -z "$SSH_PORT" ] && SSH_PORT="22"

echo -e "  \033[1;33m● SSH端口: $SSH_PORT\033[0m\n"

# ========== 步骤4: 创建配置文件 ==========
echo -e "\033[1;32m▶ 创建配置文件\033[0m"

# 根据系统选择日志路径
if [[ "$OS_TYPE" =~ ^(debian|ubuntu)$ ]]; then
    LOG_PATH="/var/log/auth.log"
else
    LOG_PATH="/var/log/secure"
fi

# 写入fail2ban配置
cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
banaction = iptables-multiport
backend = systemd

[sshd]
ignoreip = 127.0.0.1/8 ::1
enabled = true
filter = sshd
port = $SSH_PORT
maxretry = 10
findtime = 300
bantime = 1800
action = %(action_)s[port="%(port)s", protocol="%(protocol)s", logpath="%(logpath)s", chain="%(chain)s"]
logpath = $LOG_PATH
EOF

echo -e "  \033[1;32m✓ 配置文件已创建\033[0m\n"

# ========== 步骤5: 启动服务 ==========
echo -e "\033[1;32m▶ 启动服务\033[0m"
systemctl enable fail2ban.service >/dev/null 2>&1
systemctl restart fail2ban.service && sleep 2 && \
    echo -e "  \033[1;32m✓ 服务已启动\033[0m\n" || \
    echo -e "  \033[1;31m✗ 服务启动失败\033[0m\n"

# ========== 步骤6: 验证配置 ==========
echo -e "\033[1;32m▶ 验证配置\033[0m"

if systemctl is-active --quiet fail2ban && \
   fail2ban-client status 2>/dev/null | grep -q "sshd"; then
    
    # 配置成功
    echo -e "  \033[1;32m✓ 配置验证成功\033[0m\n"
    
    # 显示安装摘要
    echo -e "\033[1;36m┌─────────────────────────────────────────────┐\033[0m"
    echo -e "\033[1;36m│              安装完成摘要                   │\033[0m"
    echo -e "\033[1;36m├─────────────────────────────────────────────┤\033[0m"
    echo -e "\033[1;36m│\033[0m  状态: \033[1;32m✓ 成功\033[0m                              \033[1;36m│\033[0m"
    echo -e "\033[1;36m│\033[0m  SSH端口: \033[1;33m$SSH_PORT\033[0m                                \033[1;36m│\033[0m"
    echo -e "\033[1;36m│\033[0m  防护规则:                                  \033[1;36m│\033[0m"
    echo -e "\033[1;36m│\033[0m    • 最大重试: \033[1;33m10次\033[0m                        \033[1;36m│\033[0m"
    echo -e "\033[1;36m│\033[0m    • 监测时间: \033[1;33m5分钟\033[0m                       \033[1;36m│\033[0m"
    echo -e "\033[1;36m│\033[0m    • 封禁时长: \033[1;33m30分钟\033[0m                      \033[1;36m│\033[0m"
    echo -e "\033[1;36m└─────────────────────────────────────────────┘\033[0m\n"
    
    # 显示实时状态
    echo -e "\033[1;32m▶ Fail2ban 实时状态\033[0m"
    fail2ban-client status sshd 2>/dev/null | \
        while IFS= read -r line; do
            echo -e "  \033[90m$line\033[0m"
        done
    echo ""
    
    # 使用提示
    echo -e "\033[1;34m提示: 使用 \033[1;33mfail2ban-client status sshd\033[1;34m 查看详细状态\033[0m\n"
    
else
    # 配置失败
    echo -e "  \033[1;31m✗ 配置验证失败\033[0m"
    echo -e "\n\033[1;33m请检查日志: journalctl -u fail2ban -n 50\033[0m\n"
    exit 1
fi
'

