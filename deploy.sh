#!/bin/bash

# JAB租赁平台 - Ubuntu 24.04 部署脚本
# 使用方法: chmod +x deploy.sh && ./deploy.sh

set -e  # 遇到错误立即退出

echo "🚀 开始部署JAB租赁平台..."

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# 检查Docker是否安装
check_docker() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker未安装，请先安装Docker"
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        log_error "Docker Compose未安装，请先安装Docker Compose"
        exit 1
    fi
    
    log_info "Docker环境检查通过"
}

# 清理旧的构建
cleanup() {
    log_info "清理旧的Docker镜像和容器..."
    
    # 停止并删除容器
    docker-compose down --remove-orphans 2>/dev/null || true
    
    # 删除旧镜像（可选）
    # docker image prune -f
    
    log_info "清理完成"
}

# 构建和启动服务
build_and_start() {
    log_info "开始构建Docker镜像..."
    
    # 构建镜像
    docker-compose build --no-cache
    
    if [ $? -eq 0 ]; then
        log_info "Docker镜像构建成功"
    else
        log_error "Docker镜像构建失败"
        exit 1
    fi
    
    log_info "启动服务..."
    
    # 启动服务
    docker-compose up -d
    
    if [ $? -eq 0 ]; then
        log_info "服务启动成功"
    else
        log_error "服务启动失败"
        exit 1
    fi
}

# 检查服务状态
check_services() {
    log_info "检查服务状态..."
    
    sleep 10  # 等待服务启动
    
    # 检查容器状态
    docker-compose ps
    
    # 检查应用健康状态
    log_info "等待应用启动..."
    for i in {1..30}; do
        if curl -f http://localhost:3000/api/health &>/dev/null; then
            log_info "应用健康检查通过"
            break
        fi
        
        if [ $i -eq 30 ]; then
            log_warn "应用健康检查超时，请检查日志"
            docker-compose logs app
        fi
        
        sleep 2
    done
}

# 显示部署信息
show_info() {
    echo ""
    echo "🎉 部署完成！"
    echo ""
    echo "📋 服务信息:"
    echo "  - 应用地址: http://localhost:3000"
    echo "  - 健康检查: http://localhost:3000/api/health"
    echo "  - 数据库: PostgreSQL (端口5432)"
    echo "  - 缓存: Redis (端口6379)"
    echo ""
    echo "🔧 常用命令:"
    echo "  - 查看日志: docker-compose logs -f"
    echo "  - 停止服务: docker-compose down"
    echo "  - 重启服务: docker-compose restart"
    echo "  - 查看状态: docker-compose ps"
    echo ""
}

# 主函数
main() {
    log_info "JAB租赁平台部署脚本 v1.0"
    
    # 检查环境
    check_docker
    
    # 清理旧环境
    cleanup
    
    # 构建和启动
    build_and_start
    
    # 检查服务
    check_services
    
    # 显示信息
    show_info
}

# 错误处理
trap 'log_error "部署过程中发生错误，请检查日志"; exit 1' ERR

# 执行主函数
main "$@"