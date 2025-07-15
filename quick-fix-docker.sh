#!/bin/bash

# Docker镜像拉取快速修复脚本
# 专门解决 node:18-alpine 等镜像拉取失败问题

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 检查是否为root用户
if [[ $EUID -ne 0 ]]; then
    log_error "此脚本需要root权限运行"
    log_info "请使用: sudo $0"
    exit 1
fi

log_info "=== Docker镜像拉取快速修复 ==="
echo

# 1. 备份现有配置
log_info "1. 备份现有Docker配置..."
BACKUP_DIR="/tmp/docker-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
if [[ -f /etc/docker/daemon.json ]]; then
    cp /etc/docker/daemon.json "$BACKUP_DIR/"
    log_success "已备份daemon.json到 $BACKUP_DIR"
fi

# 2. 创建Docker配置目录
log_info "2. 创建Docker配置目录..."
mkdir -p /etc/docker

# 3. 配置国内镜像源
log_info "3. 配置Docker镜像源..."
cat > /etc/docker/daemon.json << 'EOF'
{
    "registry-mirrors": [
        "https://docker.mirrors.ustc.edu.cn",
        "https://hub-mirror.c.163.com",
        "https://mirror.baidubce.com",
        "https://ccr.ccs.tencentyun.com",
        "https://dockerproxy.com"
    ],
    "dns": ["8.8.8.8", "114.114.114.114", "223.5.5.5"],
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    },
    "storage-driver": "overlay2",
    "exec-opts": ["native.cgroupdriver=systemd"],
    "live-restore": true,
    "userland-proxy": false
}
EOF

log_success "Docker镜像源配置完成"

# 4. 配置系统DNS
log_info "4. 优化系统DNS配置..."
cp /etc/resolv.conf "$BACKUP_DIR/resolv.conf.backup" 2>/dev/null || true
cat > /etc/resolv.conf << 'EOF'
nameserver 8.8.8.8
nameserver 114.114.114.114
nameserver 223.5.5.5
EOF

log_success "DNS配置完成"

# 5. 重启Docker服务
log_info "5. 重启Docker服务..."
systemctl daemon-reload
systemctl restart docker

# 等待服务启动
sleep 3

if systemctl is-active docker >/dev/null 2>&1; then
    log_success "Docker服务重启成功"
else
    log_error "Docker服务重启失败"
    systemctl status docker --no-pager
    exit 1
fi

# 6. 清理Docker缓存
log_info "6. 清理Docker缓存..."
docker system prune -f >/dev/null 2>&1 || true
log_success "缓存清理完成"

# 7. 测试镜像拉取
log_info "7. 测试镜像拉取..."
echo

# 测试hello-world
log_info "测试拉取 hello-world..."
if timeout 60 docker pull hello-world >/dev/null 2>&1; then
    log_success "✓ hello-world 拉取成功"
else
    log_error "✗ hello-world 拉取失败"
fi

# 测试node:18-alpine
log_info "测试拉取 node:18-alpine..."
if timeout 120 docker pull node:18-alpine >/dev/null 2>&1; then
    log_success "✓ node:18-alpine 拉取成功"
else
    log_error "✗ node:18-alpine 拉取失败"
    log_warning "尝试使用阿里云镜像..."
    if timeout 120 docker pull registry.cn-hangzhou.aliyuncs.com/library/node:18-alpine >/dev/null 2>&1; then
        log_success "✓ 阿里云 node:18-alpine 拉取成功"
        log_info "建议修改Dockerfile使用: registry.cn-hangzhou.aliyuncs.com/library/node:18-alpine"
    fi
fi

# 测试nginx:alpine
log_info "测试拉取 nginx:alpine..."
if timeout 60 docker pull nginx:alpine >/dev/null 2>&1; then
    log_success "✓ nginx:alpine 拉取成功"
else
    log_error "✗ nginx:alpine 拉取失败"
fi

echo
log_info "=== 修复完成 ==="
echo

log_info "配置信息:"
echo "  - 备份目录: $BACKUP_DIR"
echo "  - Docker配置: /etc/docker/daemon.json"
echo "  - DNS配置: /etc/resolv.conf"
echo

log_info "下一步操作:"
echo "  1. 验证Docker状态: docker info"
echo "  2. 重新构建项目: docker compose up -d --build"
echo "  3. 如果仍有问题，请检查网络连接和防火墙设置"
echo

log_success "Docker镜像拉取修复脚本执行完成！"
echo

# 显示当前镜像源配置
log_info "当前镜像源配置:"
docker info 2>/dev/null | grep -A 10 "Registry Mirrors" || echo "无法获取镜像源信息"
echo