#!/bin/bash

# JAB租赁平台 - 快速构建脚本
# 解决Alpine包管理器速度慢的问题

set -e

echo "🚀 开始快速构建JAB租赁平台..."

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# 优化Docker构建环境
optimize_docker() {
    log_step "优化Docker构建环境..."
    
    # 启用BuildKit
    export DOCKER_BUILDKIT=1
    export COMPOSE_DOCKER_CLI_BUILD=1
    
    # 清理构建缓存（如果指定）
    if [ "$1" = "--clean" ]; then
        log_info "清理Docker构建缓存..."
        docker builder prune -f
    fi
    
    log_info "Docker构建环境优化完成"
}

# 快速构建
fast_build() {
    log_step "开始快速构建..."
    
    # 停止现有容器
    docker-compose down 2>/dev/null || true
    
    # 使用BuildKit和缓存优化构建
    DOCKER_BUILDKIT=1 docker-compose build --no-cache app
    
    if [ $? -eq 0 ]; then
        log_info "应用构建成功"
    else
        log_error "应用构建失败"
        exit 1
    fi
}

# 启动服务
start_services() {
    log_step "启动服务..."
    
    # 启动所有服务
    docker-compose up -d
    
    log_info "服务启动完成"
}

# 检查服务状态
check_services() {
    log_step "检查服务状态..."
    
    sleep 10
    
    # 显示服务状态
    docker-compose ps
    
    # 检查应用健康状态
    log_info "检查应用健康状态..."
    for i in {1..30}; do
        if curl -f http://localhost:3000/api/health &>/dev/null; then
            log_info "✅ 应用健康检查通过"
            break
        fi
        
        if [ $i -eq 30 ]; then
            log_warn "⚠️ 应用健康检查超时，请检查日志"
            docker-compose logs app | tail -20
        fi
        
        sleep 2
    done
}

# 主函数
main() {
    log_info "JAB租赁平台快速构建脚本 v1.0"
    
    optimize_docker "$1"
    fast_build
    start_services
    check_services
    
    echo ""
    echo "🎉 快速构建完成！"
    echo "🌐 应用地址: http://localhost:3000"
    echo "🔧 查看日志: docker-compose logs -f"
}

# 执行主函数
main "$@"