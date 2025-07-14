#!/bin/bash

# JAB租赁平台 - Docker段错误故障排除脚本
# 解决Docker构建过程中的Segmentation fault问题

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

echo "🔧 Docker段错误故障排除脚本启动..."

# 1. 系统资源检查
log_info "检查系统资源状态..."

# 检查内存使用情况
MEM_TOTAL=$(free -m | awk 'NR==2{printf "%.0f", $2}')
MEM_USED=$(free -m | awk 'NR==2{printf "%.0f", $3}')
MEM_FREE=$(free -m | awk 'NR==2{printf "%.0f", $4}')
MEM_USAGE=$(echo "scale=1; $MEM_USED*100/$MEM_TOTAL" | bc)

log_debug "内存状态: 总计${MEM_TOTAL}MB, 已用${MEM_USED}MB, 空闲${MEM_FREE}MB, 使用率${MEM_USAGE}%"

if (( $(echo "$MEM_USAGE > 85" | bc -l) )); then
    log_warning "内存使用率过高(${MEM_USAGE}%)，这可能是段错误的原因"
    log_info "建议释放内存或增加swap空间"
fi

if [ "$MEM_FREE" -lt 1024 ]; then
    log_error "可用内存不足1GB，Docker构建可能失败"
    log_info "正在尝试释放系统缓存..."
    sudo sync && sudo sysctl -w vm.drop_caches=3 || log_warning "无法清理系统缓存，需要root权限"
fi

# 检查磁盘空间
DISK_USAGE=$(df -h . | awk 'NR==2 {print $5}' | sed 's/%//')
log_debug "磁盘使用率: ${DISK_USAGE}%"

if [ "$DISK_USAGE" -gt 85 ]; then
    log_warning "磁盘空间不足，使用率${DISK_USAGE}%"
    log_info "正在清理Docker缓存..."
    docker system prune -f --volumes || log_warning "Docker清理失败"
fi

# 2. Docker服务状态检查
log_info "检查Docker服务状态..."

if ! systemctl is-active --quiet docker; then
    log_warning "Docker服务未运行，正在启动..."
    sudo systemctl start docker || {
        log_error "无法启动Docker服务"
        exit 1
    }
fi

# 检查Docker守护进程健康状态
if ! docker info > /dev/null 2>&1; then
    log_warning "Docker守护进程响应异常，正在重启..."
    sudo systemctl restart docker
    sleep 10
    
    if ! docker info > /dev/null 2>&1; then
        log_error "Docker守护进程重启后仍无法正常工作"
        exit 1
    fi
    log_success "Docker守护进程重启成功"
fi

# 3. 清理Docker资源
log_info "清理Docker资源以释放内存..."

# 停止所有容器
log_debug "停止所有运行中的容器..."
docker stop $(docker ps -q) 2>/dev/null || log_debug "没有运行中的容器"

# 清理无用资源
log_debug "清理无用的Docker资源..."
docker system prune -af --volumes || log_warning "Docker资源清理失败"

# 清理构建缓存
log_debug "清理Docker构建缓存..."
docker builder prune -af || log_warning "构建缓存清理失败"

# 4. 系统优化
log_info "应用系统优化设置..."

# 增加文件描述符限制
echo "* soft nofile 65536" | sudo tee -a /etc/security/limits.conf > /dev/null || log_warning "无法修改文件描述符限制"
echo "* hard nofile 65536" | sudo tee -a /etc/security/limits.conf > /dev/null || log_warning "无法修改文件描述符限制"

# 调整内存过量分配策略
echo 1 | sudo tee /proc/sys/vm/overcommit_memory > /dev/null || log_warning "无法调整内存分配策略"

# 5. 检查swap空间
SWAP_TOTAL=$(free -m | awk 'NR==3{printf "%.0f", $2}')
if [ "$SWAP_TOTAL" -eq 0 ]; then
    log_warning "系统没有配置swap空间"
    log_info "建议创建swap文件以避免内存不足"
    
    read -p "是否创建2GB swap文件? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "创建swap文件..."
        sudo fallocate -l 2G /swapfile || {
            log_error "创建swap文件失败"
        }
        sudo chmod 600 /swapfile
        sudo mkswap /swapfile
        sudo swapon /swapfile
        echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
        log_success "swap文件创建成功"
    fi
else
    log_debug "swap空间: ${SWAP_TOTAL}MB"
fi

# 6. 优化的Docker构建
log_info "使用优化策略重新构建应用..."

# 设置Docker构建参数
export DOCKER_BUILDKIT=1
export COMPOSE_DOCKER_CLI_BUILD=1

# 限制并行构建数量以减少内存使用
export DOCKER_BUILD_ARGS="--memory=2g --memory-swap=4g --cpus=2"

log_info "开始优化构建 (限制内存2GB, CPU 2核)..."

# 分步构建以减少内存压力
log_debug "第1步: 构建依赖层..."
docker-compose build --no-cache --parallel --memory=1g deps 2>/dev/null || {
    log_warning "依赖层构建失败，尝试单线程构建..."
    docker-compose build --no-cache --memory=1g deps || {
        log_error "依赖层构建失败"
        exit 1
    }
}

log_debug "第2步: 构建应用层..."
docker-compose build --no-cache --memory=2g app || {
    log_error "应用构建失败"
    
    # 备用方案：使用更小的内存限制
    log_info "尝试备用构建方案 (限制内存1GB)..."
    docker-compose build --no-cache --memory=1g --cpus=1 app || {
        log_error "备用构建方案也失败了"
        
        # 最后的备用方案：不使用缓存，逐步构建
        log_info "尝试最小资源构建..."
        docker build --no-cache --memory=512m --cpus=1 -t jab-app . || {
            log_error "所有构建方案都失败了，请检查系统资源"
            exit 1
        }
    }
}

log_success "Docker构建完成！"

# 7. 启动服务
log_info "启动服务..."
docker-compose up -d

# 8. 验证服务状态
log_info "等待服务启动..."
sleep 30

log_info "检查服务状态..."
docker-compose ps

# 健康检查
for i in {1..5}; do
    if curl -f http://localhost/api/health > /dev/null 2>&1; then
        log_success "应用健康检查通过"
        break
    else
        log_warning "健康检查失败，重试中... ($i/5)"
        sleep 10
    fi
    
    if [ $i -eq 5 ]; then
        log_error "应用健康检查失败"
        log_info "显示应用日志:"
        docker-compose logs --tail=50 app
    fi
done

log_success "故障排除完成！"
log_info "系统资源状态:"
free -h
df -h .
log_info "如果问题仍然存在，建议:"
log_info "1. 增加服务器内存"
log_info "2. 使用更小的Docker镜像"
log_info "3. 分批构建依赖"
log_info "4. 考虑使用远程构建服务"
