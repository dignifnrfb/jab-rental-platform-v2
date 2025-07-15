#!/bin/bash

# Docker镜像拉取修复脚本 v1.0.0
# 专门解决Docker镜像拉取失败问题
# 支持自动配置镜像源和网络诊断

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

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要root权限运行"
        log_info "请使用: sudo $0"
        exit 1
    fi
}

# 创建备份目录
create_backup_dir() {
    BACKUP_DIR="/tmp/docker-image-fix-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    log_success "备份目录已创建: $BACKUP_DIR"
}

# 诊断网络连接
diagnose_network() {
    log_info "=== 网络连接诊断 ==="
    
    log_info "1. 测试基本网络连接:"
    if ping -c 3 8.8.8.8 >/dev/null 2>&1; then
        log_success "网络连接正常"
    else
        log_error "网络连接异常，请检查网络设置"
        return 1
    fi
    
    log_info "2. 测试DNS解析:"
    if nslookup docker.io >/dev/null 2>&1; then
        log_success "DNS解析正常"
    else
        log_error "DNS解析异常"
        log_info "尝试使用公共DNS..."
        echo "nameserver 8.8.8.8" > /etc/resolv.conf
        echo "nameserver 114.114.114.114" >> /etc/resolv.conf
    fi
    
    log_info "3. 测试Docker Hub连接:"
    local docker_endpoints=(
        "registry-1.docker.io"
        "index.docker.io"
        "docker.io"
    )
    
    for endpoint in "${docker_endpoints[@]}"; do
        if curl -s --connect-timeout 10 "https://$endpoint" >/dev/null 2>&1; then
            log_success "可以连接到: $endpoint"
        else
            log_error "无法连接到: $endpoint"
        fi
    done
    echo
}

# 检查Docker配置
check_docker_config() {
    log_info "=== Docker配置检查 ==="
    
    log_info "1. Docker服务状态:"
    if systemctl is-active docker >/dev/null 2>&1; then
        log_success "Docker服务运行正常"
    else
        log_error "Docker服务未运行"
        log_info "启动Docker服务..."
        systemctl start docker
    fi
    
    log_info "2. 当前Docker配置:"
    if [[ -f /etc/docker/daemon.json ]]; then
        log_info "当前daemon.json配置:"
        cat /etc/docker/daemon.json
    else
        log_warning "daemon.json文件不存在"
    fi
    
    log_info "3. Docker版本信息:"
    docker --version || log_error "Docker命令执行失败"
    echo
}

# 配置Docker镜像源
configure_docker_registry() {
    log_info "=== 配置Docker镜像源 ==="
    
    # 备份现有配置
    if [[ -f /etc/docker/daemon.json ]]; then
        cp /etc/docker/daemon.json "$BACKUP_DIR/daemon.json.backup"
        log_info "已备份现有daemon.json配置"
    fi
    
    # 确保目录存在
    mkdir -p /etc/docker
    
    log_info "1. 测试可用的镜像源..."
    local mirrors=(
        "https://docker.mirrors.ustc.edu.cn"
        "https://hub-mirror.c.163.com"
        "https://mirror.baidubce.com"
        "https://ccr.ccs.tencentyun.com"
        "https://dockerproxy.com"
        "https://docker.nju.edu.cn"
    )
    
    local working_mirrors=()
    for mirror in "${mirrors[@]}"; do
        log_info "测试镜像源: $mirror"
        if curl -s --connect-timeout 5 "$mirror/v2/" >/dev/null 2>&1; then
            working_mirrors+=("$mirror")
            log_success "镜像源可用: $mirror"
        else
            log_warning "镜像源不可用: $mirror"
        fi
    done
    
    if [[ ${#working_mirrors[@]} -eq 0 ]]; then
        log_error "所有镜像源都不可用，使用默认配置"
        working_mirrors=("https://registry-1.docker.io")
    fi
    
    log_info "2. 生成优化的daemon.json配置..."
    
    cat > /etc/docker/daemon.json << EOF
{
    "registry-mirrors": [
EOF
    
    # 添加可用的镜像源
    for i in "${!working_mirrors[@]}"; do
        if [[ $i -eq $((${#working_mirrors[@]} - 1)) ]]; then
            echo "        \"${working_mirrors[$i]}\"" >> /etc/docker/daemon.json
        else
            echo "        \"${working_mirrors[$i]}\"," >> /etc/docker/daemon.json
        fi
    done
    
    cat >> /etc/docker/daemon.json << EOF
    ],
    "dns": ["8.8.8.8", "114.114.114.114"],
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    },
    "storage-driver": "overlay2",
    "exec-opts": ["native.cgroupdriver=systemd"],
    "insecure-registries": [],
    "live-restore": true,
    "userland-proxy": false,
    "experimental": false
}
EOF
    
    # 验证配置文件
    if python3 -m json.tool /etc/docker/daemon.json >/dev/null 2>&1; then
        log_success "daemon.json配置文件生成成功"
        log_info "新的配置内容:"
        cat /etc/docker/daemon.json
    else
        log_error "daemon.json配置文件语法错误"
        return 1
    fi
    echo
}

# 重启Docker服务
restart_docker() {
    log_info "=== 重启Docker服务 ==="
    
    log_info "1. 停止Docker服务..."
    systemctl stop docker
    
    log_info "2. 重新加载systemd配置..."
    systemctl daemon-reload
    
    log_info "3. 启动Docker服务..."
    if systemctl start docker; then
        log_success "Docker服务启动成功"
    else
        log_error "Docker服务启动失败"
        systemctl status docker --no-pager -l
        return 1
    fi
    
    log_info "4. 验证Docker服务状态..."
    if systemctl is-active docker >/dev/null 2>&1; then
        log_success "Docker服务运行正常"
    else
        log_error "Docker服务状态异常"
        return 1
    fi
    echo
}

# 测试镜像拉取
test_image_pull() {
    log_info "=== 测试镜像拉取 ==="
    
    local test_images=(
        "hello-world:latest"
        "node:18-alpine"
        "nginx:alpine"
    )
    
    for image in "${test_images[@]}"; do
        log_info "测试拉取镜像: $image"
        
        # 清理可能存在的镜像
        docker rmi "$image" 2>/dev/null || true
        
        # 尝试拉取镜像
        if timeout 300 docker pull "$image"; then
            log_success "成功拉取镜像: $image"
            
            # 测试运行容器
            if [[ "$image" == "hello-world:latest" ]]; then
                if docker run --rm "$image" >/dev/null 2>&1; then
                    log_success "容器运行测试成功: $image"
                else
                    log_warning "容器运行测试失败: $image"
                fi
            fi
        else
            log_error "拉取镜像失败: $image"
            
            # 显示详细错误信息
            log_info "详细错误信息:"
            docker pull "$image" 2>&1 | tail -10
        fi
        echo
    done
}

# 清理Docker缓存
clean_docker_cache() {
    log_info "=== 清理Docker缓存 ==="
    
    log_info "1. 清理未使用的镜像..."
    docker image prune -f || true
    
    log_info "2. 清理未使用的容器..."
    docker container prune -f || true
    
    log_info "3. 清理未使用的网络..."
    docker network prune -f || true
    
    log_info "4. 清理未使用的卷..."
    docker volume prune -f || true
    
    log_info "5. 显示磁盘使用情况..."
    docker system df
    
    log_success "Docker缓存清理完成"
    echo
}

# 显示修复报告
show_repair_report() {
    log_info "=== Docker镜像拉取修复报告 ==="
    echo
    
    log_info "修复步骤已完成，以下是详细信息:"
    echo
    
    log_info "1. 配置文件位置:"
    echo "   - Docker配置: /etc/docker/daemon.json"
    echo "   - DNS配置: /etc/resolv.conf"
    echo
    
    log_info "2. 备份文件位置:"
    echo "   - 备份目录: $BACKUP_DIR"
    if [[ -f "$BACKUP_DIR/daemon.json.backup" ]]; then
        echo "   - 原始daemon.json: $BACKUP_DIR/daemon.json.backup"
    fi
    echo
    
    log_info "3. 当前状态检查:"
    
    # Docker服务状态
    if systemctl is-active docker >/dev/null 2>&1; then
        log_success "Docker服务: 运行中"
    else
        log_error "Docker服务: 未运行"
    fi
    
    # 网络连接状态
    if ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
        log_success "网络连接: 正常"
    else
        log_error "网络连接: 异常"
    fi
    
    # DNS解析状态
    if nslookup docker.io >/dev/null 2>&1; then
        log_success "DNS解析: 正常"
    else
        log_error "DNS解析: 异常"
    fi
    
    echo
    log_info "4. 建议的下一步操作:"
    echo
    
    if systemctl is-active docker >/dev/null 2>&1; then
        log_success "Docker修复成功！现在可以尝试构建项目了。"
        echo "   建议运行: docker compose up -d --build"
        echo "   或者先测试: docker pull node:18-alpine"
    else
        log_error "Docker修复未完全成功，建议:"
        echo "   1. 检查网络连接: ping 8.8.8.8"
        echo "   2. 检查防火墙设置: ufw status"
        echo "   3. 重启系统: sudo reboot"
        echo "   4. 重新安装Docker: apt remove docker.io && apt install docker.io"
    fi
    
    echo
    log_info "5. 常用诊断命令:"
    echo "   - 查看Docker日志: journalctl -u docker -f"
    echo "   - 测试镜像拉取: docker pull hello-world"
    echo "   - 检查镜像源: docker info | grep -A 10 'Registry Mirrors'"
    echo "   - 清理Docker缓存: docker system prune -a"
    echo
}

# 主函数
main() {
    log_info "=== Docker镜像拉取修复脚本 ==="
    log_info "版本: 1.0.0 - 专门解决Docker镜像拉取失败问题"
    log_info "日期: $(date)"
    echo
    
    # 检查root权限
    check_root
    
    # 创建备份目录
    create_backup_dir
    
    # 1. 诊断阶段
    diagnose_network
    check_docker_config
    
    # 2. 修复阶段
    configure_docker_registry
    clean_docker_cache
    restart_docker
    
    # 3. 验证阶段
    test_image_pull
    
    # 4. 报告阶段
    show_repair_report
}

# 执行主函数
main "$@"