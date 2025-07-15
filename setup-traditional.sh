#!/bin/bash
# setup-traditional.sh - JAB租赁平台传统部署脚本
# 完整的服务器环境配置，无需Docker
# 适用于Ubuntu 20.04+ / Debian 11+ / CentOS 8+

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

# 检测操作系统
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
    else
        log_error "无法检测操作系统"
        exit 1
    fi
    log_info "检测到操作系统: $OS $VER"
}

# 检查root权限
check_root() {
    if [[ $EUID -eq 0 ]]; then
        log_warning "请不要使用root用户运行此脚本"
        log_info "建议创建普通用户并添加sudo权限"
        exit 1
    fi
    
    # 检查sudo权限
    if ! sudo -n true 2>/dev/null; then
        log_error "当前用户没有sudo权限，请联系管理员"
        exit 1
    fi
    
    log_success "权限检查通过"
}

# 更新系统
update_system() {
    log_info "更新系统包..."
    
    if [[ "$OS" == *"Ubuntu"* ]] || [[ "$OS" == *"Debian"* ]]; then
        sudo apt update && sudo apt upgrade -y
        sudo apt install -y curl wget gnupg2 software-properties-common apt-transport-https ca-certificates lsb-release
    elif [[ "$OS" == *"CentOS"* ]] || [[ "$OS" == *"Red Hat"* ]]; then
        sudo yum update -y
        sudo yum install -y curl wget gnupg2 ca-certificates
    else
        log_error "不支持的操作系统: $OS"
        exit 1
    fi
    
    log_success "系统更新完成"
}

# 安装Node.js 18
install_nodejs() {
    log_info "安装Node.js 18..."
    
    # 检查是否已安装
    if command -v node &> /dev/null; then
        NODE_VERSION=$(node --version)
        log_info "检测到已安装的Node.js版本: $NODE_VERSION"
        
        # 检查版本是否符合要求
        if [[ "$NODE_VERSION" == v18* ]]; then
            log_success "Node.js版本符合要求，跳过安装"
            return 0
        else
            log_warning "Node.js版本不符合要求，将重新安装"
        fi
    fi
    
    if [[ "$OS" == *"Ubuntu"* ]] || [[ "$OS" == *"Debian"* ]]; then
        # 添加NodeSource仓库
        curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
        sudo apt install -y nodejs
        
        # 安装构建工具
        sudo apt install -y build-essential python3 python3-pip
    elif [[ "$OS" == *"CentOS"* ]] || [[ "$OS" == *"Red Hat"* ]]; then
        # 添加NodeSource仓库
        curl -fsSL https://rpm.nodesource.com/setup_18.x | sudo bash -
        sudo yum install -y nodejs
        
        # 安装构建工具
        sudo yum groupinstall -y "Development Tools"
        sudo yum install -y python3 python3-pip
    fi
    
    # 验证安装
    if command -v node &> /dev/null && command -v npm &> /dev/null; then
        log_success "Node.js安装成功: $(node --version)"
        log_success "npm版本: $(npm --version)"
    else
        log_error "Node.js安装失败"
        exit 1
    fi
    
    # 配置npm镜像源
    npm config set registry https://registry.npmmirror.com
    log_success "npm镜像源配置完成"
}

# 安装PostgreSQL
install_postgresql() {
    log_info "安装PostgreSQL..."
    
    if [[ "$OS" == *"Ubuntu"* ]] || [[ "$OS" == *"Debian"* ]]; then
        sudo apt install -y postgresql postgresql-contrib
    elif [[ "$OS" == *"CentOS"* ]] || [[ "$OS" == *"Red Hat"* ]]; then
        sudo yum install -y postgresql-server postgresql-contrib
        sudo postgresql-setup initdb
    fi
    
    # 启动并启用服务
    sudo systemctl start postgresql
    sudo systemctl enable postgresql
    
    # 验证安装
    if sudo systemctl is-active --quiet postgresql; then
        log_success "PostgreSQL安装并启动成功"
    else
        log_error "PostgreSQL启动失败"
        exit 1
    fi
}

# 安装Redis
install_redis() {
    log_info "安装Redis..."
    
    if [[ "$OS" == *"Ubuntu"* ]] || [[ "$OS" == *"Debian"* ]]; then
        sudo apt install -y redis-server
    elif [[ "$OS" == *"CentOS"* ]] || [[ "$OS" == *"Red Hat"* ]]; then
        sudo yum install -y epel-release
        sudo yum install -y redis
    fi
    
    # 启动并启用服务
    sudo systemctl start redis-server || sudo systemctl start redis
    sudo systemctl enable redis-server || sudo systemctl enable redis
    
    # 验证安装
    if redis-cli ping | grep -q PONG; then
        log_success "Redis安装并启动成功"
    else
        log_error "Redis启动失败"
        exit 1
    fi
}

# 安装Nginx
install_nginx() {
    log_info "安装Nginx..."
    
    if [[ "$OS" == *"Ubuntu"* ]] || [[ "$OS" == *"Debian"* ]]; then
        sudo apt install -y nginx
    elif [[ "$OS" == *"CentOS"* ]] || [[ "$OS" == *"Red Hat"* ]]; then
        sudo yum install -y nginx
    fi
    
    # 启动并启用服务
    sudo systemctl start nginx
    sudo systemctl enable nginx
    
    # 验证安装
    if sudo systemctl is-active --quiet nginx; then
        log_success "Nginx安装并启动成功"
    else
        log_error "Nginx启动失败"
        exit 1
    fi
}

# 安装PM2
install_pm2() {
    log_info "安装PM2进程管理器..."
    
    sudo npm install -g pm2
    
    # 验证安装
    if command -v pm2 &> /dev/null; then
        log_success "PM2安装成功: $(pm2 --version)"
    else
        log_error "PM2安装失败"
        exit 1
    fi
}

# 创建应用用户和目录
setup_app_user() {
    log_info "创建应用用户和目录..."
    
    # 创建jab用户（如果不存在）
    if ! id "jab" &>/dev/null; then
        sudo useradd -m -s /bin/bash jab
        log_success "用户jab创建成功"
    else
        log_info "用户jab已存在"
    fi
    
    # 创建应用目录
    sudo mkdir -p /var/www/jab
    sudo mkdir -p /var/log/jab
    
    # 设置目录权限
    sudo chown -R jab:jab /var/www/jab
    sudo chown -R jab:jab /var/log/jab
    sudo chmod -R 755 /var/www/jab
    sudo chmod -R 755 /var/log/jab
    
    log_success "应用目录创建完成"
}

# 配置防火墙
setup_firewall() {
    log_info "配置防火墙..."
    
    if command -v ufw &> /dev/null; then
        # Ubuntu/Debian使用ufw
        sudo ufw --force enable
        sudo ufw allow ssh
        sudo ufw allow 80/tcp
        sudo ufw allow 443/tcp
        sudo ufw allow 3000/tcp  # 开发环境
        log_success "ufw防火墙配置完成"
    elif command -v firewall-cmd &> /dev/null; then
        # CentOS/RHEL使用firewalld
        sudo systemctl start firewalld
        sudo systemctl enable firewalld
        sudo firewall-cmd --permanent --add-service=ssh
        sudo firewall-cmd --permanent --add-service=http
        sudo firewall-cmd --permanent --add-service=https
        sudo firewall-cmd --permanent --add-port=3000/tcp
        sudo firewall-cmd --reload
        log_success "firewalld防火墙配置完成"
    else
        log_warning "未检测到防火墙，请手动配置"
    fi
}

# 优化系统参数
optimize_system() {
    log_info "优化系统参数..."
    
    # 创建系统优化配置
    sudo tee /etc/sysctl.d/99-jab-optimization.conf > /dev/null <<EOF
# JAB租赁平台系统优化
# 网络优化
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_congestion_control = bbr

# 文件描述符限制
fs.file-max = 65536

# 虚拟内存优化
vm.swappiness = 10
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
EOF
    
    # 应用配置
    sudo sysctl -p /etc/sysctl.d/99-jab-optimization.conf
    
    # 设置用户限制
    sudo tee /etc/security/limits.d/99-jab.conf > /dev/null <<EOF
# JAB应用用户限制
jab soft nofile 65536
jab hard nofile 65536
jab soft nproc 4096
jab hard nproc 4096
EOF
    
    log_success "系统优化完成"
}

# 创建快速启动脚本
create_quick_scripts() {
    log_info "创建快速管理脚本..."
    
    # 创建快速部署脚本
    cat > deploy-app.sh <<'EOF'
#!/bin/bash
# deploy-app.sh - 应用部署脚本

set -e

APP_DIR="/var/www/jab"
REPO_URL="https://github.com/dignifnrfb/jab-rental-platform-v2.git"

echo "🚀 开始部署JAB租赁平台..."

# 切换到应用用户
sudo -u jab bash <<SCRIPT
cd $APP_DIR

# 克隆或更新代码
if [ -d ".git" ]; then
    echo "📥 更新代码..."
    git pull origin main
else
    echo "📥 克隆代码..."
    git clone $REPO_URL .
fi

# 安装依赖
echo "📦 安装依赖..."
npm ci --production

# 构建应用
echo "🔨 构建应用..."
npm run build

# 生成Prisma客户端
echo "🗄️ 生成数据库客户端..."
npx prisma generate

# 运行数据库迁移
echo "🗄️ 运行数据库迁移..."
npx prisma migrate deploy
SCRIPT

echo "✅ 应用部署完成"
EOF
    
    # 创建服务管理脚本
    cat > manage-service.sh <<'EOF'
#!/bin/bash
# manage-service.sh - 服务管理脚本

case "$1" in
    start)
        echo "🚀 启动JAB租赁平台..."
        sudo -u jab pm2 start /var/www/jab/ecosystem.config.json
        ;;
    stop)
        echo "🛑 停止JAB租赁平台..."
        sudo -u jab pm2 stop jab-rental
        ;;
    restart)
        echo "🔄 重启JAB租赁平台..."
        sudo -u jab pm2 restart jab-rental
        ;;
    status)
        echo "📊 JAB租赁平台状态:"
        sudo -u jab pm2 status
        ;;
    logs)
        echo "📋 JAB租赁平台日志:"
        sudo -u jab pm2 logs jab-rental
        ;;
    monitor)
        echo "📊 JAB租赁平台监控:"
        sudo -u jab pm2 monit
        ;;
    *)
        echo "用法: $0 {start|stop|restart|status|logs|monitor}"
        exit 1
        ;;
esac
EOF
    
    # 设置执行权限
    chmod +x deploy-app.sh
    chmod +x manage-service.sh
    
    log_success "管理脚本创建完成"
}

# 显示安装总结
show_summary() {
    echo ""
    echo "🎉 JAB租赁平台传统部署环境安装完成！"
    echo "================================================"
    echo ""
    echo "📋 已安装的组件:"
    echo "   ✅ Node.js $(node --version)"
    echo "   ✅ npm $(npm --version)"
    echo "   ✅ PostgreSQL $(sudo -u postgres psql -c 'SELECT version();' | head -3 | tail -1 | cut -d' ' -f2)"
    echo "   ✅ Redis $(redis-cli --version | cut -d' ' -f2)"
    echo "   ✅ Nginx $(nginx -v 2>&1 | cut -d' ' -f3 | cut -d'/' -f2)"
    echo "   ✅ PM2 $(pm2 --version)"
    echo ""
    echo "📁 目录结构:"
    echo "   📂 应用目录: /var/www/jab"
    echo "   📂 日志目录: /var/log/jab"
    echo "   👤 应用用户: jab"
    echo ""
    echo "🔧 下一步操作:"
    echo "   1. 配置数据库: ./setup-database.sh"
    echo "   2. 部署应用: ./deploy-app.sh"
    echo "   3. 启动服务: ./manage-service.sh start"
    echo ""
    echo "📖 更多信息请查看: DEPLOYMENT_ALTERNATIVES.md"
    echo ""
}

# 主函数
main() {
    echo "🐳 JAB租赁平台传统部署脚本"
    echo "================================================"
    echo "⚠️  注意: 此脚本将安装Node.js、PostgreSQL、Redis、Nginx等组件"
    echo "⚠️  请确保在干净的服务器环境中运行"
    echo ""
    read -p "是否继续安装? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "安装已取消"
        exit 0
    fi
    
    echo ""
    echo "🚀 开始安装..."
    echo ""
    
    # 执行安装步骤
    detect_os
    check_root
    update_system
    install_nodejs
    install_postgresql
    install_redis
    install_nginx
    install_pm2
    setup_app_user
    setup_firewall
    optimize_system
    create_quick_scripts
    
    # 显示总结
    show_summary
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi