#!/bin/bash
# fix-node-image.sh - Node镜像拉取问题自动修复脚本
# 适用于JAB租赁平台Docker部署

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

# 检查Docker是否安装
check_docker() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker未安装，请先安装Docker"
        exit 1
    fi
    log_info "Docker已安装: $(docker --version)"
}

# 检查Docker服务状态
check_docker_service() {
    if ! docker info &> /dev/null; then
        log_error "Docker服务未运行，请启动Docker服务"
        exit 1
    fi
    log_info "Docker服务正常运行"
}

# 备份现有Docker配置
backup_docker_config() {
    if [ -f "/etc/docker/daemon.json" ]; then
        log_info "备份现有Docker配置..."
        sudo cp /etc/docker/daemon.json /etc/docker/daemon.json.backup.$(date +%Y%m%d_%H%M%S)
        log_success "配置已备份"
    fi
}

# 配置Docker镜像加速器
configure_docker_mirrors() {
    log_info "配置Docker镜像加速器..."
    
    sudo mkdir -p /etc/docker
    
    # 创建镜像加速器配置
    sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "registry-mirrors": [
    "https://registry.cn-hangzhou.aliyuncs.com",
    "https://hub-mirror.c.163.com",
    "https://mirror.baidubce.com",
    "https://dockerproxy.com"
  ],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
    
    log_success "镜像加速器配置完成"
}

# 重启Docker服务
restart_docker() {
    log_info "重启Docker服务..."
    sudo systemctl daemon-reload
    sudo systemctl restart docker
    
    # 等待Docker服务启动
    sleep 5
    
    if docker info &> /dev/null; then
        log_success "Docker服务重启成功"
    else
        log_error "Docker服务重启失败"
        exit 1
    fi
}

# 测试镜像拉取
test_image_pull() {
    log_info "测试Node.js镜像拉取..."
    
    # 尝试拉取不同版本的Node.js镜像
    local images=(
        "node:18-alpine"
        "node:lts-alpine"
        "node:18"
        "node:18.19.0-alpine"
    )
    
    for image in "${images[@]}"; do
        log_info "尝试拉取: $image"
        if timeout 300 docker pull "$image" &> /dev/null; then
            log_success "成功拉取: $image"
            
            # 如果不是node:18-alpine，则创建标签
            if [ "$image" != "node:18-alpine" ]; then
                docker tag "$image" node:18-alpine
                log_success "已标记 $image 为 node:18-alpine"
            fi
            return 0
        else
            log_warning "拉取失败: $image"
        fi
    done
    
    return 1
}

# 尝试从国内镜像源拉取
try_chinese_mirrors() {
    log_info "尝试从国内镜像源拉取..."
    
    local mirrors=(
        "registry.cn-hangzhou.aliyuncs.com/library/node:18-alpine"
        "ccr.ccs.tencentyun.com/library/node:18-alpine"
        "hub-mirror.c.163.com/library/node:18-alpine"
    )
    
    for mirror in "${mirrors[@]}"; do
        log_info "尝试拉取: $mirror"
        if timeout 300 docker pull "$mirror" &> /dev/null; then
            log_success "成功拉取: $mirror"
            docker tag "$mirror" node:18-alpine
            log_success "已重新标记为 node:18-alpine"
            return 0
        else
            log_warning "拉取失败: $mirror"
        fi
    done
    
    return 1
}

# 清理Docker缓存
clean_docker_cache() {
    log_info "清理Docker缓存以释放空间..."
    docker system prune -f &> /dev/null
    log_success "Docker缓存清理完成"
}

# 网络诊断
network_diagnosis() {
    log_info "进行网络诊断..."
    
    # 测试DNS解析
    if nslookup registry-1.docker.io &> /dev/null; then
        log_success "DNS解析正常"
    else
        log_warning "DNS解析可能有问题"
    fi
    
    # 测试网络连接
    if ping -c 3 registry-1.docker.io &> /dev/null; then
        log_success "网络连接正常"
    else
        log_warning "网络连接可能有问题"
    fi
    
    # 测试HTTPS连接
    if curl -s -I https://registry-1.docker.io/v2/ &> /dev/null; then
        log_success "HTTPS连接正常"
    else
        log_warning "HTTPS连接可能有问题"
    fi
}

# 验证修复结果
verify_fix() {
    log_info "验证修复结果..."
    
    # 检查镜像是否存在
    if docker images | grep -q "node.*18-alpine"; then
        log_success "node:18-alpine镜像已可用"
        
        # 测试容器运行
        if docker run --rm node:18-alpine node --version &> /dev/null; then
            log_success "容器运行测试通过"
            return 0
        else
            log_warning "容器运行测试失败"
        fi
    else
        log_error "node:18-alpine镜像仍不可用"
    fi
    
    return 1
}

# 创建替代Dockerfile
create_alternative_dockerfile() {
    log_info "创建替代Dockerfile..."
    
    cat > Dockerfile.alternative <<EOF
# JAB租赁平台 - 替代镜像版本
# 使用更稳定的Node.js镜像

FROM node:lts-alpine AS deps
WORKDIR /app

# 安装系统依赖
RUN apk add --no-cache libc6-compat python3 make g++ && rm -rf /var/cache/apk/*

# 配置npm使用国内镜像源
RUN npm config set registry https://registry.npmmirror.com

# 复制package文件
COPY package*.json ./

# 安装依赖
RUN npm ci --only=production

# 构建阶段
FROM node:lts-alpine AS builder
WORKDIR /app

RUN apk add --no-cache libc6-compat python3 make g++ && rm -rf /var/cache/apk/*
RUN npm config set registry https://registry.npmmirror.com

COPY package*.json ./
RUN npm ci

COPY . .
RUN npm run build

# 运行时阶段
FROM node:lts-alpine AS runner
WORKDIR /app

RUN apk add --no-cache dumb-init curl && rm -rf /var/cache/apk/*
RUN addgroup --system --gid 1001 nodejs && adduser --system --uid 1001 nextjs

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
ENV PORT=3000
ENV HOSTNAME="0.0.0.0"

COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static
COPY --from=builder --chown=nextjs:nodejs /app/public ./public
COPY --from=deps --chown=nextjs:nodejs /app/node_modules ./node_modules
COPY --from=builder --chown=nextjs:nodejs /app/package.json ./package.json

USER nextjs
EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 CMD curl -f http://localhost:3000/api/health || exit 1

ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "server.js"]
EOF
    
    log_success "替代Dockerfile已创建: Dockerfile.alternative"
}

# 主函数
main() {
    echo "🐳 JAB租赁平台 - Node镜像拉取问题修复脚本"
    echo "================================================"
    
    # 检查环境
    check_docker
    check_docker_service
    
    # 网络诊断
    network_diagnosis
    
    # 清理缓存
    clean_docker_cache
    
    # 备份配置
    backup_docker_config
    
    # 配置镜像加速器
    configure_docker_mirrors
    
    # 重启Docker
    restart_docker
    
    # 测试镜像拉取
    if test_image_pull; then
        log_success "镜像拉取成功！"
    elif try_chinese_mirrors; then
        log_success "从国内镜像源拉取成功！"
    else
        log_error "所有镜像拉取尝试都失败了"
        log_info "创建替代方案..."
        create_alternative_dockerfile
        log_info "请尝试使用 Dockerfile.alternative 进行构建"
        exit 1
    fi
    
    # 验证修复结果
    if verify_fix; then
        echo ""
        log_success "🎉 修复完成！现在可以正常构建Docker容器了"
        echo ""
        echo "📋 下一步操作:"
        echo "   docker compose -f docker-compose.china.yml up -d --build"
        echo ""
    else
        log_error "修复验证失败，请检查日志或尝试手动解决"
        exit 1
    fi
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi