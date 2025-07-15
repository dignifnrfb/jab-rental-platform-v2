#!/bin/bash

# Docker服务紧急修复脚本
# 专门解决Docker服务启动失败和网络配置问题
# 作者: JAB租赁平台团队
# 版本: 1.1.0 - 增强版
# 日期: 2025-01-14
# 更新: 增强daemon.json语法检测和DNS诊断功能

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
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

log_debug() {
    echo -e "${PURPLE}[DEBUG]${NC} $1"
}

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要root权限运行"
        log_info "请使用: sudo $0"
        exit 1
    fi
}

# 创建备份目录
create_backup() {
    local backup_dir="/tmp/docker-emergency-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"
    
    # 备份关键配置文件
    [[ -f /etc/docker/daemon.json ]] && cp /etc/docker/daemon.json "$backup_dir/"
    [[ -f /etc/resolv.conf ]] && cp /etc/resolv.conf "$backup_dir/"
    [[ -f /etc/systemd/system/docker.service ]] && cp /etc/systemd/system/docker.service "$backup_dir/"
    
    echo "$backup_dir" > /tmp/docker-emergency-backup-path
    log_success "配置文件已备份到: $backup_dir"
}

# 检查Docker服务详细状态
check_docker_service_status() {
    log_info "=== Docker服务详细诊断 ==="
    
    # 检查Docker服务状态
    log_info "1. Docker服务状态:"
    systemctl status docker.service --no-pager -l || true
    echo
    
    # 检查Docker服务日志
    log_info "2. Docker服务最近日志:"
    journalctl -xeu docker.service --no-pager -l --since "10 minutes ago" || true
    echo
    
    # 检查Docker socket
    log_info "3. Docker socket状态:"
    if [[ -S /var/run/docker.sock ]]; then
        log_success "Docker socket存在"
        ls -la /var/run/docker.sock
    else
        log_error "Docker socket不存在"
    fi
    echo
    
    # 检查Docker进程
    log_info "4. Docker相关进程:"
    ps aux | grep -E "(docker|containerd)" | grep -v grep || log_warning "未找到Docker进程"
    echo
}

# 检查系统资源
check_system_resources() {
    log_info "=== 系统资源检查 ==="
    
    # 检查内存使用
    log_info "1. 内存使用情况:"
    free -h
    echo
    
    # 检查磁盘空间
    log_info "2. 磁盘空间使用:"
    df -h /var/lib/docker 2>/dev/null || df -h /
    echo
    
    # 检查系统负载
    log_info "3. 系统负载:"
    uptime
    echo
}

# 检查网络配置
check_network_config() {
    log_info "=== 网络配置检查 ==="
    
    # 检查网络接口
    log_info "1. 网络接口状态:"
    ip addr show || ifconfig -a
    echo
    
    # 检查路由表
    log_info "2. 路由表:"
    ip route show || route -n
    echo
    
    # 检查DNS配置
    log_info "3. DNS配置:"
    cat /etc/resolv.conf
    echo
    
    # 详细的网络连接测试
    log_info "4. 详细网络连接测试:"
    
    # 测试多个DNS服务器
    local dns_servers=("8.8.8.8" "114.114.114.114" "223.5.5.5" "1.1.1.1" "208.67.222.222")
    local working_dns_count=0
    
    for dns in "${dns_servers[@]}"; do
        log_info "测试DNS服务器: $dns"
        if timeout 5 ping -c 1 -W 3 "$dns" >/dev/null 2>&1; then
            log_success "DNS服务器可达: $dns"
            ((working_dns_count++))
            
            # 测试DNS解析功能
            if timeout 5 nslookup google.com "$dns" >/dev/null 2>&1; then
                log_success "DNS解析功能正常: $dns"
            else
                log_warning "DNS解析功能异常: $dns"
            fi
        else
            log_error "DNS服务器不可达: $dns"
        fi
    done
    
    if [[ $working_dns_count -eq 0 ]]; then
        log_error "所有DNS服务器都不可达，网络连接存在严重问题"
        
        # 检查网络接口是否up
        log_info "检查网络接口状态..."
        local active_interfaces
        active_interfaces=$(ip link show up | grep -E '^[0-9]+:' | grep -v 'lo:' | wc -l)
        
        if [[ $active_interfaces -eq 0 ]]; then
            log_error "没有活动的网络接口"
        else
            log_info "发现 $active_interfaces 个活动网络接口"
        fi
        
        # 检查默认路由
        if ip route show default >/dev/null 2>&1; then
            log_info "默认路由存在:"
            ip route show default
        else
            log_error "没有默认路由"
        fi
    else
        log_success "发现 $working_dns_count 个可用的DNS服务器"
    fi
    
    # 测试常用网站连接
    log_info "5. 测试常用网站连接:"
    local test_sites=("google.com" "baidu.com" "github.com")
    
    for site in "${test_sites[@]}"; do
        if timeout 10 curl -s --connect-timeout 5 "https://$site" >/dev/null 2>&1; then
            log_success "网站可访问: $site"
        else
            log_warning "网站不可访问: $site"
        fi
    done
    
    echo
}

# 检查Docker配置文件
check_docker_config() {
    log_info "=== Docker配置文件检查 ==="
    
    local daemon_json="/etc/docker/daemon.json"
    
    if [[ -f "$daemon_json" ]]; then
        log_info "1. daemon.json存在，检查语法:"
        
        # 详细的JSON语法检查
        local json_error_output
        json_error_output=$(python3 -m json.tool "$daemon_json" 2>&1)
        local json_exit_code=$?
        
        if [[ $json_exit_code -eq 0 ]]; then
            log_success "daemon.json语法正确"
            log_info "当前配置内容:"
            cat "$daemon_json"
            
            # 检查常见配置问题
            check_daemon_json_content "$daemon_json"
        else
            log_error "daemon.json语法错误"
            log_error "详细错误信息: $json_error_output"
            log_info "错误的配置内容:"
            cat "$daemon_json"
            
            # 尝试识别常见语法错误
            identify_json_syntax_errors "$daemon_json"
        fi
    else
        log_warning "daemon.json不存在"
    fi
    echo
}

# 检查daemon.json内容的常见问题
check_daemon_json_content() {
    local daemon_json="$1"
    
    log_info "2. 检查配置内容常见问题:"
    
    # 检查registry-mirrors配置
    if grep -q "registry-mirrors" "$daemon_json"; then
        log_info "发现registry-mirrors配置，检查镜像源有效性..."
        
        # 提取镜像源地址并测试
        local mirrors
        mirrors=$(python3 -c "
import json
with open('$daemon_json', 'r') as f:
    data = json.load(f)
    mirrors = data.get('registry-mirrors', [])
    for mirror in mirrors:
        print(mirror)
" 2>/dev/null || echo "")
        
        if [[ -n "$mirrors" ]]; then
            while IFS= read -r mirror; do
                if [[ -n "$mirror" ]]; then
                    log_info "测试镜像源: $mirror"
                    if curl -s --connect-timeout 5 "$mirror/v2/" >/dev/null 2>&1; then
                        log_success "镜像源可访问: $mirror"
                    else
                        log_warning "镜像源不可访问: $mirror"
                    fi
                fi
            done <<< "$mirrors"
        fi
    fi
    
    # 检查DNS配置
    if grep -q '"dns"' "$daemon_json"; then
        log_info "发现DNS配置，检查DNS服务器有效性..."
        local dns_servers
        dns_servers=$(python3 -c "
import json
with open('$daemon_json', 'r') as f:
    data = json.load(f)
    dns = data.get('dns', [])
    for server in dns:
        print(server)
" 2>/dev/null || echo "")
        
        if [[ -n "$dns_servers" ]]; then
            while IFS= read -r dns_server; do
                if [[ -n "$dns_server" ]]; then
                    log_info "测试DNS服务器: $dns_server"
                    if timeout 3 nslookup google.com "$dns_server" >/dev/null 2>&1; then
                        log_success "DNS服务器可用: $dns_server"
                    else
                        log_warning "DNS服务器不可用: $dns_server"
                    fi
                fi
            done <<< "$dns_servers"
        fi
    fi
}

# 识别JSON语法错误
identify_json_syntax_errors() {
    local daemon_json="$1"
    
    log_info "3. 分析常见JSON语法错误:"
    
    # 检查常见语法问题
    local line_num=1
    while IFS= read -r line; do
        # 检查多余的逗号
        if [[ "$line" =~ ,\s*[}\]] ]]; then
            log_warning "第${line_num}行: 发现多余的逗号 - $line"
        fi
        
        # 检查缺少逗号
        if [[ "$line" =~ \"[^\"]*\"\s*$ ]] && [[ $(sed -n "$((line_num+1))p" "$daemon_json") =~ ^\s*\" ]]; then
            log_warning "第${line_num}行: 可能缺少逗号 - $line"
        fi
        
        # 检查引号问题
        local quote_count
        quote_count=$(echo "$line" | grep -o '"' | wc -l)
        if [[ $((quote_count % 2)) -ne 0 ]]; then
            log_warning "第${line_num}行: 引号不匹配 - $line"
        fi
        
        ((line_num++))
    done < "$daemon_json"
    
    # 检查括号匹配
    local open_braces
    local close_braces
    open_braces=$(grep -o '{' "$daemon_json" | wc -l)
    close_braces=$(grep -o '}' "$daemon_json" | wc -l)
    
    if [[ $open_braces -ne $close_braces ]]; then
        log_warning "大括号不匹配: 开括号${open_braces}个，闭括号${close_braces}个"
    fi
    
    local open_brackets
    local close_brackets
    open_brackets=$(grep -o '\[' "$daemon_json" | wc -l)
    close_brackets=$(grep -o '\]' "$daemon_json" | wc -l)
    
    if [[ $open_brackets -ne $close_brackets ]]; then
        log_warning "方括号不匹配: 开括号${open_brackets}个，闭括号${close_brackets}个"
    fi
}

# 修复Docker配置文件
fix_docker_config() {
    log_info "=== 修复Docker配置 ==="
    
    local daemon_json="/etc/docker/daemon.json"
    
    # 移除可能有问题的配置文件
    if [[ -f "$daemon_json" ]]; then
        log_info "备份并移除当前daemon.json配置"
        mv "$daemon_json" "${daemon_json}.broken.$(date +%Y%m%d-%H%M%S)"
        log_success "已备份损坏的配置文件"
    fi
    
    # 创建Docker配置目录
    mkdir -p /etc/docker
    
    # 检测可用的镜像源和DNS
    log_info "检测可用的镜像源和DNS服务器..."
    
    # 测试镜像源
    local available_mirrors=()
    local test_mirrors=(
        "https://registry.cn-hangzhou.aliyuncs.com"
        "https://registry.cn-shanghai.aliyuncs.com"
        "https://registry.cn-beijing.aliyuncs.com"
        "https://mirror.ccs.tencentyun.com"
        "https://registry.cn-shenzhen.aliyuncs.com"
    )
    
    for mirror in "${test_mirrors[@]}"; do
        if timeout 10 curl -s --connect-timeout 5 "$mirror/v2/" >/dev/null 2>&1; then
            available_mirrors+=("$mirror")
            log_success "镜像源可用: $mirror"
        else
            log_warning "镜像源不可用: $mirror"
        fi
    done
    
    # 测试DNS服务器
    local available_dns=()
    local test_dns=("8.8.8.8" "114.114.114.114" "223.5.5.5" "1.1.1.1")
    
    for dns in "${test_dns[@]}"; do
        if timeout 5 ping -c 1 -W 3 "$dns" >/dev/null 2>&1; then
            available_dns+=("$dns")
            log_success "DNS服务器可用: $dns"
        else
            log_warning "DNS服务器不可用: $dns"
        fi
    done
    
    # 创建优化的Docker配置
    log_info "创建优化的Docker配置..."
    
    # 基础配置
    cat > "$daemon_json" << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "live-restore": true,
  "max-concurrent-downloads": 3,
  "max-concurrent-uploads": 3
EOF
    
    # 添加可用的镜像源
    if [[ ${#available_mirrors[@]} -gt 0 ]]; then
        echo '  ,"registry-mirrors": [' >> "$daemon_json"
        for i in "${!available_mirrors[@]}"; do
            if [[ $i -eq $((${#available_mirrors[@]} - 1)) ]]; then
                echo "    \"${available_mirrors[$i]}\"" >> "$daemon_json"
            else
                echo "    \"${available_mirrors[$i]}\"," >> "$daemon_json"
            fi
        done
        echo '  ]' >> "$daemon_json"
        log_success "添加了 ${#available_mirrors[@]} 个可用镜像源"
    fi
    
    # 添加可用的DNS服务器
    if [[ ${#available_dns[@]} -gt 0 ]]; then
        echo '  ,"dns": [' >> "$daemon_json"
        for i in "${!available_dns[@]}"; do
            if [[ $i -eq $((${#available_dns[@]} - 1)) ]]; then
                echo "    \"${available_dns[$i]}\"" >> "$daemon_json"
            else
                echo "    \"${available_dns[$i]}\"," >> "$daemon_json"
            fi
        done
        echo '  ]' >> "$daemon_json"
        log_success "添加了 ${#available_dns[@]} 个可用DNS服务器"
    fi
    
    # 结束JSON
    echo '}' >> "$daemon_json"
    
    # 验证生成的JSON语法
    if python3 -m json.tool "$daemon_json" >/dev/null 2>&1; then
        log_success "已创建优化的Docker配置，JSON语法正确"
        log_info "新配置内容:"
        cat "$daemon_json"
    else
        log_error "生成的JSON配置语法错误，使用最小化配置"
        cat > "$daemon_json" << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "live-restore": true
}
EOF
        log_info "回退到最小化配置:"
        cat "$daemon_json"
    fi
    
    echo
}

# 修复系统DNS配置
fix_system_dns() {
    log_info "=== 修复系统DNS配置 ==="
    
    # 备份原始DNS配置
    if [[ -f /etc/resolv.conf ]]; then
        local backup_path
        backup_path="$(cat /tmp/docker-emergency-backup-path 2>/dev/null || echo '/tmp')/resolv.conf.backup.$(date +%Y%m%d-%H%M%S)"
        cp /etc/resolv.conf "$backup_path"
        log_success "已备份原始DNS配置到: $backup_path"
    fi
    
    # 检测当前DNS配置问题
    log_info "分析当前DNS配置问题..."
    
    if [[ -f /etc/resolv.conf ]]; then
        log_info "当前DNS配置内容:"
        cat /etc/resolv.conf
        
        # 检查DNS服务器数量
        local dns_count
        dns_count=$(grep -c '^nameserver' /etc/resolv.conf 2>/dev/null || echo "0")
        log_info "发现 $dns_count 个DNS服务器"
        
        # 测试现有DNS服务器
        if [[ $dns_count -gt 0 ]]; then
            log_info "测试现有DNS服务器..."
            while IFS= read -r line; do
                if [[ $line =~ ^nameserver[[:space:]]+([0-9.]+) ]]; then
                    local dns_ip="${BASH_REMATCH[1]}"
                    log_info "测试DNS: $dns_ip"
                    if timeout 3 nslookup google.com "$dns_ip" >/dev/null 2>&1; then
                        log_success "DNS可用: $dns_ip"
                    else
                        log_error "DNS不可用: $dns_ip"
                    fi
                fi
            done < /etc/resolv.conf
        fi
    else
        log_warning "resolv.conf文件不存在"
    fi
    
    # 检测可用的DNS服务器
    log_info "检测可用的DNS服务器..."
    local available_dns=()
    local test_dns_servers=(
        "8.8.8.8"          # Google DNS
        "8.8.4.4"          # Google DNS 备用
        "114.114.114.114"  # 114 DNS
        "114.114.115.115"  # 114 DNS 备用
        "223.5.5.5"        # 阿里云 DNS
        "223.6.6.6"        # 阿里云 DNS 备用
        "1.1.1.1"          # Cloudflare DNS
        "1.0.0.1"          # Cloudflare DNS 备用
        "208.67.222.222"   # OpenDNS
        "208.67.220.220"   # OpenDNS 备用
    )
    
    for dns in "${test_dns_servers[@]}"; do
        log_info "测试DNS服务器: $dns"
        if timeout 5 ping -c 1 -W 3 "$dns" >/dev/null 2>&1; then
            # 进一步测试DNS解析功能
            if timeout 5 nslookup google.com "$dns" >/dev/null 2>&1; then
                available_dns+=("$dns")
                log_success "DNS服务器可用: $dns"
            else
                log_warning "DNS服务器可达但解析功能异常: $dns"
            fi
        else
            log_error "DNS服务器不可达: $dns"
        fi
    done
    
    if [[ ${#available_dns[@]} -eq 0 ]]; then
        log_error "没有找到可用的DNS服务器，网络连接存在严重问题"
        log_warning "将使用默认DNS配置，但可能无法正常工作"
        
        # 创建基本的DNS配置
        cat > /etc/resolv.conf << 'EOF'
# Docker修复脚本生成的基本DNS配置（网络问题时的回退配置）
nameserver 8.8.8.8
nameserver 114.114.114.114
options timeout:5 attempts:2
EOF
    else
        log_success "发现 ${#available_dns[@]} 个可用的DNS服务器"
        
        # 创建优化的DNS配置
        log_info "创建优化的DNS配置..."
        
        cat > /etc/resolv.conf << 'EOF'
# Docker修复脚本生成的优化DNS配置
EOF
        
        # 添加可用的DNS服务器（最多5个）
        local dns_added=0
        for dns in "${available_dns[@]}"; do
            if [[ $dns_added -lt 5 ]]; then
                echo "nameserver $dns" >> /etc/resolv.conf
                ((dns_added++))
            fi
        done
        
        # 添加优化选项
        cat >> /etc/resolv.conf << 'EOF'
options timeout:2 attempts:3 rotate single-request-reopen
EOF
        
        log_success "已配置 $dns_added 个可用的DNS服务器"
    fi
    
    # 检查NetworkManager是否在管理DNS
    if systemctl is-active NetworkManager >/dev/null 2>&1; then
        log_info "检测到NetworkManager正在运行"
        
        # 检查是否需要配置NetworkManager
        if [[ -f /etc/NetworkManager/NetworkManager.conf ]]; then
            if ! grep -q "dns=none" /etc/NetworkManager/NetworkManager.conf; then
                log_info "配置NetworkManager不管理DNS..."
                
                # 备份NetworkManager配置
                local nm_backup_path
                nm_backup_path="$(cat /tmp/docker-emergency-backup-path 2>/dev/null || echo '/tmp')/NetworkManager.conf.backup.$(date +%Y%m%d-%H%M%S)"
                cp /etc/NetworkManager/NetworkManager.conf "$nm_backup_path"
                
                # 添加dns=none配置
                if grep -q "\[main\]" /etc/NetworkManager/NetworkManager.conf; then
                    sed -i '/\[main\]/a dns=none' /etc/NetworkManager/NetworkManager.conf
                else
                    echo -e "\n[main]\ndns=none" >> /etc/NetworkManager/NetworkManager.conf
                fi
                
                log_success "已配置NetworkManager不管理DNS"
                log_info "重启NetworkManager以应用配置..."
                systemctl restart NetworkManager || log_warning "NetworkManager重启失败"
            else
                log_info "NetworkManager已配置为不管理DNS"
            fi
        fi
    fi
    
    # 验证DNS配置
    log_info "验证DNS配置..."
    log_info "最终DNS配置:"
    cat /etc/resolv.conf
    
    # 测试DNS解析
    log_info "测试DNS解析功能..."
    local test_domains=("google.com" "baidu.com" "github.com")
    local resolved_count=0
    
    for domain in "${test_domains[@]}"; do
        if timeout 10 nslookup "$domain" >/dev/null 2>&1; then
            log_success "DNS解析成功: $domain"
            ((resolved_count++))
        else
            log_warning "DNS解析失败: $domain"
        fi
    done
    
    if [[ $resolved_count -gt 0 ]]; then
        log_success "DNS配置修复成功，$resolved_count/$((${#test_domains[@]})) 个域名解析正常"
    else
        log_error "DNS配置修复失败，所有域名解析都失败"
    fi
    
    echo
}

# 清理Docker相关进程和文件
clean_docker_processes() {
    log_info "=== 清理Docker进程和文件 ==="
    
    # 停止所有Docker相关服务
    log_info "停止Docker相关服务..."
    systemctl stop docker.socket docker.service containerd.service 2>/dev/null || true
    
    # 等待进程完全停止
    sleep 5
    
    # 强制杀死残留进程
    log_info "清理残留进程..."
    pkill -f docker 2>/dev/null || true
    pkill -f containerd 2>/dev/null || true
    
    # 清理Docker socket
    log_info "清理Docker socket..."
    rm -f /var/run/docker.sock /var/run/docker.pid
    
    log_success "Docker进程和文件清理完成"
    echo
}

# 重新安装Docker服务文件
reinstall_docker_service() {
    log_info "=== 重新安装Docker服务文件 ==="
    
    # 检查Docker是否已安装
    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker未安装，请先安装Docker"
        return 1
    fi
    
    # 重新生成systemd服务文件
    log_info "重新生成Docker systemd服务文件..."
    
    # 删除可能损坏的服务文件
    rm -f /etc/systemd/system/docker.service
    rm -f /etc/systemd/system/docker.socket
    
    # 重新加载systemd
    systemctl daemon-reload
    
    # 重新启用Docker服务
    systemctl enable docker.service
    systemctl enable docker.socket
    
    log_success "Docker服务文件重新安装完成"
    echo
}

# 启动Docker服务
start_docker_service() {
    log_info "=== 启动Docker服务 ==="
    
    # 重新加载systemd配置
    systemctl daemon-reload
    
    # 启动containerd服务
    log_info "启动containerd服务..."
    systemctl start containerd.service || log_warning "containerd启动失败"
    
    # 启动Docker socket
    log_info "启动Docker socket..."
    systemctl start docker.socket || log_warning "Docker socket启动失败"
    
    # 启动Docker服务
    log_info "启动Docker服务..."
    if systemctl start docker.service; then
        log_success "Docker服务启动成功"
    else
        log_error "Docker服务启动失败"
        log_info "查看详细错误信息:"
        journalctl -xeu docker.service --no-pager -l --since "1 minute ago"
        return 1
    fi
    
    # 等待服务完全启动
    sleep 10
    
    # 验证服务状态
    if systemctl is-active --quiet docker; then
        log_success "Docker服务运行正常"
    else
        log_error "Docker服务状态异常"
        return 1
    fi
    
    echo
}

# 验证Docker功能
verify_docker_functionality() {
    log_info "=== 验证Docker功能 ==="
    
    # 测试Docker基本命令
    log_info "1. 测试Docker版本:"
    if docker --version; then
        log_success "Docker版本命令正常"
    else
        log_error "Docker版本命令失败"
        return 1
    fi
    
    # 测试Docker信息
    log_info "2. 测试Docker信息:"
    if timeout 30 docker info >/dev/null 2>&1; then
        log_success "Docker信息命令正常"
    else
        log_error "Docker信息命令失败"
        return 1
    fi
    
    # 测试简单容器运行
    log_info "3. 测试容器运行:"
    if timeout 60 docker run --rm hello-world >/dev/null 2>&1; then
        log_success "容器运行测试成功"
    else
        log_warning "容器运行测试失败，可能是网络问题"
    fi
    
    echo
}

# 显示修复报告
show_repair_report() {
    log_info "=== Docker紧急修复报告 ==="
    echo
    
    log_info "修复步骤完成情况:"
    echo "✓ 1. 系统诊断和资源检查"
    echo "✓ 2. 网络配置检查和修复（增强版DNS诊断）"
    echo "✓ 3. Docker配置文件修复（增强版语法检测）"
    echo "✓ 4. 系统DNS配置修复（智能DNS检测）"
    echo "✓ 5. Docker进程清理"
    echo "✓ 6. Docker服务文件重新安装"
    echo "✓ 7. Docker服务启动"
    echo "✓ 8. Docker功能验证"
    echo
    
    log_info "重要文件位置:"
    echo "• Docker配置: /etc/docker/daemon.json"
    echo "• DNS配置: /etc/resolv.conf"
    echo "• Docker服务: /lib/systemd/system/docker.service"
    local backup_dir
    backup_dir="$(cat /tmp/docker-emergency-backup-path 2>/dev/null || echo '未创建备份')"
    echo "• 备份目录: $backup_dir"
    echo
    
    # 显示当前配置状态
    log_info "当前配置状态:"
    
    # 检查daemon.json状态
    if [[ -f /etc/docker/daemon.json ]]; then
        if python3 -m json.tool /etc/docker/daemon.json >/dev/null 2>&1; then
            echo "• daemon.json: ✓ 语法正确"
            
            # 检查镜像源数量
            local mirror_count
            mirror_count=$(python3 -c "import json; data=json.load(open('/etc/docker/daemon.json')); print(len(data.get('registry-mirrors', [])))" 2>/dev/null || echo "0")
            echo "  - 配置了 $mirror_count 个镜像源"
            
            # 检查DNS数量
            local dns_count
            dns_count=$(python3 -c "import json; data=json.load(open('/etc/docker/daemon.json')); print(len(data.get('dns', [])))" 2>/dev/null || echo "0")
            echo "  - 配置了 $dns_count 个DNS服务器"
        else
            echo "• daemon.json: ✗ 语法错误"
        fi
    else
        echo "• daemon.json: ✗ 文件不存在"
    fi
    
    # 检查DNS配置状态
    if [[ -f /etc/resolv.conf ]]; then
        local system_dns_count
        system_dns_count=$(grep -c '^nameserver' /etc/resolv.conf 2>/dev/null || echo "0")
        echo "• 系统DNS: ✓ 配置了 $system_dns_count 个DNS服务器"
    else
        echo "• 系统DNS: ✗ resolv.conf不存在"
    fi
    
    # 检查网络连接状态
    if timeout 5 ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
        echo "• 网络连接: ✓ 正常"
    else
        echo "• 网络连接: ✗ 异常"
    fi
    
    echo
    
    log_info "如果问题仍然存在，请按以下顺序检查:"
    echo "1. 网络连接问题:"
    echo "   • 检查网络接口: ip addr show"
    echo "   • 检查路由表: ip route show"
    echo "   • 测试网络: ping 8.8.8.8"
    echo "2. DNS解析问题:"
    echo "   • 测试DNS: nslookup google.com"
    echo "   • 检查DNS配置: cat /etc/resolv.conf"
    echo "3. Docker配置问题:"
    echo "   • 检查配置语法: python3 -m json.tool /etc/docker/daemon.json"
    echo "   • 查看Docker日志: journalctl -xeu docker.service"
    echo "4. 系统资源问题:"
    echo "   • 检查磁盘空间: df -h"
    echo "   • 检查内存使用: free -h"
    echo "   • 检查系统负载: uptime"
    echo "5. 权限和安全问题:"
    echo "   • 检查防火墙: sudo ufw status"
    echo "   • 检查SELinux: sestatus"
    echo "   • 检查Docker组: groups \$USER"
    echo
    
    log_info "常用诊断命令:"
    echo "• 检查Docker状态: systemctl status docker"
    echo "• 查看详细日志: journalctl -xeu docker.service --no-pager"
    echo "• 测试Docker功能: docker run hello-world"
    echo "• 检查Docker信息: docker info"
    echo "• 重启Docker服务: sudo systemctl restart docker"
    echo
    
    # 最终状态检查
    log_info "最终状态检查:"
    if systemctl is-active docker >/dev/null 2>&1; then
        log_success "✓ Docker服务状态: 运行中"
        
        # 尝试运行简单的Docker命令
        if timeout 30 docker version >/dev/null 2>&1; then
            log_success "✓ Docker命令响应: 正常"
        else
            log_warning "⚠ Docker命令响应: 超时或异常"
        fi
        
        # 检查Docker daemon连接
        if timeout 10 docker info >/dev/null 2>&1; then
            log_success "✓ Docker daemon连接: 正常"
        else
            log_warning "⚠ Docker daemon连接: 异常"
        fi
    else
        log_error "✗ Docker服务状态: 未运行"
        log_info "建议手动执行: sudo systemctl start docker"
    fi
    
    echo
    log_info "修复完成时间: $(date)"
    log_info "备份文件位置: $backup_dir"
    
    # 提供下一步建议
    echo
    log_info "下一步建议:"
    if systemctl is-active docker >/dev/null 2>&1; then
        echo "1. 测试Docker功能: docker run hello-world"
        echo "2. 拉取常用镜像: docker pull nginx:alpine"
        echo "3. 检查镜像源速度: time docker pull hello-world"
    else
        echo "1. 手动启动Docker: sudo systemctl start docker"
        echo "2. 查看启动日志: journalctl -xeu docker.service"
        echo "3. 如果仍然失败，考虑重新安装Docker"
    fi
    
    echo
    log_success "紧急修复脚本执行完成！"
}

# 主函数
main() {
    echo "=== Docker服务紧急修复脚本 ==="
    echo "版本: 1.1.0 - 增强版 - 专门解决Docker服务启动失败问题"
    echo "日期: $(date)"
    echo
    
    # 检查权限
    check_root
    
    # 创建备份
    create_backup
    
    # 详细诊断
    check_docker_service_status
    check_system_resources
    check_network_config
    check_docker_config
    
    echo
    log_info "开始紧急修复..."
    echo
    
    # 执行修复步骤
    fix_docker_config
    fix_system_dns
    clean_docker_processes
    reinstall_docker_service
    start_docker_service
    
    echo
    log_info "修复完成，开始验证..."
    echo
    
    # 验证修复结果
    verify_docker_functionality
    
    echo
    # 显示报告
    show_repair_report
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi