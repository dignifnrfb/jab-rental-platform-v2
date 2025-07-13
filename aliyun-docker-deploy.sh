#!/bin/bash

# JAB租赁平台 - 阿里云ECS Docker一键部署脚本
# 适用于4GB内存的ECS实例

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

# 检查系统资源
check_system_resources() {
    log_info "检查系统资源..."
    
    # 检查内存
    TOTAL_MEM=$(free -m | awk 'NR==2{printf "%.0f", $2}')
    if [ "$TOTAL_MEM" -lt 3500 ]; then
        log_warning "系统内存不足4GB，当前: ${TOTAL_MEM}MB"
        log_warning "建议升级到4GB或更高内存的ECS实例"
    else
        log_success "内存检查通过: ${TOTAL_MEM}MB"
    fi
    
    # 检查磁盘空间
    DISK_SPACE=$(df -h / | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "${DISK_SPACE%.*}" -lt 10 ]; then
        log_error "磁盘空间不足，至少需要10GB可用空间"
        exit 1
    else
        log_success "磁盘空间检查通过: ${DISK_SPACE}G可用"
    fi
}

# 安装Docker
install_docker() {
    if command -v docker &> /dev/null; then
        log_success "Docker已安装"
        return
    fi
    
    log_info "安装Docker..."
    
    # 更新包管理器
    sudo apt-get update
    
    # 安装必要的包
    sudo apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release
    
    # 添加Docker官方GPG密钥
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    # 添加Docker仓库
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # 安装Docker Engine
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io
    
    # 启动Docker服务
    sudo systemctl start docker
    sudo systemctl enable docker
    
    # 将当前用户添加到docker组
    sudo usermod -aG docker $USER
    
    log_success "Docker安装完成"
}

# 安装Docker Compose
install_docker_compose() {
    if command -v docker-compose &> /dev/null; then
        log_success "Docker Compose已安装"
        return
    fi
    
    log_info "安装Docker Compose..."
    
    # 下载Docker Compose
    sudo curl -L "https://github.com/docker/compose/releases/download/v2.20.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    
    # 添加执行权限
    sudo chmod +x /usr/local/bin/docker-compose
    
    # 创建软链接
    sudo ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
    
    log_success "Docker Compose安装完成"
}

# 设置项目目录
setup_project_directory() {
    log_info "设置项目目录..."
    
    PROJECT_DIR="/opt/jab-rental"
    
    # 创建项目目录
    sudo mkdir -p $PROJECT_DIR
    sudo chown $USER:$USER $PROJECT_DIR
    
    # 创建必要的子目录
    mkdir -p $PROJECT_DIR/{data,logs,nginx,ssl}
    mkdir -p $PROJECT_DIR/data/{postgres,redis}
    
    log_success "项目目录创建完成: $PROJECT_DIR"
}

# 配置PostgreSQL
setup_postgresql() {
    log_info "配置PostgreSQL..."
    
    # 创建PostgreSQL初始化脚本
    cat > /opt/jab-rental/init-db.sql << 'EOF'
-- 创建数据库
CREATE DATABASE jab_rental;

-- 创建用户
CREATE USER jab_user WITH ENCRYPTED PASSWORD 'jab_password_2024';

-- 授权
GRANT ALL PRIVILEGES ON DATABASE jab_rental TO jab_user;
ALTER USER jab_user CREATEDB;

-- 连接到jab_rental数据库
\c jab_rental;

-- 授权schema权限
GRANT ALL ON SCHEMA public TO jab_user;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO jab_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO jab_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO jab_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO jab_user;
EOF

    log_success "PostgreSQL配置完成"
}

# 配置Nginx
setup_nginx() {
    log_info "配置Nginx..."
    
    # 创建Nginx配置文件
    cat > /opt/jab-rental/nginx/nginx.conf << 'EOF'
events {
    worker_connections 1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    
    # 日志格式
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';
    
    # Gzip压缩
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/xml+rss application/json;
    
    # 上游服务器
    upstream jab_app {
        server jab-app:3000;
    }
    
    # 限制请求速率
    limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
    
    server {
        listen 80;
        server_name _;
        
        # 安全头
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;
        
        # 静态文件缓存
        location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
            expires 1y;
            add_header Cache-Control "public, immutable";
            proxy_pass http://jab_app;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
        
        # API路由
        location /api/ {
            limit_req zone=api burst=20 nodelay;
            proxy_pass http://jab_app;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_connect_timeout 30s;
            proxy_send_timeout 30s;
            proxy_read_timeout 30s;
        }
        
        # 主应用
        location / {
            proxy_pass http://jab_app;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_connect_timeout 30s;
            proxy_send_timeout 30s;
            proxy_read_timeout 30s;
            
            # WebSocket支持
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
        }
        
        # 健康检查
        location /health {
            access_log off;
            return 200 "healthy\n";
            add_header Content-Type text/plain;
        }
    }
}
EOF

    log_success "Nginx配置完成"
}

# 创建环境变量文件
setup_environment() {
    log_info "创建环境变量文件..."
    
    cat > /opt/jab-rental/.env << 'EOF'
# 数据库配置
DATABASE_URL="postgresql://jab_user:jab_password_2024@postgres:5432/jab_rental?schema=public"
POSTGRES_DB=jab_rental
POSTGRES_USER=jab_user
POSTGRES_PASSWORD=jab_password_2024

# Redis配置
REDIS_URL="redis://redis:6379"

# 应用配置
NEXT_PUBLIC_APP_URL=http://localhost
NEXTAUTH_SECRET=your-nextauth-secret-key-change-this-in-production
NEXTAUTH_URL=http://localhost

# 文件上传配置
UPLOAD_MAX_SIZE=10485760
UPLOAD_ALLOWED_TYPES=image/jpeg,image/png,image/webp

# 邮件配置（可选）
SMTP_HOST=
SMTP_PORT=587
SMTP_USER=
SMTP_PASS=
SMTP_FROM=

# 支付配置（可选）
STRIPE_PUBLIC_KEY=
STRIPE_SECRET_KEY=
STRIPE_WEBHOOK_SECRET=

# 监控配置
NODE_ENV=production
LOG_LEVEL=info
EOF

    log_success "环境变量文件创建完成"
}

# 启动服务
start_services() {
    log_info "启动Docker服务..."
    
    # 确保在项目目录
    cd /opt/jab-rental
    
    # 跳过 docker-compose pull（避免段错误），直接启动服务
    # Docker会自动拉取缺失的镜像
    log_info "启动服务（Docker将自动拉取所需镜像）..."
    
    # 构建并启动服务
    docker-compose up -d
    
    # 等待服务启动
    log_info "等待服务启动..."
    sleep 30
    
    # 检查服务状态
    docker-compose ps
    
    log_success "Docker服务启动完成"
}

# 部署应用
deploy_application() {
    log_info "部署应用..."
    
    cd /opt/jab-rental
    
    # 启动服务
    start_services
    
    # 等待服务启动
    log_info "等待服务启动..."
    sleep 30
    
    # 检查服务状态
    if docker-compose ps | grep -q "Up"; then
        log_success "应用部署成功！"
    else
        log_error "应用部署失败，请检查日志"
        docker-compose logs
        exit 1
    fi
}

# 显示部署信息
show_deployment_info() {
    log_success "=== JAB租赁平台部署完成 ==="
    echo
    log_info "访问地址: http://$(curl -s ifconfig.me)"
    log_info "管理命令:"
    echo "  查看服务状态: cd /opt/jab-rental && docker-compose ps"
    echo "  查看日志: cd /opt/jab-rental && docker-compose logs -f"
    echo "  重启服务: cd /opt/jab-rental && docker-compose restart"
    echo "  停止服务: cd /opt/jab-rental && docker-compose down"
    echo "  更新应用: cd /opt/jab-rental && docker-compose pull && docker-compose up -d"
    echo
    log_info "配置文件位置:"
    echo "  环境变量: /opt/jab-rental/.env"
    echo "  Nginx配置: /opt/jab-rental/nginx/nginx.conf"
    echo "  Docker Compose: /opt/jab-rental/docker-compose.yml"
    echo
    log_warning "请记得修改默认密码和密钥！"
}

# 主函数
main() {
    log_info "开始部署JAB租赁平台..."
    
    check_system_resources
    install_docker
    install_docker_compose
    setup_project_directory
    setup_postgresql
    setup_nginx
    setup_environment
    
    # 复制docker-compose.yml到项目目录
    if [ -f "docker-compose.yml" ]; then
        cp docker-compose.yml /opt/jab-rental/
    else
        log_error "docker-compose.yml文件不存在，请确保在项目根目录运行此脚本"
        exit 1
    fi
    
    deploy_application
    show_deployment_info
    
    log_success "部署完成！"
}

# 运行主函数
main "$@"