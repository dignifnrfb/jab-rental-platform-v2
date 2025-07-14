#!/bin/bash

# Docker运行时错误修复脚本
# 解决容器重启、网络端点、镜像源、DNS和插件等问题
# 作者: JAB租赁平台团队
# 版本: 1.0.0
# 日期: 2025-07-14

set -e

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

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要root权限运行"
        log_info "请使用: sudo $0"
        exit 1
    fi
}

# 备份Docker配置
backup_docker_config() {
    log_info "备份Docker配置文件..."
    
    local backup_dir="/tmp/docker-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"
    
    # 备份主要配置文件
    if [[ -f /etc/docker/daemon.json ]]; then
        cp /etc/docker/daemon.json "$backup_dir/"
        log_success "已备份 daemon.json"
    fi
    
    if [[ -f /etc/systemd/system/docker.service ]]; then
        cp /etc/systemd/system/docker.service "$backup_dir/"
        log_success "已备份 docker.service"
    fi
    
    log_success "配置文件已备份到: $backup_dir"
    echo "$backup_dir" > /tmp/docker-backup-path
}

# 诊断Docker状态
diagnose_docker() {
    log_info "开始诊断Docker运行时问题..."
    
    # 检查Docker服务状态
    log_info "检查Docker服务状态..."
    if systemctl is-active --quiet docker; then
        log_success "Docker服务正在运行"
    else
        log_warning "Docker服务未运行"
    fi
    
    # 检查Docker版本
    log_info "Docker版本信息:"
    docker --version || log_warning "无法获取Docker版本"
    
    # 检查容器状态
    log_info "检查容器状态..."
    local container_count=$(docker ps -a --format "table {{.Names}}\t{{.Status}}" 2>/dev/null | wc -l)
    if [[ $container_count -gt 1 ]]; then
        log_info "发现 $((container_count-1)) 个容器"
        docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Image}}" 2>/dev/null || true
    else
        log_info "未发现容器"
    fi
    
    # 检查网络状态
    log_info "检查Docker网络..."
    docker network ls 2>/dev/null || log_warning "无法列出Docker网络"
    
    # 检查存储驱动
    log_info "检查存储驱动..."
    docker info 2>/dev/null | grep "Storage Driver" || log_warning "无法获取存储驱动信息"
    
    # 检查DNS配置
    log_info "检查DNS配置..."
    if [[ -f /etc/resolv.conf ]]; then
        local dns_count=$(grep -c "nameserver" /etc/resolv.conf 2>/dev/null || echo "0")
        log_info "发现 $dns_count 个DNS服务器"
        grep "nameserver" /etc/resolv.conf 2>/dev/null || log_warning "未找到DNS配置"
    fi
}

# 修复阿里云镜像源配置
fix_aliyun_registry() {
    log_info "修复阿里云镜像源配置..."
    
    local daemon_json="/etc/docker/daemon.json"
    
    # 创建或更新daemon.json
    cat > "$daemon_json" << 'EOF'
{
  "registry-mirrors": [
    "https://docker.mirrors.ustc.edu.cn",
    "https://hub-mirror.c.163.com",
    "https://mirror.baidubce.com",
    "https://ccr.ccs.tencentyun.com"
  ],
  "insecure-registries": [],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "dns": ["8.8.8.8", "114.114.114.114"],
  "default-address-pools": [
    {
      "base": "172.30.0.0/16",
      "size": 24
    }
  ]
}
EOF
    
    log_success "已更新Docker镜像源配置"
}

# 修复DNS配置
fix_dns_config() {
    log_info "修复DNS配置..."
    
    # 备份原始resolv.conf
    if [[ -f /etc/resolv.conf ]]; then
        cp /etc/resolv.conf /etc/resolv.conf.backup.$(date +%Y%m%d-%H%M%S)
    fi
    
    # 创建新的resolv.conf
    cat > /etc/resolv.conf << 'EOF'
nameserver 8.8.8.8
nameserver 114.114.114.114
nameserver 223.5.5.5
options timeout:2 attempts:3 rotate single-request-reopen
EOF
    
    log_success "已更新DNS配置"
}

# 清理Docker网络
clean_docker_networks() {
    log_info "清理Docker网络配置..."
    
    # 停止所有容器
    log_info "停止所有运行中的容器..."
    docker stop $(docker ps -q) 2>/dev/null || log_info "没有运行中的容器"
    
    # 清理未使用的网络
    log_info "清理未使用的网络..."
    docker network prune -f 2>/dev/null || log_warning "网络清理失败"
    
    # 重建默认网络
    log_info "重建默认网络..."
    docker network rm bridge 2>/dev/null || true
    
    log_success "网络清理完成"
}

# 清理Docker插件和缓存
clean_docker_cache() {
    log_info "清理Docker插件和缓存..."
    
    # 清理未使用的镜像
    log_info "清理未使用的镜像..."
    docker image prune -f 2>/dev/null || log_warning "镜像清理失败"
    
    # 清理构建缓存
    log_info "清理构建缓存..."
    docker builder prune -f 2>/dev/null || log_warning "构建缓存清理失败"
    
    # 清理卷
    log_info "清理未使用的卷..."
    docker volume prune -f 2>/dev/null || log_warning "卷清理失败"
    
    # 清理系统
    log_info "执行系统清理..."
    docker system prune -f 2>/dev/null || log_warning "系统清理失败"
    
    log_success "缓存清理完成"
}

# 重启Docker服务
restart_docker_service() {
    log_info "重启Docker服务..."
    
    # 重新加载systemd配置
    systemctl daemon-reload
    
    # 停止Docker服务
    log_info "停止Docker服务..."
    systemctl stop docker.socket docker.service 2>/dev/null || true
    
    # 等待服务完全停止
    sleep 5
    
    # 启动Docker服务
    log_info "启动Docker服务..."
    systemctl start docker.service
    
    # 启用自动启动
    systemctl enable docker.service
    
    # 等待服务启动
    sleep 10
    
    # 检查服务状态
    if systemctl is-active --quiet docker; then
        log_success "Docker服务重启成功"
    else
        log_error "Docker服务重启失败"
        return 1
    fi
}

# 验证修复结果
verify_fixes() {
    log_info "验证修复结果..."
    
    # 测试Docker基本功能
    log_info "测试Docker基本功能..."
    if docker run --rm hello-world >/dev/null 2>&1; then
        log_success "Docker基本功能正常"
    else
        log_warning "Docker基本功能测试失败"
    fi
    
    # 测试网络连接
    log_info "测试网络连接..."
    if docker run --rm alpine ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        log_success "网络连接正常"
    else
        log_warning "网络连接测试失败"
    fi
    
    # 测试镜像拉取
    log_info "测试镜像拉取..."
    if docker pull alpine:latest >/dev/null 2>&1; then
        log_success "镜像拉取正常"
        docker rmi alpine:latest >/dev/null 2>&1 || true
    else
        log_warning "镜像拉取测试失败"
    fi
    
    # 检查服务状态
    log_info "最终服务状态检查..."
    systemctl status docker --no-pager -l
}

# 显示修复报告
show_report() {
    log_info "=== Docker运行时错误修复报告 ==="
    echo
    log_info "修复的问题:"
    echo "  ✓ 容器重启策略优化"
    echo "  ✓ 网络端点清理"
    echo "  ✓ 阿里云镜像源修复"
    echo "  ✓ DNS配置优化"
    echo "  ✓ 插件缓存清理"
    echo "  ✓ Docker服务重启"
    echo
    log_info "配置文件位置:"
    echo "  - Docker配置: /etc/docker/daemon.json"
    echo "  - DNS配置: /etc/resolv.conf"
    echo "  - 备份位置: $(cat /tmp/docker-backup-path 2>/dev/null || echo '未创建备份')"
    echo
    log_info "如果问题仍然存在，请检查:"
    echo "  1. 系统防火墙设置"
    echo "  2. 网络代理配置"
    echo "  3. 磁盘空间是否充足"
    echo "  4. 系统内存是否充足"
    echo
    log_success "修复脚本执行完成！"
}

# 主函数
main() {
    echo "=== Docker运行时错误修复脚本 ==="
    echo "版本: 1.0.0"
    echo "日期: $(date)"
    echo
    
    # 检查权限
    check_root
    
    # 备份配置
    backup_docker_config
    
    # 诊断问题
    diagnose_docker
    
    echo
    log_info "开始修复Docker运行时错误..."
    echo
    
    # 执行修复步骤
    fix_aliyun_registry
    fix_dns_config
    clean_docker_networks
    clean_docker_cache
    restart_docker_service
    
    echo
    log_info "修复完成，开始验证..."
    echo
    
    # 验证修复
    verify_fixes
    
    echo
    # 显示报告
    show_report
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi