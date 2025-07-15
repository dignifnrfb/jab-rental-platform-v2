#!/bin/bash

# JAB租赁平台传统部署脚本
# 支持Ubuntu/Debian/CentOS系统
# 版本: 2.0
# 更新: 2024-12-19

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

# 显示横幅
show_banner() {
    echo -e "${BLUE}"
    echo " 🐳 JAB租赁平台传统部署脚本 "
    echo " ================================================ "
    echo -e "${YELLOW} ⚠️  注意: 此脚本将安装Node.js、PostgreSQL、Redis、Nginx等组件 ${NC}"
    echo -e "${YELLOW} ⚠️  请确保在干净的服务器环境中运行 ${NC}"
    echo ""
}

# 检测操作系统
detect_os() {
    if [[ -f /etc/os-release ]]; then
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
        log_warning "检测到正在使用root用户运行脚本"
        log_info "建议创建普通用户并添加sudo权限以提高安全性"
        echo ""
        read -p "是否继续使用root用户安装? (y/N): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "安装已取消，请创建普通用户后重新运行"
            log_info "创建用户命令: useradd -m -s /bin/bash username && usermod -aG sudo username"
            exit 0
        fi
        log_warning "继续使用root用户安装..."
        IS_ROOT=true
    else
        # 检查sudo权限
        if ! sudo -n true 2>/dev/null; then
            log_error "当前用户没有sudo权限，请联系管理员"
            exit 1
        fi
        IS_ROOT=false
        log_success "权限检查通过"
    fi
}

# 更新系统
update_system() {
    log_info "更新系统包..."
    
    local SUDO_CMD=""
    if [[ "$IS_ROOT" != "true" ]]; then
        SUDO_CMD="sudo"
    fi
    
    if [[ "$OS" == *"Ubuntu"* ]] || [[ "$OS" == *"Debian"* ]]; then
        $SUDO_CMD apt update && $SUDO_CMD apt upgrade -y
        $SUDO_CMD apt install -y curl wget gnupg2 software-properties-common apt-transport-https ca-certificates lsb-release
    elif [[ "$OS" == *"CentOS"* ]] || [[ "$OS" == *"Red Hat"* ]]; then
        $SUDO_CMD yum update -y
        $SUDO_CMD yum install -y curl wget gnupg2 ca-certificates
    else
        log_error "不支持的操作系统: $OS"
        exit 1
    fi
    
    log_success "系统更新完成"
}

# 安装Node.js 18
install_nodejs() {
    log_info "安装Node.js 18..."
    
    local SUDO_CMD=""
    if [[ "$IS_ROOT" != "true" ]]; then
        SUDO_CMD="sudo"
    fi
    
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
        if [[ "$IS_ROOT" == "true" ]]; then
            curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
        else
            curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
        fi
        $SUDO_CMD apt install -y nodejs
        
        # 安装构建工具
        $SUDO_CMD apt install -y build-essential python3 python3-pip
    elif [[ "$OS" == *"CentOS"* ]] || [[ "$OS" == *"Red Hat"* ]]; then
        # 添加NodeSource仓库
        curl -fsSL https://rpm.nodesource.com/setup_18.x | $SUDO_CMD bash -
        $SUDO_CMD yum install -y nodejs
        
        # 安装构建工具
        $SUDO_CMD yum groupinstall -y "Development Tools"
        $SUDO_CMD yum install -y python3 python3-pip
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
    
    local SUDO_CMD=""
    if [[ "$IS_ROOT" != "true" ]]; then
        SUDO_CMD="sudo"
    fi
    
    # 检查是否已安装
    if command -v psql &> /dev/null; then
        log_info "检测到已安装的PostgreSQL"
        if $SUDO_CMD systemctl is-active --quiet postgresql; then
            log_success "PostgreSQL服务正在运行，跳过安装"
            return 0
        fi
    fi
    
    if [[ "$OS" == *"Ubuntu"* ]] || [[ "$OS" == *"Debian"* ]]; then
        $SUDO_CMD apt install -y postgresql postgresql-contrib
    elif [[ "$OS" == *"CentOS"* ]] || [[ "$OS" == *"Red Hat"* ]]; then
        $SUDO_CMD yum install -y postgresql-server postgresql-contrib
        $SUDO_CMD postgresql-setup initdb
    fi
    
    # 启动并启用PostgreSQL服务
    $SUDO_CMD systemctl start postgresql
    $SUDO_CMD systemctl enable postgresql
    
    # 验证安装
    if $SUDO_CMD systemctl is-active --quiet postgresql; then
        log_success "PostgreSQL安装并启动成功"
    else
        log_error "PostgreSQL安装失败"
        exit 1
    fi
}

# 安装Redis
install_redis() {
    log_info "安装Redis..."
    
    local SUDO_CMD=""
    if [[ "$IS_ROOT" != "true" ]]; then
        SUDO_CMD="sudo"
    fi
    
    # 检查是否已安装
    if command -v redis-server &> /dev/null; then
        log_info "检测到已安装的Redis"
        if $SUDO_CMD systemctl is-active --quiet redis || $SUDO_CMD systemctl is-active --quiet redis-server; then
            log_success "Redis服务正在运行，跳过安装"
            return 0
        fi
    fi
    
    if [[ "$OS" == *"Ubuntu"* ]] || [[ "$OS" == *"Debian"* ]]; then
        $SUDO_CMD apt install -y redis-server
    elif [[ "$OS" == *"CentOS"* ]] || [[ "$OS" == *"Red Hat"* ]]; then
        $SUDO_CMD yum install -y redis
    fi
    
    # 启动并启用Redis服务
    if [[ "$OS" == *"Ubuntu"* ]] || [[ "$OS" == *"Debian"* ]]; then
        $SUDO_CMD systemctl start redis-server
        $SUDO_CMD systemctl enable redis-server
        REDIS_SERVICE="redis-server"
    else
        $SUDO_CMD systemctl start redis
        $SUDO_CMD systemctl enable redis
        REDIS_SERVICE="redis"
    fi
    
    # 验证安装
    if $SUDO_CMD systemctl is-active --quiet $REDIS_SERVICE; then
        log_success "Redis安装并启动成功"
    else
        log_error "Redis安装失败"
        exit 1
    fi
}

# 安装Nginx
install_nginx() {
    log_info "安装Nginx..."
    
    local SUDO_CMD=""
    if [[ "$IS_ROOT" != "true" ]]; then
        SUDO_CMD="sudo"
    fi
    
    # 检查是否已安装
    if command -v nginx &> /dev/null; then
        log_info "检测到已安装的Nginx"
        if $SUDO_CMD systemctl is-active --quiet nginx; then
            log_success "Nginx服务正在运行，跳过安装"
            return 0
        fi
    fi
    
    if [[ "$OS" == *"Ubuntu"* ]] || [[ "$OS" == *"Debian"* ]]; then
        $SUDO_CMD apt install -y nginx
    elif [[ "$OS" == *"CentOS"* ]] || [[ "$OS" == *"Red Hat"* ]]; then
        $SUDO_CMD yum install -y nginx
    fi
    
    # 启动并启用Nginx服务
    $SUDO_CMD systemctl start nginx
    $SUDO_CMD systemctl enable nginx
    
    # 验证安装
    if $SUDO_CMD systemctl is-active --quiet nginx; then
        log_success "Nginx安装并启动成功"
    else
        log_error "Nginx安装失败"
        exit 1
    fi
}

# 安装PM2
install_pm2() {
    log_info "安装PM2进程管理器..."
    
    # 检查是否已安装
    if command -v pm2 &> /dev/null; then
        log_success "PM2已安装，版本: $(pm2 --version)"
        return 0
    fi
    
    # 全局安装PM2
    npm install -g pm2
    
    # 验证安装
    if command -v pm2 &> /dev/null; then
        log_success "PM2安装成功，版本: $(pm2 --version)"
        
        # 设置PM2开机自启
        if [[ "$IS_ROOT" == "true" ]]; then
            log_warning "root用户环境下，请在部署应用后手动配置PM2开机自启"
        else
            sudo env PATH=$PATH:/usr/bin pm2 startup systemd -u $USER --hp $HOME
        fi
    else
        log_error "PM2安装失败"
        exit 1
    fi
}

# 创建应用用户和目录
create_app_user() {
    log_info "创建应用用户和目录..."
    
    local SUDO_CMD=""
    if [[ "$IS_ROOT" != "true" ]]; then
        SUDO_CMD="sudo"
    fi
    
    local APP_USER="jab"
    local CREATE_APP_USER=true
    
    # 如果是root用户运行，询问是否创建专用用户
    if [[ "$IS_ROOT" == "true" ]]; then
        echo ""
        read -p "是否创建专用应用用户 '$APP_USER'? (推荐) (y/N): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            CREATE_APP_USER=true
        else
            CREATE_APP_USER=false
            APP_USER="root"
            log_warning "将使用root用户运行应用，存在安全风险"
        fi
    fi
    
    # 创建应用用户
    if [[ "$CREATE_APP_USER" == "true" ]] && [[ "$APP_USER" != "root" ]]; then
        if ! id "$APP_USER" &>/dev/null; then
            $SUDO_CMD useradd -m -s /bin/bash $APP_USER
            log_success "用户$APP_USER创建成功"
        else
            log_info "用户$APP_USER已存在"
        fi
    fi
    
    # 创建应用目录
    if [[ "$IS_ROOT" == "true" ]] && [[ "$APP_USER" == "root" ]]; then
        mkdir -p /var/www/jab
        mkdir -p /var/log/jab
        chmod -R 755 /var/www/jab
        chmod -R 755 /var/log/jab
    else
        $SUDO_CMD mkdir -p /var/www/jab
        $SUDO_CMD mkdir -p /var/log/jab
        
        # 设置目录权限
        $SUDO_CMD chown -R $APP_USER:$APP_USER /var/www/jab
        $SUDO_CMD chown -R $APP_USER:$APP_USER /var/log/jab
        $SUDO_CMD chmod -R 755 /var/www/jab
        $SUDO_CMD chmod -R 755 /var/log/jab
    fi
    
    log_success "应用目录创建完成"
}

# 配置防火墙
configure_firewall() {
    log_info "配置防火墙..."
    
    local SUDO_CMD=""
    if [[ "$IS_ROOT" != "true" ]]; then
        SUDO_CMD="sudo"
    fi
    
    if command -v ufw &> /dev/null; then
        # Ubuntu/Debian使用ufw
        $SUDO_CMD ufw --force enable
        $SUDO_CMD ufw allow ssh
        $SUDO_CMD ufw allow 80/tcp
        $SUDO_CMD ufw allow 443/tcp
        $SUDO_CMD ufw allow 3000/tcp  # Next.js开发端口
        log_success "UFW防火墙配置完成"
    elif command -v firewall-cmd &> /dev/null; then
        # CentOS/RHEL使用firewalld
        $SUDO_CMD systemctl start firewalld
        $SUDO_CMD systemctl enable firewalld
        $SUDO_CMD firewall-cmd --permanent --add-service=ssh
        $SUDO_CMD firewall-cmd --permanent --add-service=http
        $SUDO_CMD firewall-cmd --permanent --add-service=https
        $SUDO_CMD firewall-cmd --permanent --add-port=3000/tcp
        $SUDO_CMD firewall-cmd --reload
        log_success "Firewalld防火墙配置完成"
    else
        log_warning "未检测到防火墙工具，请手动配置"
    fi
}

# 系统优化
optimize_system() {
    log_info "优化系统参数..."
    
    local SUDO_CMD=""
    if [[ "$IS_ROOT" != "true" ]]; then
        SUDO_CMD="sudo"
    fi
    
    # 创建系统优化配置
    $SUDO_CMD tee /etc/sysctl.d/99-jab-optimization.conf > /dev/null <<EOF
# JAB租赁平台系统优化
# 网络优化
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.tcp_max_tw_buckets = 5000

# 内存优化
vm.swappiness = 10
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5

# 文件系统优化
fs.file-max = 2097152
fs.nr_open = 1048576
EOF
    
    # 应用配置
    $SUDO_CMD sysctl -p /etc/sysctl.d/99-jab-optimization.conf
    
    # 设置用户限制
    $SUDO_CMD tee /etc/security/limits.d/99-jab.conf > /dev/null <<EOF
# JAB应用用户限制
jab soft nofile 65536
jab hard nofile 65536
jab soft nproc 4096
jab hard nproc 4096

# 所有用户限制
* soft nofile 65536
* hard nofile 65536
EOF
    
    log_success "系统优化完成"
}

# 创建快速启动脚本
create_scripts() {
    log_info "创建快速管理脚本..."
    
    # 确定应用用户
    local SCRIPT_APP_USER="jab"
    if [[ "$IS_ROOT" == "true" ]] && [[ "$CREATE_APP_USER" != "true" ]]; then
        SCRIPT_APP_USER="root"
    fi
    
    # 创建快速部署脚本
    cat > deploy-app.sh <<EOF
#!/bin/bash
# deploy-app.sh - 应用部署脚本

set -e

APP_DIR="/var/www/jab"
APP_USER="$SCRIPT_APP_USER"
REPO_URL="https://github.com/dignifnrfb/jab-rental-platform-v2.git"

echo "🚀 开始部署JAB租赁平台..."

# 执行部署操作
if [ "\$APP_USER" = "root" ]; then
    cd \$APP_DIR
    
    # 克隆或更新代码
    if [ -d ".git" ]; then
        echo "📥 更新代码..."
        git pull origin main
    else
        echo "📥 克隆代码..."
        git clone \$REPO_URL .
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
else
    # 切换到应用用户
    sudo -u \$APP_USER bash <<SCRIPT
cd \$APP_DIR

# 克隆或更新代码
if [ -d ".git" ]; then
    echo "📥 更新代码..."
    git pull origin main
else
    echo "📥 克隆代码..."
    git clone \$REPO_URL .
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
fi

echo "✅ 应用部署完成"
echo "💡 使用 ./manage-service.sh start 启动服务"
EOF
    
    # 创建服务管理脚本
    cat > manage-service.sh <<EOF
#!/bin/bash
# manage-service.sh - 服务管理脚本

APP_USER="$SCRIPT_APP_USER"

case "\$1" in
    start)
        echo "🚀 启动JAB租赁平台..."
        if [ "\$APP_USER" = "root" ]; then
            pm2 start /var/www/jab/ecosystem.config.json
        else
            sudo -u \$APP_USER pm2 start /var/www/jab/ecosystem.config.json
        fi
        ;;
    stop)
        echo "🛑 停止JAB租赁平台..."
        if [ "\$APP_USER" = "root" ]; then
            pm2 stop jab-rental
        else
            sudo -u \$APP_USER pm2 stop jab-rental
        fi
        ;;
    restart)
        echo "🔄 重启JAB租赁平台..."
        if [ "\$APP_USER" = "root" ]; then
            pm2 restart jab-rental
        else
            sudo -u \$APP_USER pm2 restart jab-rental
        fi
        ;;
    status)
        echo "📊 JAB租赁平台状态:"
        if [ "\$APP_USER" = "root" ]; then
            pm2 status
        else
            sudo -u \$APP_USER pm2 status
        fi
        ;;
    logs)
        echo "📋 JAB租赁平台日志:"
        if [ "\$APP_USER" = "root" ]; then
            pm2 logs jab-rental
        else
            sudo -u \$APP_USER pm2 logs jab-rental
        fi
        ;;
    monitor)
        echo "📊 JAB租赁平台监控:"
        if [ "\$APP_USER" = "root" ]; then
            pm2 monit
        else
            sudo -u \$APP_USER pm2 monit
        fi
        ;;
    *)
        echo "用法: \$0 {start|stop|restart|status|logs|monitor}"
        exit 1
        ;;
esac
EOF
    
    # 设置执行权限
    chmod +x deploy-app.sh
    chmod +x manage-service.sh
    
    log_success "管理脚本创建完成"
    log_info "部署脚本: ./deploy-app.sh"
    log_info "管理脚本: ./manage-service.sh"
}

# 显示安装总结
show_summary() {
    echo ""
    echo -e "${GREEN}🎉 JAB租赁平台环境安装完成！${NC}"
    echo -e "${BLUE}================================================${NC}"
    echo ""
    echo -e "${YELLOW}📋 安装组件:${NC}"
    echo "   ✅ Node.js $(node --version)"
    echo "   ✅ npm $(npm --version)"
    echo "   ✅ PM2 $(pm2 --version)"
    echo "   ✅ PostgreSQL"
    echo "   ✅ Redis"
    echo "   ✅ Nginx"
    echo ""
    echo -e "${YELLOW}📁 重要目录:${NC}"
    echo "   📂 应用目录: /var/www/jab"
    echo "   📂 日志目录: /var/log/jab"
    echo ""
    echo -e "${YELLOW}🔧 管理脚本:${NC}"
    echo "   🚀 部署应用: ./deploy-app.sh"
    echo "   ⚙️  管理服务: ./manage-service.sh {start|stop|restart|status|logs|monitor}"
    echo ""
    echo -e "${YELLOW}📖 下一步操作:${NC}"
    echo "   1. 配置环境变量 (.env 文件)"
    echo "   2. 配置数据库连接"
    echo "   3. 运行 ./deploy-app.sh 部署应用"
    echo "   4. 运行 ./manage-service.sh start 启动服务"
    echo ""
    echo -e "${BLUE}📚 更多信息请查看: DEPLOYMENT_ALTERNATIVES.md${NC}"
    echo ""
}

# 主函数
main() {
    show_banner
    
    # 确认安装
    read -p "是否继续安装? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "安装已取消"
        exit 0
    fi
    
    echo ""
    log_info "🚀 开始安装..."
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
    create_app_user
    configure_firewall
    optimize_system
    create_scripts
    
    # 显示总结
    show_summary
}

# 运行主函数
main "$@"