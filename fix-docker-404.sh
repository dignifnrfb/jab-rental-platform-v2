#!/bin/bash

# JAB租赁平台 - Docker 404错误修复脚本
# 解决Next.js standalone模式在Docker中的路由问题

set -e

echo "🔧 开始修复Docker 404错误..."

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

# 检查Docker是否运行
if ! docker info > /dev/null 2>&1; then
    log_error "Docker未运行，请先启动Docker服务"
    exit 1
fi

# 检查docker-compose文件是否存在
if [ ! -f "docker-compose.yml" ]; then
    log_error "docker-compose.yml文件不存在"
    exit 1
fi

log_info "停止现有容器..."
docker-compose down --remove-orphans || true

log_info "清理Docker缓存和未使用的镜像..."
docker system prune -f
docker image prune -f

log_info "重新构建应用容器（无缓存）..."
docker-compose build --no-cache app

log_info "启动所有服务..."
docker-compose up -d

log_info "等待服务启动..."
sleep 30

log_info "检查服务状态..."
docker-compose ps

log_info "检查应用健康状态..."
for i in {1..10}; do
    if curl -f http://localhost/api/health > /dev/null 2>&1; then
        log_success "应用健康检查通过"
        break
    else
        log_warning "健康检查失败，重试中... ($i/10)"
        sleep 5
    fi
    
    if [ $i -eq 10 ]; then
        log_error "应用健康检查失败"
        log_info "显示应用日志:"
        docker-compose logs app
        exit 1
    fi
done

log_info "检查Nginx状态..."
if curl -f http://localhost > /dev/null 2>&1; then
    log_success "Nginx运行正常"
else
    log_error "Nginx访问失败"
    log_info "显示Nginx日志:"
    docker-compose logs nginx
fi

log_info "显示应用日志（最后50行）:"
docker-compose logs --tail=50 app

log_success "修复脚本执行完成！"
log_info "请访问 http://your-server-ip 测试应用"
log_info "如果仍有问题，请检查:"
log_info "1. 服务器防火墙设置"
log_info "2. 域名DNS解析"
log_info "3. SSL证书配置"
log_info "4. 查看完整日志: docker-compose logs"
