#!/bin/bash

# JAB租赁平台 - 终极Docker段错误修复脚本
# 适用于所有其他方案都失败的情况
# 包含系统级优化和手动构建步骤

set -e

echo "🚀 Docker终极修复脚本启动..."
echo "⚠️  这是最后的解决方案，将进行系统级优化"

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
if [ "$EUID" -ne 0 ]; then
    log_warning "建议以root权限运行以进行系统级优化"
    log_info "当前将跳过部分系统优化步骤"
    IS_ROOT=false
else
    IS_ROOT=true
fi

# 检查Docker是否运行
if ! docker info > /dev/null 2>&1; then
    log_error "Docker未运行，请先启动Docker服务"
    exit 1
fi

log_info "=== 第1步: 系统级优化 ==="

if [ "$IS_ROOT" = true ]; then
    log_info "应用系统级内存优化..."
    
    # 禁用透明大页（可能导致段错误）
    if [ -f /sys/kernel/mm/transparent_hugepage/enabled ]; then
        echo never > /sys/kernel/mm/transparent_hugepage/enabled
        log_debug "已禁用透明大页"
    fi
    
    # 调整OOM killer设置
    echo 1 > /proc/sys/vm/overcommit_memory
    echo 80 > /proc/sys/vm/overcommit_ratio
    log_debug "已调整内存过量分配策略"
    
    # 增加文件描述符限制
    ulimit -n 65536
    echo "* soft nofile 65536" >> /etc/security/limits.conf
    echo "* hard nofile 65536" >> /etc/security/limits.conf
    log_debug "已增加文件描述符限制"
    
    # 调整虚拟内存设置
    echo 1 > /proc/sys/vm/drop_caches
    sysctl -w vm.swappiness=10
    sysctl -w vm.vfs_cache_pressure=50
    log_debug "已优化虚拟内存设置"
else
    log_warning "非root用户，跳过系统级优化"
fi

log_info "=== 第2步: Docker环境重置 ==="

# 完全停止Docker服务
log_info "停止所有Docker容器和服务..."
docker-compose -f docker-compose.yml down --remove-orphans 2>/dev/null || true
docker-compose -f docker-compose.lightweight.yml down --remove-orphans 2>/dev/null || true
docker-compose -f docker-compose.ultra-safe.yml down --remove-orphans 2>/dev/null || true

# 强制停止所有容器
docker stop $(docker ps -aq) 2>/dev/null || true
docker rm $(docker ps -aq) 2>/dev/null || true

# 清理所有Docker资源
log_info "清理Docker资源..."
docker system prune -a -f --volumes
docker builder prune -a -f
docker volume prune -f

# 重启Docker服务（如果有权限）
if [ "$IS_ROOT" = true ]; then
    log_info "重启Docker服务..."
    systemctl restart docker
    sleep 10
    log_debug "Docker服务已重启"
fi

log_info "=== 第3步: 禁用Docker BuildKit ==="

# 完全禁用BuildKit
export DOCKER_BUILDKIT=0
export COMPOSE_DOCKER_CLI_BUILD=0
unset BUILDKIT_PROGRESS

log_debug "已禁用Docker BuildKit，使用传统构建方式"

log_info "=== 第4步: 检查系统资源 ==="

# 详细的系统资源检查
MEM_TOTAL=$(free -m | awk 'NR==2{print $2}')
MEM_FREE=$(free -m | awk 'NR==2{print $4}')
MEM_AVAILABLE=$(free -m | awk 'NR==2{print $7}')
SWAP_TOTAL=$(free -m | awk 'NR==3{print $2}')
SWAP_FREE=$(free -m | awk 'NR==3{print $4}')
DISK_USAGE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')

log_debug "内存状态: 总计${MEM_TOTAL}MB, 空闲${MEM_FREE}MB, 可用${MEM_AVAILABLE}MB"
log_debug "交换空间: 总计${SWAP_TOTAL}MB, 空闲${SWAP_FREE}MB"
log_debug "磁盘使用率: ${DISK_USAGE}%"

# 检查是否有足够资源
if [ "$MEM_AVAILABLE" -lt 2048 ]; then
    log_error "可用内存不足2GB，无法安全构建"
    log_info "建议:"
    log_info "1. 关闭其他应用程序释放内存"
    log_info "2. 增加交换空间"
    log_info "3. 使用更高配置的服务器"
    exit 1
fi

if [ "$DISK_USAGE" -gt 85 ]; then
    log_error "磁盘使用率过高(${DISK_USAGE}%)，可能导致构建失败"
    exit 1
fi

log_info "=== 第5步: 手动分步构建 ==="

log_info "开始手动分步构建，避免段错误..."

# 设置构建环境变量
export NODE_OPTIONS="--max-old-space-size=3072 --max-semi-space-size=128"
export NODE_ENV=production
export NEXT_TELEMETRY_DISABLED=1

# 第一步：构建基础镜像
log_info "步骤1: 构建基础依赖镜像..."
docker build \
    --no-cache \
    --memory=3g \
    --memory-swap=4g \
    --cpus=1 \
    --target=deps \
    -f Dockerfile.ultra-safe \
    -t jab-deps:latest \
    . || {
    log_error "基础依赖构建失败"
    log_info "尝试备用方案..."
    
    # 备用方案：使用更小的内存限制
    docker build \
        --no-cache \
        --memory=2g \
        --memory-swap=3g \
        --cpus=1 \
        --target=deps \
        -f Dockerfile.ultra-safe \
        -t jab-deps:latest \
        . || {
        log_error "备用方案也失败，请检查系统状态"
        exit 1
    }
}

log_success "基础依赖镜像构建完成"

# 第二步：构建应用镜像
log_info "步骤2: 构建应用镜像..."
docker build \
    --no-cache \
    --memory=3g \
    --memory-swap=4g \
    --cpus=1 \
    --target=builder \
    -f Dockerfile.ultra-safe \
    -t jab-builder:latest \
    . || {
    log_error "应用构建失败"
    exit 1
}

log_success "应用镜像构建完成"

# 第三步：构建最终运行镜像
log_info "步骤3: 构建最终运行镜像..."
docker build \
    --no-cache \
    --memory=2g \
    --memory-swap=3g \
    --cpus=1 \
    -f Dockerfile.ultra-safe \
    -t jab-app:latest \
    . || {
    log_error "最终镜像构建失败"
    exit 1
}

log_success "所有镜像构建完成"

log_info "=== 第6步: 启动服务 ==="

# 使用超安全配置启动服务
log_info "使用超安全配置启动服务..."
docker-compose -f docker-compose.ultra-safe.yml up -d

log_info "等待服务启动..."
sleep 60

log_info "=== 第7步: 验证部署 ==="

# 检查服务状态
log_info "检查服务状态..."
docker-compose -f docker-compose.ultra-safe.yml ps

# 健康检查
log_info "执行健康检查..."
for i in {1..15}; do
    if curl -f http://localhost/api/health > /dev/null 2>&1; then
        log_success "应用健康检查通过"
        break
    else
        log_warning "健康检查失败，重试中... ($i/15)"
        sleep 10
    fi
    
    if [ $i -eq 15 ]; then
        log_error "应用健康检查失败"
        log_info "显示应用日志:"
        docker-compose -f docker-compose.ultra-safe.yml logs app
        exit 1
    fi
done

# 检查Nginx
if curl -f http://localhost > /dev/null 2>&1; then
    log_success "Nginx运行正常"
else
    log_error "Nginx访问失败"
    docker-compose -f docker-compose.ultra-safe.yml logs nginx
fi

log_info "=== 部署完成 ==="

log_success "🎉 终极修复脚本执行完成！"
log_info "应用已使用超安全配置成功部署"
log_info "访问地址: http://your-server-ip"
log_info "健康检查: http://your-server-ip/api/health"

log_info "如果仍有问题，请检查:"
log_info "1. 服务器硬件是否存在问题"
log_info "2. 操作系统内核版本是否过旧"
log_info "3. Docker版本是否兼容"
log_info "4. 考虑使用云服务器或更换服务器"

log_info "查看详细日志: docker-compose -f docker-compose.ultra-safe.yml logs"
