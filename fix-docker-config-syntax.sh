#!/bin/bash

# Docker配置语法修复脚本
# 专门解决daemon.json语法错误和DNS配置问题
# 作者: JAB租赁平台团队
# 版本: 1.0.0
# 日期: 2025-01-14
# 要求: bash 4.0+, jq工具

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

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要root权限运行"
        log_info "请使用: sudo $0"
        exit 1
    fi
}

# 安装必要工具
install_dependencies() {
    log_info "=== 检查并安装必要工具 ==="
    
    # 检查jq工具
    if ! command -v jq >/dev/null 2>&1; then
        log_info "安装jq工具..."
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update && apt-get install -y jq
        elif command -v yum >/dev/null 2>&1; then
            yum install -y jq
        elif command -v dnf >/dev/null 2>&1; then
            dnf install -y jq
        else
            log_error "无法自动安装jq，请手动安装"
            exit 1
        fi
    fi
    
    # 检查python3
    if ! command -v python3 >/dev/null 2>&1; then
        log_warning "python3未安装，将使用jq进行JSON验证"
    fi
    
    log_success "依赖工具检查完成"
    echo
}

# 创建备份
create_backup() {
    local backup_dir="/tmp/docker-config-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"
    
    # 备份关键配置文件
    [[ -f /etc/docker/daemon.json ]] && cp /etc/docker/daemon.json "$backup_dir/"
    [[ -f /etc/resolv.conf ]] && cp /etc/resolv.conf "$backup_dir/"
    [[ -f /etc/systemd/resolved.conf ]] && cp /etc/systemd/resolved.conf "$backup_dir/"
    
    echo "$backup_dir" > /tmp/docker-config-backup-path
    log_success "配置文件已备份到: $backup_dir"
    echo
}

# 验证JSON语法
validate_json() {
    local file="$1"
    local temp_file="/tmp/json_validation.tmp"
    
    if [[ ! -f "$file" ]]; then
        log_error "文件不存在: $file"
        return 1
    fi
    
    # 使用jq验证JSON语法
    if jq empty "$file" 2>/dev/null; then
        log_success "JSON语法正确: $file"
        return 0
    else
        log_error "JSON语法错误: $file"
        
        # 显示详细错误信息
        log_info "详细错误信息:"
        jq empty "$file" 2>&1 || true
        
        # 尝试使用python3进行更详细的错误分析
        if command -v python3 >/dev/null 2>&1; then
            log_info "Python JSON验证结果:"
            python3 -c "
import json
import sys
try:
    with open('$file', 'r') as f:
        json.load(f)
    print('JSON语法正确')
except json.JSONDecodeError as e:
    print(f'JSON语法错误: {e}')
    print(f'错误位置: 行{e.lineno}, 列{e.colno}')
except Exception as e:
    print(f'文件读取错误: {e}')
" 2>&1 || true
        fi
        
        return 1
    fi
}

# 修复daemon.json语法错误
fix_daemon_json() {
    log_info "=== 修复Docker daemon.json配置 ==="
    
    local daemon_json="/etc/docker/daemon.json"
    local temp_file="/tmp/daemon.json.tmp"
    
    if [[ ! -f "$daemon_json" ]]; then
        log_warning "daemon.json不存在，创建默认配置"
        mkdir -p /etc/docker
        create_default_daemon_json
        return 0
    fi
    
    log_info "当前daemon.json内容:"
    cat "$daemon_json"
    echo
    
    # 验证当前JSON语法
    if validate_json "$daemon_json"; then
        log_success "daemon.json语法正确，无需修复"
        return 0
    fi
    
    log_info "开始修复daemon.json语法错误..."
    
    # 尝试自动修复常见语法错误
    fix_common_json_errors "$daemon_json" "$temp_file"
    
    # 验证修复后的文件
    if validate_json "$temp_file"; then
        log_success "JSON语法修复成功"
        mv "$temp_file" "$daemon_json"
        log_info "修复后的daemon.json内容:"
        cat "$daemon_json"
    else
        log_error "自动修复失败，创建默认配置"
        mv "$daemon_json" "${daemon_json}.broken.$(date +%Y%m%d-%H%M%S)"
        create_default_daemon_json
    fi
    
    echo
}

# 修复常见JSON语法错误
fix_common_json_errors() {
    local input_file="$1"
    local output_file="$2"
    
    # 读取原文件内容
    local content=$(cat "$input_file")
    
    # 修复常见错误
    # 1. 移除多余的逗号
    content=$(echo "$content" | sed 's/,\s*}/}/g')
    content=$(echo "$content" | sed 's/,\s*]/]/g')
    
    # 2. 修复缺失的引号
    content=$(echo "$content" | sed 's/\([a-zA-Z0-9_-]\+\)\s*:/"\1":/g')
    
    # 3. 移除注释（JSON不支持注释）
    content=$(echo "$content" | sed 's|//.*$||g')
    content=$(echo "$content" | sed 's|/\*.*\*/||g')
    
    # 4. 修复单引号为双引号
    content=$(echo "$content" | sed "s/'/\"/g")
    
    # 5. 移除多余的空行和空格
    content=$(echo "$content" | sed '/^\s*$/d')
    
    # 写入临时文件
    echo "$content" > "$output_file"
    
    log_info "已应用常见JSON语法修复规则"
}

# 创建默认daemon.json配置
create_default_daemon_json() {
    local daemon_json="/etc/docker/daemon.json"
    
    log_info "创建默认daemon.json配置..."
    
    # 检测可用的镜像源
    local available_mirrors=()
    local test_mirrors=(
        "https://registry.cn-hangzhou.aliyuncs.com"
        "https://registry.cn-shanghai.aliyuncs.com"
        "https://registry.cn-beijing.aliyuncs.com"
        "https://mirror.ccs.tencentyun.com"
        "https://registry.cn-shenzhen.aliyuncs.com"
    )
    
    log_info "测试镜像源可用性..."
    for mirror in "${test_mirrors[@]}"; do
        if timeout 5 curl -s "$mirror/v2/" >/dev/null 2>&1; then
            available_mirrors+=("$mirror")
            log_success "可用镜像源: $mirror"
        else
            log_warning "不可用镜像源: $mirror"
        fi
    done
    
    # 如果没有可用镜像源，使用默认配置
    if [[ ${#available_mirrors[@]} -eq 0 ]]; then
        log_warning "未找到可用镜像源，使用基础配置"
        cat > "$daemon_json" << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "live-restore": true,
  "dns": ["8.8.8.8", "114.114.114.114"]
}
EOF
    else
        # 创建包含可用镜像源的配置
        log_info "创建包含${#available_mirrors[@]}个可用镜像源的配置"
        
        # 构建镜像源数组
        local mirrors_json=""
        for i in "${!available_mirrors[@]}"; do
            if [[ $i -eq 0 ]]; then
                mirrors_json="\"${available_mirrors[$i]}\""
            else
                mirrors_json="$mirrors_json,\"${available_mirrors[$i]}\""
            fi
        done
        
        cat > "$daemon_json" << EOF
{
  "registry-mirrors": [$mirrors_json],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "live-restore": true,
  "dns": ["8.8.8.8", "114.114.114.114", "223.5.5.5"]
}
EOF
    fi
    
    # 验证生成的配置
    if validate_json "$daemon_json"; then
        log_success "默认daemon.json配置创建成功"
        log_info "配置内容:"
        cat "$daemon_json"
    else
        log_error "默认配置创建失败"
        exit 1
    fi
}

# 修复DNS配置
fix_dns_config() {
    log_info "=== 修复系统DNS配置 ==="
    
    # 测试当前DNS服务器
    local current_dns=()
    if [[ -f /etc/resolv.conf ]]; then
        current_dns=($(grep '^nameserver' /etc/resolv.conf | awk '{print $2}'))
    fi
    
    log_info "当前DNS服务器: ${current_dns[*]}"
    
    # 测试DNS服务器可用性
    local working_dns=()
    local test_dns=(
        "8.8.8.8"          # Google DNS
        "114.114.114.114"   # 114 DNS
        "223.5.5.5"         # 阿里DNS
        "1.1.1.1"           # Cloudflare DNS
        "208.67.222.222"    # OpenDNS
    )
    
    log_info "测试DNS服务器可用性..."
    for dns in "${test_dns[@]}"; do
        if timeout 3 nslookup google.com "$dns" >/dev/null 2>&1; then
            working_dns+=("$dns")
            log_success "可用DNS: $dns"
        else
            log_warning "不可用DNS: $dns"
        fi
    done
    
    # 如果没有可用DNS，使用默认配置
    if [[ ${#working_dns[@]} -eq 0 ]]; then
        log_error "未找到可用DNS服务器，使用默认配置"
        working_dns=("8.8.8.8" "114.114.114.114" "223.5.5.5")
    fi
    
    # 更新resolv.conf
    log_info "更新/etc/resolv.conf..."
    {
        echo "# DNS配置 - 由docker-config-syntax修复脚本生成"
        echo "# 生成时间: $(date)"
        for dns in "${working_dns[@]:0:3}"; do  # 最多使用3个DNS服务器
            echo "nameserver $dns"
        done
        echo "options timeout:2 attempts:3"
        echo "options rotate"
    } > /etc/resolv.conf
    
    log_success "DNS配置已更新"
    log_info "新DNS配置:"
    cat /etc/resolv.conf
    echo
    
    # 如果系统使用systemd-resolved，也更新其配置
    if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
        log_info "检测到systemd-resolved，更新其配置..."
        
        # 备份原配置
        [[ -f /etc/systemd/resolved.conf ]] && \
            cp /etc/systemd/resolved.conf /etc/systemd/resolved.conf.backup.$(date +%Y%m%d-%H%M%S)
        
        # 更新resolved.conf
        {
            echo "[Resolve]"
            echo "DNS=${working_dns[*]}"
            echo "FallbackDNS=8.8.8.8 1.1.1.1"
            echo "Domains=~."
            echo "DNSSEC=no"
            echo "DNSOverTLS=no"
            echo "Cache=yes"
            echo "DNSStubListener=yes"
        } > /etc/systemd/resolved.conf
        
        # 重启systemd-resolved
        systemctl restart systemd-resolved
        log_success "systemd-resolved配置已更新"
    fi
}

# 测试网络连接
test_network_connectivity() {
    log_info "=== 测试网络连接 ==="
    
    local test_hosts=(
        "8.8.8.8"                    # Google DNS
        "114.114.114.114"             # 114 DNS
        "registry.cn-hangzhou.aliyuncs.com"  # 阿里云镜像源
        "google.com"                  # 域名解析测试
    )
    
    local success_count=0
    
    for host in "${test_hosts[@]}"; do
        log_info "测试连接: $host"
        if timeout 5 ping -c 1 -W 3 "$host" >/dev/null 2>&1; then
            log_success "连接成功: $host"
            ((success_count++))
        else
            log_error "连接失败: $host"
        fi
    done
    
    echo
    log_info "网络连接测试结果: $success_count/${#test_hosts[@]} 成功"
    
    if [[ $success_count -eq 0 ]]; then
        log_error "所有网络连接测试失败，请检查网络配置"
        return 1
    elif [[ $success_count -lt ${#test_hosts[@]} ]]; then
        log_warning "部分网络连接失败，可能影响Docker功能"
        return 0
    else
        log_success "所有网络连接测试通过"
        return 0
    fi
}

# 重启Docker服务
restart_docker_service() {
    log_info "=== 重启Docker服务 ==="
    
    # 停止Docker服务
    log_info "停止Docker服务..."
    systemctl stop docker.socket docker.service 2>/dev/null || true
    
    # 等待服务完全停止
    sleep 3
    
    # 重新加载systemd配置
    systemctl daemon-reload
    
    # 启动Docker服务
    log_info "启动Docker服务..."
    if systemctl start docker.service; then
        log_success "Docker服务启动成功"
        
        # 等待服务完全启动
        sleep 5
        
        # 验证服务状态
        if systemctl is-active --quiet docker; then
            log_success "Docker服务运行正常"
            return 0
        else
            log_error "Docker服务状态异常"
            systemctl status docker.service --no-pager -l
            return 1
        fi
    else
        log_error "Docker服务启动失败"
        log_info "查看详细错误信息:"
        journalctl -xeu docker.service --no-pager -l --since "1 minute ago"
        return 1
    fi
}

# 验证Docker功能
verify_docker_functionality() {
    log_info "=== 验证Docker功能 ==="
    
    # 测试Docker版本
    log_info "1. 测试Docker版本:"
    if timeout 10 docker --version; then
        log_success "Docker版本命令正常"
    else
        log_error "Docker版本命令失败"
        return 1
    fi
    
    # 测试Docker信息
    log_info "2. 测试Docker信息:"
    if timeout 30 docker info >/dev/null 2>&1; then
        log_success "Docker信息命令正常"
    else
        log_error "Docker信息命令失败"
        return 1
    fi
    
    # 测试镜像拉取（使用小镜像）
    log_info "3. 测试镜像拉取:"
    if timeout 60 docker pull hello-world >/dev/null 2>&1; then
        log_success "镜像拉取测试成功"
        
        # 测试容器运行
        log_info "4. 测试容器运行:"
        if timeout 30 docker run --rm hello-world >/dev/null 2>&1; then
            log_success "容器运行测试成功"
        else
            log_warning "容器运行测试失败"
        fi
    else
        log_warning "镜像拉取测试失败，可能是网络问题"
    fi
    
    echo
}

# 显示修复报告
show_repair_report() {
    log_info "=== Docker配置语法修复报告 ==="
    echo
    log_info "修复步骤:"
    echo "  ✓ 依赖工具安装"
    echo "  ✓ 配置文件备份"
    echo "  ✓ daemon.json语法修复"
    echo "  ✓ DNS配置修复"
    echo "  ✓ 网络连接测试"
    echo "  ✓ Docker服务重启"
    echo "  ✓ Docker功能验证"
    echo
    log_info "配置文件位置:"
    echo "  - Docker配置: /etc/docker/daemon.json"
    echo "  - DNS配置: /etc/resolv.conf"
    echo "  - 备份位置: $(cat /tmp/docker-config-backup-path 2>/dev/null || echo '未创建备份')"
    echo
    log_info "如果问题仍然存在，请检查:"
    echo "  1. 系统防火墙设置"
    echo "  2. SELinux状态和策略"
    echo "  3. 磁盘空间和权限"
    echo "  4. 网络代理设置"
    echo "  5. Docker版本兼容性"
    echo
    log_info "手动验证命令:"
    echo "  - jq empty /etc/docker/daemon.json  # 验证JSON语法"
    echo "  - systemctl status docker.service  # 检查服务状态"
    echo "  - docker info                      # 检查Docker信息"
    echo "  - nslookup google.com              # 测试DNS解析"
    echo
    log_success "配置语法修复脚本执行完成！"
}

# 主函数
main() {
    echo "=== Docker配置语法修复脚本 ==="
    echo "版本: 1.0.0 - 专门解决daemon.json语法错误和DNS配置问题"
    echo "日期: $(date)"
    echo
    
    # 检查权限
    check_root
    
    # 安装依赖
    install_dependencies
    
    # 创建备份
    create_backup
    
    echo
    log_info "开始配置修复..."
    echo
    
    # 执行修复步骤
    fix_daemon_json
    fix_dns_config
    test_network_connectivity
    restart_docker_service
    
    echo
    log_info "修复完成，开始验证..."
    echo
    
    # 验证修复结果
    verify_docker_functionality
    
    echo
    # 显示报告
    show_repair_report
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi