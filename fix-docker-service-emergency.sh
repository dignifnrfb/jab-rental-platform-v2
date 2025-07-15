#!/bin/bash

# Docker服务紧急修复脚本
# 专门解决Docker服务启动失败和网络配置问题
# 作者: JAB租赁平台团队
# 版本: 1.0.0
# 日期: 2025-01-14

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
    
    # 测试基本网络连接
    log_info "4. 网络连接测试:"
    if ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
        log_success "外网连接正常"
    else
        log_error "外网连接失败"
    fi
    
    if ping -c 1 -W 3 114.114.114.114 >/dev/null 2>&1; then
        log_success "备用DNS连接正常"
    else
        log_error "备用DNS连接失败"
    fi
    echo
}

# 检查Docker配置文件
check_docker_config() {
    log_info "=== Docker配置文件检查 ==="
    
    local daemon_json="/etc/docker/daemon.json"
    
    if [[ -f "$daemon_json" ]]; then
        log_info "1. daemon.json存在，检查语法:"
        if python3 -m json.tool "$daemon_json" >/dev/null 2>&1; then
            log_success "daemon.json语法正确"
            log_info "当前配置内容:"
            cat "$daemon_json"
        else
            log_error "daemon.json语法错误"
            log_info "错误的配置内容:"
            cat "$daemon_json"
        fi
    else
        log_warning "daemon.json不存在"
    fi
    echo
}

# 修复Docker配置文件
fix_docker_config() {
    log_info "=== 修复Docker配置 ==="
    
    local daemon_json="/etc/docker/daemon.json"
    
    # 移除可能有问题的配置文件
    if [[ -f "$daemon_json" ]]; then
        log_info "移除当前daemon.json配置"
        mv "$daemon_json" "${daemon_json}.broken.$(date +%Y%m%d-%H%M%S)"
    fi
    
    # 创建最小化的安全配置
    mkdir -p /etc/docker
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
    
    log_success "已创建最小化Docker配置"
    log_info "新配置内容:"
    cat "$daemon_json"
    echo
}

# 修复系统DNS配置
fix_system_dns() {
    log_info "=== 修复系统DNS配置 ==="
    
    # 备份当前DNS配置
    cp /etc/resolv.conf /etc/resolv.conf.emergency.backup.$(date +%Y%m%d-%H%M%S)
    
    # 创建基本DNS配置
    cat > /etc/resolv.conf << 'EOF'
nameserver 8.8.8.8
nameserver 114.114.114.114
nameserver 223.5.5.5
options timeout:2 attempts:3
EOF
    
    log_success "已更新系统DNS配置"
    log_info "新DNS配置:"
    cat /etc/resolv.conf
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
show_emergency_report() {
    log_info "=== Docker紧急修复报告 ==="
    echo
    log_info "修复步骤:"
    echo "  ✓ 系统资源检查"
    echo "  ✓ 网络配置检查"
    echo "  ✓ Docker配置文件修复"
    echo "  ✓ 系统DNS配置修复"
    echo "  ✓ Docker进程清理"
    echo "  ✓ Docker服务重新安装"
    echo "  ✓ Docker服务启动"
    echo "  ✓ Docker功能验证"
    echo
    log_info "配置文件位置:"
    echo "  - Docker配置: /etc/docker/daemon.json"
    echo "  - DNS配置: /etc/resolv.conf"
    echo "  - 备份位置: $(cat /tmp/docker-emergency-backup-path 2>/dev/null || echo '未创建备份')"
    echo
    log_info "如果问题仍然存在，请检查:"
    echo "  1. 系统防火墙设置 (iptables/firewalld)"
    echo "  2. SELinux状态和策略"
    echo "  3. 系统内核版本兼容性"
    echo "  4. 磁盘空间和inode使用情况"
    echo "  5. 系统日志中的相关错误信息"
    echo
    log_info "手动诊断命令:"
    echo "  - systemctl status docker.service"
    echo "  - journalctl -xeu docker.service"
    echo "  - docker info"
    echo "  - docker version"
    echo
    log_success "紧急修复脚本执行完成！"
}

# 主函数
main() {
    echo "=== Docker服务紧急修复脚本 ==="
    echo "版本: 1.0.0 - 专门解决Docker服务启动失败问题"
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
    show_emergency_report
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi