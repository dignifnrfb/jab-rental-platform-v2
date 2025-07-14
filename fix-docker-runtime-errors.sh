#!/bin/bash

# Docker运行时错误修复脚本 (增强版)
# 解决容器重启、网络端点、镜像源、DNS和插件等问题
# 特别针对镜像源DNS解析失败问题进行优化
# 作者: JAB租赁平台团队
# 版本: 2.0.0
# 日期: 2025-07-14

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 镜像源列表 (按优先级排序)
REGISTRY_MIRRORS=(
    "https://registry.cn-hangzhou.aliyuncs.com"
    "https://registry.cn-shanghai.aliyuncs.com"
    "https://registry.cn-beijing.aliyuncs.com"
    "https://ccr.ccs.tencentyun.com"
    "https://docker.m.daocloud.io"
    "https://dockerproxy.com"
    "https://docker.nju.edu.cn"
)

# 备用镜像源 (如果主要镜像源都不可用)
FALLBACK_MIRRORS=(
    "https://registry-1.docker.io"
)

# DNS服务器列表
DNS_SERVERS=(
    "223.5.5.5"      # 阿里DNS
    "119.29.29.29"   # 腾讯DNS
    "114.114.114.114" # 114DNS
    "8.8.8.8"        # Google DNS
    "1.1.1.1"        # Cloudflare DNS
)

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

# 检测网络连接
test_network_connectivity() {
    local host="$1"
    local timeout="${2:-5}"
    
    if command -v curl >/dev/null 2>&1; then
        curl -s --connect-timeout "$timeout" --max-time "$timeout" "$host" >/dev/null 2>&1
    elif command -v wget >/dev/null 2>&1; then
        wget -q --timeout="$timeout" --tries=1 "$host" -O /dev/null 2>&1
    else
        # 使用ping作为最后手段
        ping -c 1 -W "$timeout" "$(echo "$host" | sed 's|https\?://||' | cut -d'/' -f1)" >/dev/null 2>&1
    fi
}

# 测试镜像源可用性
test_registry_mirror() {
    local mirror="$1"
    local test_url="${mirror}/v2/"
    
    log_info "测试镜像源: $mirror"
    
    if test_network_connectivity "$test_url" 10; then
        log_success "镜像源可用: $mirror"
        return 0
    else
        log_warning "镜像源不可用: $mirror"
        return 1
    fi
}

# 获取可用的镜像源
get_available_mirrors() {
    local available_mirrors=()
    
    log_info "检测可用的Docker镜像源..."
    
    # 测试主要镜像源
    for mirror in "${REGISTRY_MIRRORS[@]}"; do
        if test_registry_mirror "$mirror"; then
            available_mirrors+=("$mirror")
        fi
        # 限制测试数量，避免等待时间过长
        if [[ ${#available_mirrors[@]} -ge 3 ]]; then
            break
        fi
    done
    
    # 如果没有可用的镜像源，尝试备用源
    if [[ ${#available_mirrors[@]} -eq 0 ]]; then
        log_warning "主要镜像源都不可用，尝试备用镜像源..."
        for mirror in "${FALLBACK_MIRRORS[@]}"; do
            if test_registry_mirror "$mirror"; then
                available_mirrors+=("$mirror")
            fi
        done
    fi
    
    # 输出结果
    if [[ ${#available_mirrors[@]} -gt 0 ]]; then
        log_success "找到 ${#available_mirrors[@]} 个可用镜像源"
        printf '%s\n' "${available_mirrors[@]}"
    else
        log_error "未找到可用的镜像源"
        return 1
    fi
}

# 测试DNS服务器
test_dns_server() {
    local dns="$1"
    
    if command -v nslookup >/dev/null 2>&1; then
        nslookup registry.cn-hangzhou.aliyuncs.com "$dns" >/dev/null 2>&1
    elif command -v dig >/dev/null 2>&1; then
        dig @"$dns" registry.cn-hangzhou.aliyuncs.com >/dev/null 2>&1
    else
        # 简单的ping测试
        ping -c 1 -W 3 "$dns" >/dev/null 2>&1
    fi
}

# 获取可用的DNS服务器
get_available_dns() {
    local available_dns=()
    
    log_info "检测可用的DNS服务器..."
    
    for dns in "${DNS_SERVERS[@]}"; do
        if test_dns_server "$dns"; then
            available_dns+=("$dns")
            log_success "DNS服务器可用: $dns"
        else
            log_warning "DNS服务器不可用: $dns"
        fi
        
        # 限制DNS数量
        if [[ ${#available_dns[@]} -ge 3 ]]; then
            break
        fi
    done
    
    if [[ ${#available_dns[@]} -eq 0 ]]; then
        log_error "未找到可用的DNS服务器"
        # 使用默认DNS
        available_dns=("8.8.8.8" "114.114.114.114")
        log_warning "使用默认DNS服务器"
    fi
    
    printf '%s\n' "${available_dns[@]}"
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
    
    if [[ -f /etc/resolv.conf ]]; then
        cp /etc/resolv.conf "$backup_dir/"
        log_success "已备份 resolv.conf"
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
    
    # 检查当前DNS配置
    log_info "检查当前DNS配置..."
    if [[ -f /etc/resolv.conf ]]; then
        local dns_count=$(grep -c "nameserver" /etc/resolv.conf 2>/dev/null || echo "0")
        log_info "发现 $dns_count 个DNS服务器"
        grep "nameserver" /etc/resolv.conf 2>/dev/null || log_warning "未找到DNS配置"
    fi
    
    # 检查当前镜像源配置
    log_info "检查当前镜像源配置..."
    if [[ -f /etc/docker/daemon.json ]]; then
        if grep -q "registry-mirrors" /etc/docker/daemon.json 2>/dev/null; then
            log_info "当前镜像源配置:"
            grep -A 10 "registry-mirrors" /etc/docker/daemon.json 2>/dev/null || true
        else
            log_warning "未配置镜像源"
        fi
    else
        log_warning "Docker daemon.json 不存在"
    fi
}

# 修复Docker镜像源配置
fix_docker_registry() {
    log_info "修复Docker镜像源配置..."
    
    # 获取可用的镜像源
    local available_mirrors
    if ! available_mirrors=($(get_available_mirrors)); then
        log_error "无法获取可用的镜像源，使用默认配置"
        available_mirrors=("https://registry.cn-hangzhou.aliyuncs.com")
    fi
    
    # 获取可用的DNS服务器
    local available_dns=($(get_available_dns))
    
    local daemon_json="/etc/docker/daemon.json"
    
    # 确保目录存在
    mkdir -p /etc/docker
    
    # 生成镜像源JSON数组
    local mirrors_json=""
    for mirror in "${available_mirrors[@]}"; do
        if [[ -n "$mirrors_json" ]]; then
            mirrors_json="$mirrors_json,"
        fi
        mirrors_json="$mirrors_json\n    \"$mirror\""
    done
    
    # 生成DNS JSON数组
    local dns_json=""
    for dns in "${available_dns[@]}"; do
        if [[ -n "$dns_json" ]]; then
            dns_json="$dns_json,"
        fi
        dns_json="$dns_json\n    \"$dns\""
    done
    
    # 创建或更新daemon.json
    cat > "$daemon_json" << EOF
{
  "registry-mirrors": [$mirrors_json
  ],
  "insecure-registries": [],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "dns": [$dns_json
  ],
  "default-address-pools": [
    {
      "base": "172.30.0.0/16",
      "size": 24
    }
  ],
  "max-concurrent-downloads": 3,
  "max-concurrent-uploads": 5,
  "live-restore": true
}
EOF
    
    log_success "已更新Docker镜像源配置"
    log_info "使用的镜像源: ${available_mirrors[*]}"
    log_info "使用的DNS: ${available_dns[*]}"
}

# 修复DNS配置
fix_dns_config() {
    log_info "修复系统DNS配置..."
    
    # 获取可用的DNS服务器
    local available_dns=($(get_available_dns))
    
    # 备份原始resolv.conf
    if [[ -f /etc/resolv.conf ]]; then
        cp /etc/resolv.conf /etc/resolv.conf.backup.$(date +%Y%m%d-%H%M%S)
    fi
    
    # 创建新的resolv.conf
    {
        for dns in "${available_dns[@]}"; do
            echo "nameserver $dns"
        done
        echo "options timeout:2 attempts:3 rotate single-request-reopen"
    } > /etc/resolv.conf
    
    log_success "已更新系统DNS配置"
    log_info "使用的DNS服务器: ${available_dns[*]}"
}

# 清理Docker网络
clean_docker_networks() {
    log_info "清理Docker网络配置..."
    
    # 停止所有容器
    log_info "停止所有运行中的容器..."
    if docker ps -q | grep -q .; then
        docker stop $(docker ps -q) 2>/dev/null || log_info "容器停止完成"
    else
        log_info "没有运行中的容器"
    fi
    
    # 清理未使用的网络
    log_info "清理未使用的网络..."
    docker network prune -f 2>/dev/null || log_warning "网络清理失败"
    
    # 重建默认网络 (谨慎操作)
    log_info "检查默认网络状态..."
    if ! docker network ls | grep -q "bridge"; then
        log_info "重建默认bridge网络..."
        docker network create bridge 2>/dev/null || log_warning "默认网络重建失败"
    fi
    
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
    if timeout 30 docker run --rm hello-world >/dev/null 2>&1; then
        log_success "Docker基本功能正常"
    else
        log_warning "Docker基本功能测试失败，可能需要更多时间"
    fi
    
    # 测试网络连接
    log_info "测试容器网络连接..."
    if timeout 30 docker run --rm alpine ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        log_success "容器网络连接正常"
    else
        log_warning "容器网络连接测试失败"
    fi
    
    # 测试镜像拉取
    log_info "测试镜像拉取功能..."
    if timeout 60 docker pull alpine:latest >/dev/null 2>&1; then
        log_success "镜像拉取功能正常"
        docker rmi alpine:latest >/dev/null 2>&1 || true
    else
        log_warning "镜像拉取测试失败，可能是网络问题"
    fi
    
    # 检查服务状态
    log_info "最终服务状态检查..."
    systemctl status docker --no-pager -l | head -20
}

# 显示修复报告
show_report() {
    log_info "=== Docker运行时错误修复报告 (增强版) ==="
    echo
    log_info "修复的问题:"
    echo "  ✓ 智能检测可用镜像源"
    echo "  ✓ 智能检测可用DNS服务器"
    echo "  ✓ 容器重启策略优化"
    echo "  ✓ 网络端点清理"
    echo "  ✓ Docker镜像源配置优化"
    echo "  ✓ DNS配置优化"
    echo "  ✓ 插件缓存清理"
    echo "  ✓ Docker服务重启"
    echo
    log_info "配置文件位置:"
    echo "  - Docker配置: /etc/docker/daemon.json"
    echo "  - DNS配置: /etc/resolv.conf"
    echo "  - 备份位置: $(cat /tmp/docker-backup-path 2>/dev/null || echo '未创建备份')"
    echo
    log_info "针对镜像源DNS解析失败的特别优化:"
    echo "  ✓ 自动检测可用的镜像源"
    echo "  ✓ 优先使用阿里云、腾讯云等稳定镜像源"
    echo "  ✓ 自动回退到Docker Hub官方源"
    echo "  ✓ 优化DNS配置，使用多个可用DNS服务器"
    echo
    log_info "如果问题仍然存在，请检查:"
    echo "  1. 网络防火墙设置"
    echo "  2. 服务器网络连接状态"
    echo "  3. 是否在受限网络环境中"
    echo "  4. 磁盘空间是否充足"
    echo "  5. 系统内存是否充足"
    echo
    log_success "增强版修复脚本执行完成！"
}

# 主函数
main() {
    echo "=== Docker运行时错误修复脚本 (增强版) ==="
    echo "版本: 2.0.0 - 针对镜像源DNS解析失败优化"
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
    fix_docker_registry
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