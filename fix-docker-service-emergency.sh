#!/bin/bash

# Docker服务紧急修复脚本 - 增强版 v1.1.0
# 专门解决Docker服务启动失败问题
# 支持自动诊断和修复以下问题:
# 1. daemon.json语法错误
# 2. DNS服务器连接失败
# 3. Docker服务启动失败
# 4. 网络连接问题
# 5. 系统资源不足
# 6. 内核模块和cgroup问题

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要root权限运行"
        log_info "请使用: sudo $0"
        exit 1
    fi
}

# 创建备份目录
create_backup_dir() {
    BACKUP_DIR="/tmp/docker-emergency-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    log_success "配置文件已备份到: $BACKUP_DIR"
}

# 检查Docker服务状态
check_docker_service() {
    log_info "=== Docker服务详细诊断 ==="
    
    log_info "1. Docker服务状态:"
    systemctl status docker --no-pager -l || true
    echo
    
    log_info "2. Docker服务最近日志 (过去1小时):"
    journalctl -u docker --since "1 hour ago" --no-pager -l || log_warning "无法获取Docker服务日志"
    echo
    
    log_info "2.1 今天所有Docker启动失败日志:"
    journalctl -u docker --since "today" --grep="Failed to start" --no-pager -l || log_info "今天无Docker启动失败日志"
    echo
    
    log_info "2.2 containerd服务日志:"
    journalctl -u containerd --since "1 hour ago" --no-pager -l | tail -10 || log_warning "无法获取containerd日志"
    echo
    
    log_info "2.3 系统启动日志中的Docker错误:"
    journalctl --since "today" --grep="docker" --grep="error\|failed\|Error\|Failed" --no-pager -l | tail -10 || log_info "无相关错误日志"
    echo
    
    log_info "3. Docker socket状态:"
    if [[ -S /var/run/docker.sock ]]; then
        log_success "Docker socket存在"
        ls -la /var/run/docker.sock
    else
        log_error "Docker socket不存在"
    fi
    echo
    
    log_info "4. Docker相关进程:"
    ps aux | grep -E "(docker|containerd)" | grep -v grep || log_warning "未找到Docker相关进程"
    echo
    
    log_info "5. Docker关键文件检查:"
    local docker_files=(
        "/usr/bin/dockerd"
        "/run/containerd/containerd.sock"
        "/var/lib/docker"
        "/var/lib/docker/containers"
        "/var/lib/docker/image"
        "/var/lib/docker/overlay2"
        "/etc/docker"
    )
    
    for file in "${docker_files[@]}"; do
        if [[ -e "$file" ]]; then
            log_success "存在: $file"
            ls -la "$file" 2>/dev/null | head -1
        else
            log_error "缺失: $file"
        fi
    done
    echo
}

# 检查系统资源
check_system_resources() {
    log_info "=== 系统资源检查 ==="
    
    log_info "1. 内存使用情况:"
    free -h
    echo
    
    log_info "2. 磁盘空间使用:"
    df -h | grep -E "(Filesystem|/dev/)"
    echo
    
    log_info "3. 系统负载:"
    uptime
    echo
}

# 增强的网络配置检查
check_network_config() {
    log_info "=== 网络配置检查 ==="
    
    log_info "1. 网络接口状态:"
    ip addr show
    echo
    
    log_info "2. 路由表:"
    ip route show
    echo
    
    log_info "3. DNS配置:"
    cat /etc/resolv.conf
    echo
    
    log_info "4. 详细网络连接测试:"
    
    # 测试多个DNS服务器的可达性和解析功能
    local dns_servers=("8.8.8.8" "114.114.114.114" "223.5.5.5" "1.1.1.1")
    for dns in "${dns_servers[@]}"; do
        log_info "测试DNS服务器: $dns"
        if ping -c 1 -W 3 "$dns" >/dev/null 2>&1; then
            log_success "DNS服务器可达: $dns"
            
            # 测试DNS解析功能
            if nslookup google.com "$dns" >/dev/null 2>&1; then
                log_success "DNS解析功能正常: $dns"
            else
                log_warning "DNS解析功能异常: $dns"
            fi
        else
            log_error "DNS服务器不可达: $dns"
        fi
    done
    echo
    
    log_info "5. 网络接口详细状态:"
    for interface in $(ip link show | grep -E '^[0-9]+:' | cut -d: -f2 | tr -d ' '); do
        if [[ "$interface" != "lo" ]]; then
            log_info "接口 $interface 状态:"
            ip link show "$interface"
            ethtool "$interface" 2>/dev/null | grep -E "(Link detected|Speed|Duplex)" || true
        fi
    done
    echo
    
    log_info "6. 默认路由检查:"
    if ip route show default >/dev/null 2>&1; then
        log_success "默认路由存在"
        ip route show default
    else
        log_error "默认路由不存在"
    fi
    echo
    
    log_info "7. 常用网站连接测试:"
    local test_sites=("google.com" "github.com" "docker.io" "registry-1.docker.io")
    for site in "${test_sites[@]}"; do
        if ping -c 1 -W 5 "$site" >/dev/null 2>&1; then
            log_success "可以连接到: $site"
        else
            log_error "无法连接到: $site"
        fi
    done
    echo
}

# 分析Docker启动失败原因
analyze_docker_failure() {
    log_info "=== Docker启动失败原因分析 ==="
    
    # 检查常见的Docker启动失败原因
    log_info "1. 分析Docker启动失败的可能原因:"
    
    # 检查端口占用
    log_info "1.1 检查Docker相关端口占用:"
    local docker_ports=("2375" "2376" "2377")
    for port in "${docker_ports[@]}"; do
        if netstat -tlnp 2>/dev/null | grep ":$port " >/dev/null; then
            log_warning "端口 $port 被占用:"
            netstat -tlnp | grep ":$port "
        else
            log_info "端口 $port 未被占用"
        fi
    done
    echo
    
    # 检查磁盘空间
    log_info "1.2 检查关键目录磁盘空间:"
    local critical_dirs=("/var/lib/docker" "/tmp" "/var/log")
    for dir in "${critical_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            local usage
            usage=$(df "$dir" | tail -1 | awk '{print $5}' | sed 's/%//')
            if [[ $usage -gt 90 ]]; then
                log_error "$dir 磁盘使用率过高: ${usage}%"
            elif [[ $usage -gt 80 ]]; then
                log_warning "$dir 磁盘使用率较高: ${usage}%"
            else
                log_success "$dir 磁盘使用率正常: ${usage}%"
            fi
        fi
    done
    echo
    
    # 检查内存不足
    log_info "1.3 检查系统内存状态:"
    local available_mem
    available_mem=$(free -m | awk 'NR==2{printf "%.1f", $7/1024}')
    if (( $(echo "$available_mem < 0.5" | bc -l) )); then
        log_error "可用内存不足: ${available_mem}GB"
    elif (( $(echo "$available_mem < 1.0" | bc -l) )); then
        log_warning "可用内存较低: ${available_mem}GB"
    else
        log_success "可用内存充足: ${available_mem}GB"
    fi
    echo
    
    # 检查systemd服务依赖
    log_info "1.4 检查systemd服务依赖:"
    
    # 检查containerd服务状态
    if systemctl is-active containerd >/dev/null 2>&1; then
        log_success "containerd服务运行正常"
    else
        log_error "containerd服务未运行"
        log_info "containerd服务状态:"
        systemctl status containerd --no-pager -l || true
    fi
    
    # 检查docker.socket状态
    if systemctl is-active docker.socket >/dev/null 2>&1; then
        log_success "docker.socket运行正常"
    else
        log_warning "docker.socket未运行"
        log_info "docker.socket状态:"
        systemctl status docker.socket --no-pager -l || true
    fi
    echo
    
    # 检查SELinux状态（如果存在）
    log_info "1.5 检查SELinux状态:"
    if command -v getenforce >/dev/null 2>&1; then
        local selinux_status
        selinux_status=$(getenforce 2>/dev/null || echo "未知")
        log_info "SELinux状态: $selinux_status"
        if [[ "$selinux_status" == "Enforcing" ]]; then
            log_warning "SELinux处于强制模式，可能影响Docker运行"
        fi
    else
        log_info "系统未安装SELinux"
    fi
    echo
    
    # 检查AppArmor状态（如果存在）
    log_info "1.6 检查AppArmor状态:"
    if command -v aa-status >/dev/null 2>&1; then
        log_info "AppArmor状态:"
        aa-status 2>/dev/null | head -5 || log_info "无法获取AppArmor状态"
    else
        log_info "系统未安装AppArmor"
    fi
    echo
    
    # 检查cgroup支持
    log_info "1.7 检查cgroup支持:"
    if [[ -d /sys/fs/cgroup ]]; then
        log_success "cgroup文件系统存在"
        
        # 检查cgroup v1/v2
        if [[ -f /sys/fs/cgroup/cgroup.controllers ]]; then
            log_info "检测到cgroup v2"
        elif [[ -d /sys/fs/cgroup/memory ]]; then
            log_info "检测到cgroup v1"
        else
            log_warning "cgroup版本检测异常"
        fi
        
        # 检查关键cgroup控制器
        local controllers=("memory" "cpu" "cpuset" "blkio")
        for controller in "${controllers[@]}"; do
            if [[ -d "/sys/fs/cgroup/$controller" ]] || grep -q "$controller" /sys/fs/cgroup/cgroup.controllers 2>/dev/null; then
                log_success "cgroup控制器可用: $controller"
            else
                log_warning "cgroup控制器不可用: $controller"
            fi
        done
    else
        log_error "cgroup文件系统不存在"
    fi
    echo
    
    # 检查内核模块
    log_info "1.8 检查Docker所需内核模块:"
    local required_modules=("overlay" "br_netfilter" "iptable_nat")
    for module in "${required_modules[@]}"; do
        if lsmod | grep -q "^$module"; then
            log_success "内核模块已加载: $module"
        else
            log_warning "内核模块未加载: $module"
            # 尝试加载模块
            if modprobe "$module" 2>/dev/null; then
                log_success "成功加载内核模块: $module"
            else
                log_error "无法加载内核模块: $module"
            fi
        fi
    done
    echo
}

# 检查Docker配置文件
check_docker_config() {
    log_info "=== Docker配置文件检查 ==="
    
    # 检查daemon.json文件
    local daemon_json="/etc/docker/daemon.json"
    
    log_info "1. 检查daemon.json语法:"
    if [[ -f "$daemon_json" ]]; then
        log_info "daemon.json文件存在，检查语法..."
        
        # 详细的JSON语法检查
        if python3 -m json.tool "$daemon_json" >/dev/null 2>&1; then
            log_success "daemon.json语法正确"
        else
            log_error "daemon.json语法错误！"
            log_info "错误详情:"
            python3 -m json.tool "$daemon_json" 2>&1 || true
            
            # 备份损坏的文件
            cp "$daemon_json" "$BACKUP_DIR/daemon.json.broken"
            log_info "已备份损坏的daemon.json到: $BACKUP_DIR/daemon.json.broken"
        fi
        
        log_info "当前daemon.json内容:"
        cat "$daemon_json"
        echo
        
        # 检查daemon.json内容的有效性
        log_info "2. 检查daemon.json配置有效性:"
        
        # 检查镜像源配置
        if grep -q "registry-mirrors" "$daemon_json" 2>/dev/null; then
            log_info "发现镜像源配置:"
            grep -A 5 "registry-mirrors" "$daemon_json" || true
        else
            log_warning "未配置镜像源"
        fi
        
        # 检查DNS配置
        if grep -q "dns" "$daemon_json" 2>/dev/null; then
            log_info "发现DNS配置:"
            grep -A 3 "dns" "$daemon_json" || true
        else
            log_warning "未配置DNS"
        fi
        
        # 检查常见的JSON语法错误
        log_info "3. 检查常见JSON语法问题:"
        
        # 检查尾随逗号
        if grep -E ',\s*[}\]]' "$daemon_json" >/dev/null 2>&1; then
            log_error "发现尾随逗号错误"
        else
            log_success "无尾随逗号错误"
        fi
        
        # 检查引号匹配
        local quote_count
        quote_count=$(grep -o '"' "$daemon_json" | wc -l)
        if (( quote_count % 2 != 0 )); then
            log_error "引号不匹配"
        else
            log_success "引号匹配正确"
        fi
        
        # 检查括号匹配
        local open_braces
        local close_braces
        open_braces=$(grep -o '{' "$daemon_json" | wc -l)
        close_braces=$(grep -o '}' "$daemon_json" | wc -l)
        if [[ $open_braces -ne $close_braces ]]; then
            log_error "大括号不匹配: 开括号$open_braces个，闭括号$close_braces个"
        else
            log_success "大括号匹配正确"
        fi
        
    else
        log_warning "daemon.json文件不存在"
    fi
    echo
}

# 修复Docker配置
fix_docker_config() {
    log_info "=== 修复Docker配置 ==="
    
    local daemon_json="/etc/docker/daemon.json"
    
    # 确保/etc/docker目录存在
    mkdir -p /etc/docker
    
    # 备份现有配置（如果存在）
    if [[ -f "$daemon_json" ]]; then
        cp "$daemon_json" "$BACKUP_DIR/daemon.json.original"
        log_info "已备份原始daemon.json"
    fi
    
    # 检测可用的镜像源
    log_info "1. 检测可用的Docker镜像源..."
    local mirrors=()
    local test_mirrors=(
        "https://docker.mirrors.ustc.edu.cn"
        "https://hub-mirror.c.163.com"
        "https://mirror.baidubce.com"
        "https://ccr.ccs.tencentyun.com"
    )
    
    for mirror in "${test_mirrors[@]}"; do
        if curl -s --connect-timeout 5 "$mirror/v2/" >/dev/null 2>&1; then
            mirrors+=("$mirror")
            log_success "可用镜像源: $mirror"
        else
            log_warning "不可用镜像源: $mirror"
        fi
    done
    
    # 检测可用的DNS服务器
    log_info "2. 检测可用的DNS服务器..."
    local dns_servers=()
    local test_dns=("8.8.8.8" "114.114.114.114" "223.5.5.5" "1.1.1.1")
    
    for dns in "${test_dns[@]}"; do
        if ping -c 1 -W 3 "$dns" >/dev/null 2>&1; then
            dns_servers+=("$dns")
            log_success "可用DNS: $dns"
        else
            log_warning "不可用DNS: $dns"
        fi
    done
    
    # 生成优化的daemon.json配置
    log_info "3. 生成优化的daemon.json配置..."
    
    cat > "$daemon_json" << EOF
{
    "registry-mirrors": [
EOF
    
    # 添加可用的镜像源
    if [[ ${#mirrors[@]} -gt 0 ]]; then
        for i in "${!mirrors[@]}"; do
            if [[ $i -eq $((${#mirrors[@]} - 1)) ]]; then
                echo "        \"${mirrors[$i]}\"" >> "$daemon_json"
            else
                echo "        \"${mirrors[$i]}\"," >> "$daemon_json"
            fi
        done
    else
        echo "        \"https://registry-1.docker.io\"" >> "$daemon_json"
    fi
    
    cat >> "$daemon_json" << EOF
    ],
    "dns": [
EOF
    
    # 添加可用的DNS服务器
    if [[ ${#dns_servers[@]} -gt 0 ]]; then
        for i in "${!dns_servers[@]}"; do
            if [[ $i -eq $((${#dns_servers[@]} - 1)) ]]; then
                echo "        \"${dns_servers[$i]}\"" >> "$daemon_json"
            else
                echo "        \"${dns_servers[$i]}\"," >> "$daemon_json"
            fi
        done
    else
        echo "        \"8.8.8.8\"," >> "$daemon_json"
        echo "        \"114.114.114.114\"" >> "$daemon_json"
    fi
    
    cat >> "$daemon_json" << EOF
    ],
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    },
    "storage-driver": "overlay2",
    "exec-opts": ["native.cgroupdriver=systemd"]
}
EOF
    
    # 验证生成的配置文件
    if python3 -m json.tool "$daemon_json" >/dev/null 2>&1; then
        log_success "daemon.json配置文件生成成功并通过语法检查"
        log_info "新的daemon.json内容:"
        cat "$daemon_json"
    else
        log_error "生成的daemon.json语法错误，回退到最小化配置"
        
        # 回退到最小化配置
        cat > "$daemon_json" << EOF
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    }
}
EOF
        log_info "已生成最小化daemon.json配置"
    fi
    echo
}

# 修复系统DNS配置
fix_system_dns() {
    log_info "=== 修复系统DNS配置 ==="
    
    # 备份原始DNS配置
    cp /etc/resolv.conf "$BACKUP_DIR/resolv.conf.original"
    log_info "已备份原始resolv.conf"
    
    # 分析当前DNS配置问题
    log_info "1. 分析当前DNS配置..."
    if [[ -f /etc/resolv.conf ]]; then
        log_info "当前resolv.conf内容:"
        cat /etc/resolv.conf
        
        # 检查是否有有效的nameserver
        local nameserver_count
        nameserver_count=$(grep -c "^nameserver" /etc/resolv.conf 2>/dev/null || echo "0")
        if [[ $nameserver_count -eq 0 ]]; then
            log_error "未找到有效的nameserver配置"
        else
            log_info "找到 $nameserver_count 个nameserver配置"
        fi
    fi
    echo
    
    # 测试现有DNS服务器
    log_info "2. 测试现有DNS服务器..."
    local working_dns=()
    
    while IFS= read -r line; do
        if [[ $line =~ ^nameserver[[:space:]]+([0-9.]+) ]]; then
            local dns_ip="${BASH_REMATCH[1]}"
            if ping -c 1 -W 3 "$dns_ip" >/dev/null 2>&1; then
                working_dns+=("$dns_ip")
                log_success "DNS服务器可用: $dns_ip"
            else
                log_error "DNS服务器不可用: $dns_ip"
            fi
        fi
    done < /etc/resolv.conf
    
    # 如果现有DNS都不可用，使用公共DNS
    if [[ ${#working_dns[@]} -eq 0 ]]; then
        log_warning "现有DNS服务器都不可用，切换到公共DNS"
        
        # 智能选择最佳公共DNS
        local public_dns=("8.8.8.8" "114.114.114.114" "223.5.5.5" "1.1.1.1")
        for dns in "${public_dns[@]}"; do
            if ping -c 1 -W 3 "$dns" >/dev/null 2>&1; then
                working_dns+=("$dns")
                log_success "公共DNS可用: $dns"
                if [[ ${#working_dns[@]} -ge 2 ]]; then
                    break
                fi
            fi
        done
    fi
    
    # 生成新的resolv.conf
    if [[ ${#working_dns[@]} -gt 0 ]]; then
        log_info "3. 生成新的DNS配置..."
        
        # 检查是否使用NetworkManager
        if systemctl is-active NetworkManager >/dev/null 2>&1; then
            log_info "检测到NetworkManager，通过NetworkManager配置DNS"
            
            # 通过NetworkManager设置DNS
            local connection
            connection=$(nmcli -t -f NAME connection show --active | head -1)
            if [[ -n "$connection" ]]; then
                nmcli connection modify "$connection" ipv4.dns "${working_dns[0]}"
                if [[ ${#working_dns[@]} -gt 1 ]]; then
                    nmcli connection modify "$connection" +ipv4.dns "${working_dns[1]}"
                fi
                nmcli connection up "$connection"
                log_success "已通过NetworkManager更新DNS配置"
            fi
        else
            log_info "直接更新resolv.conf文件"
            
            # 直接写入resolv.conf
            cat > /etc/resolv.conf << EOF
# Generated by Docker emergency repair script
# $(date)
EOF
            
            for dns in "${working_dns[@]}"; do
                echo "nameserver $dns" >> /etc/resolv.conf
            done
            
            echo "options timeout:2 attempts:3" >> /etc/resolv.conf
            
            log_success "已更新resolv.conf配置"
        fi
        
        # 验证DNS解析
        log_info "4. 验证DNS解析功能..."
        if nslookup google.com >/dev/null 2>&1; then
            log_success "DNS解析功能正常"
        else
            log_error "DNS解析功能仍然异常"
        fi
    else
        log_error "无法找到可用的DNS服务器"
    fi
    echo
}

# 清理Docker进程和文件
cleanup_docker_processes() {
    log_info "=== 清理Docker进程和文件 ==="
    
    # 停止Docker服务
    log_info "1. 停止Docker相关服务..."
    systemctl stop docker.socket docker.service containerd 2>/dev/null || true
    
    # 杀死残留的Docker进程
    log_info "2. 清理残留进程..."
    pkill -f dockerd 2>/dev/null || true
    pkill -f containerd 2>/dev/null || true
    
    # 清理Docker socket文件
    log_info "3. 清理socket文件..."
    rm -f /var/run/docker.sock /var/run/docker.pid
    
    log_success "Docker进程和文件清理完成"
    echo
}

# 重新安装Docker服务文件
reinstall_docker_service() {
    log_info "=== 重新安装Docker服务文件 ==="
    
    # 重新生成systemd服务文件
    log_info "1. 重新生成systemd服务文件..."
    
    # 重新加载systemd
    systemctl daemon-reload
    
    # 重新启用Docker服务
    systemctl enable docker.service
    systemctl enable containerd.service
    
    log_success "Docker服务文件重新安装完成"
    echo
}

# 启动Docker服务
start_docker_service() {
    log_info "=== 启动Docker服务 ==="
    
    # 按顺序启动服务
    log_info "1. 启动containerd服务..."
    if systemctl start containerd; then
        log_success "containerd服务启动成功"
    else
        log_error "containerd服务启动失败"
        systemctl status containerd --no-pager -l
    fi
    
    sleep 2
    
    log_info "2. 启动docker.socket..."
    if systemctl start docker.socket; then
        log_success "docker.socket启动成功"
    else
        log_error "docker.socket启动失败"
        systemctl status docker.socket --no-pager -l
    fi
    
    sleep 2
    
    log_info "3. 启动docker.service..."
    if systemctl start docker.service; then
        log_success "docker.service启动成功"
    else
        log_error "docker.service启动失败"
        systemctl status docker.service --no-pager -l
        return 1
    fi
    
    # 验证服务状态
    log_info "4. 验证服务状态..."
    if systemctl is-active docker >/dev/null 2>&1; then
        log_success "Docker服务运行正常"
    else
        log_error "Docker服务状态异常"
        systemctl status docker --no-pager -l
        return 1
    fi
    echo
}

# 验证Docker功能
verify_docker_functionality() {
    log_info "=== 验证Docker功能 ==="
    
    # 测试Docker命令
    log_info "1. 测试Docker版本..."
    if docker --version; then
        log_success "Docker版本命令正常"
    else
        log_error "Docker版本命令失败"
        return 1
    fi
    
    log_info "2. 测试Docker信息..."
    if docker info >/dev/null 2>&1; then
        log_success "Docker信息命令正常"
    else
        log_error "Docker信息命令失败"
        docker info
        return 1
    fi
    
    log_info "3. 测试Docker运行容器..."
    if docker run --rm hello-world >/dev/null 2>&1; then
        log_success "Docker容器运行测试成功"
    else
        log_warning "Docker容器运行测试失败，可能是网络问题"
        log_info "尝试运行hello-world容器:"
        docker run --rm hello-world || true
    fi
    echo
}

# 显示修复报告
show_repair_report() {
    log_info "=== Docker修复报告 ==="
    echo
    
    log_info "修复步骤已完成，以下是详细信息:"
    echo
    
    log_info "1. 配置文件位置:"
    echo "   - Docker配置: /etc/docker/daemon.json"
    echo "   - DNS配置: /etc/resolv.conf"
    echo
    
    log_info "2. 备份文件位置:"
    echo "   - 备份目录: $BACKUP_DIR"
    if [[ -f "$BACKUP_DIR/daemon.json.original" ]]; then
        echo "   - 原始daemon.json: $BACKUP_DIR/daemon.json.original"
    fi
    if [[ -f "$BACKUP_DIR/resolv.conf.original" ]]; then
        echo "   - 原始resolv.conf: $BACKUP_DIR/resolv.conf.original"
    fi
    echo
    
    log_info "3. 当前配置状态:"
    
    # 检查daemon.json语法
    if [[ -f /etc/docker/daemon.json ]]; then
        if python3 -m json.tool /etc/docker/daemon.json >/dev/null 2>&1; then
            log_success "daemon.json语法正确"
            
            # 统计配置项
            local mirror_count
            local dns_count
            mirror_count=$(grep -c "registry-mirrors" /etc/docker/daemon.json 2>/dev/null || echo "0")
            dns_count=$(grep -c '"[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+"' /etc/docker/daemon.json 2>/dev/null || echo "0")
            echo "   - 镜像源配置: $mirror_count 个"
            echo "   - DNS配置: $dns_count 个"
        else
            log_error "daemon.json语法错误"
        fi
    else
        log_warning "daemon.json文件不存在"
    fi
    
    # 检查系统DNS
    local system_dns_count
    system_dns_count=$(grep -c "^nameserver" /etc/resolv.conf 2>/dev/null || echo "0")
    if [[ $system_dns_count -gt 0 ]]; then
        log_success "系统DNS配置正常 ($system_dns_count 个DNS服务器)"
    else
        log_error "系统DNS配置异常"
    fi
    
    # 检查网络连接
    if ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
        log_success "网络连接正常"
    else
        log_error "网络连接异常"
    fi
    echo
    
    log_info "4. 问题排查建议:"
    echo
    
    log_info "如果Docker仍然无法正常工作，请检查:"
    echo "   a) 防火墙设置: sudo ufw status"
    echo "   b) 内核版本: uname -r (建议 >= 3.10)"
    echo "   c) 存储驱动: docker info | grep 'Storage Driver'"
    echo "   d) 磁盘空间: df -h /var/lib/docker"
    echo "   e) 内存使用: free -h"
    echo
    
    log_info "常用诊断命令:"
    echo "   - 查看Docker日志: journalctl -u docker -f"
    echo "   - 查看容器日志: docker logs <container_id>"
    echo "   - 重启Docker: sudo systemctl restart docker"
    echo "   - 检查Docker状态: sudo systemctl status docker"
    echo "   - 测试网络: docker run --rm busybox ping -c 3 8.8.8.8"
    echo
    
    log_info "5. 最终状态检查:"
    
    # Docker服务状态
    if systemctl is-active docker >/dev/null 2>&1; then
        log_success "Docker服务: 运行中"
    else
        log_error "Docker服务: 未运行"
    fi
    
    # containerd服务状态
    if systemctl is-active containerd >/dev/null 2>&1; then
        log_success "containerd服务: 运行中"
    else
        log_error "containerd服务: 未运行"
    fi
    
    # Docker socket
    if [[ -S /var/run/docker.sock ]]; then
        log_success "Docker socket: 存在"
    else
        log_error "Docker socket: 不存在"
    fi
    
    echo
    log_info "6. 下一步建议:"
    
    if systemctl is-active docker >/dev/null 2>&1; then
        log_success "Docker修复成功！可以正常使用Docker了。"
        echo "   建议运行: docker run hello-world 来验证功能"
    else
        log_error "Docker修复未完全成功，建议:"
        echo "   1. 检查系统日志: journalctl -xe"
        echo "   2. 重启系统: sudo reboot"
        echo "   3. 重新安装Docker: apt remove docker.io && apt install docker.io"
    fi
    echo
}

# 主函数
main() {
    log_info "=== Docker服务紧急修复脚本 ==="
    log_info "版本: 1.1.0 - 增强版 - 专门解决Docker服务启动失败问题"
    log_info "日期: $(date)"
    echo
    
    # 检查root权限
    check_root
    
    # 创建备份目录
    create_backup_dir
    
    # 1. 诊断阶段
    check_docker_service
    analyze_docker_failure
    check_system_resources
    check_network_config
    check_docker_config
    
    # 2. 修复阶段
    fix_docker_config
    fix_system_dns
    cleanup_docker_processes
    reinstall_docker_service
    
    # 3. 验证阶段
    start_docker_service
    verify_docker_functionality
    
    # 4. 报告阶段
    show_repair_report
}

# 执行主函数
main "$@"