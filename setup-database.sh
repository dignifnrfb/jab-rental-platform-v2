#!/bin/bash
# setup-database.sh - JAB租赁平台数据库配置脚本
# 配置PostgreSQL数据库和Redis

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

# 生成随机密码
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
}

# 配置PostgreSQL
setup_postgresql() {
    log_info "配置PostgreSQL数据库..."
    
    # 检查PostgreSQL是否运行
    if ! sudo systemctl is-active --quiet postgresql; then
        log_error "PostgreSQL服务未运行，请先运行 setup-traditional.sh"
        exit 1
    fi
    
    # 生成数据库密码
    DB_PASSWORD=$(generate_password)
    
    # 创建数据库和用户
    sudo -u postgres psql <<EOF
-- 创建数据库用户
CREATE USER jab_user WITH PASSWORD '$DB_PASSWORD';

-- 创建数据库
CREATE DATABASE jab_rental OWNER jab_user;

-- 授予权限
GRANT ALL PRIVILEGES ON DATABASE jab_rental TO jab_user;

-- 连接到数据库并授予schema权限
\c jab_rental
GRANT ALL ON SCHEMA public TO jab_user;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO jab_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO jab_user;

-- 设置默认权限
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO jab_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO jab_user;

-- 退出
\q
EOF
    
    if [ $? -eq 0 ]; then
        log_success "PostgreSQL数据库配置完成"
        log_info "数据库名: jab_rental"
        log_info "用户名: jab_user"
        log_info "密码: $DB_PASSWORD"
    else
        log_error "PostgreSQL数据库配置失败"
        exit 1
    fi
    
    # 保存数据库连接信息
    cat > /tmp/db_credentials.txt <<EOF
# JAB租赁平台数据库连接信息
DATABASE_URL="postgresql://jab_user:$DB_PASSWORD@localhost:5432/jab_rental"
DB_HOST="localhost"
DB_PORT="5432"
DB_NAME="jab_rental"
DB_USER="jab_user"
DB_PASSWORD="$DB_PASSWORD"
EOF
    
    # 配置PostgreSQL性能优化
    setup_postgresql_optimization
}

# PostgreSQL性能优化
setup_postgresql_optimization() {
    log_info "优化PostgreSQL配置..."
    
    # 获取系统内存大小（MB）
    TOTAL_MEM=$(free -m | awk 'NR==2{printf "%.0f", $2}')
    
    # 计算优化参数
    SHARED_BUFFERS=$((TOTAL_MEM / 4))  # 25%的内存
    EFFECTIVE_CACHE_SIZE=$((TOTAL_MEM * 3 / 4))  # 75%的内存
    WORK_MEM=$((TOTAL_MEM / 64))  # 约1.5%的内存
    MAINTENANCE_WORK_MEM=$((TOTAL_MEM / 16))  # 约6%的内存
    
    # 限制最大值
    [ $SHARED_BUFFERS -gt 8192 ] && SHARED_BUFFERS=8192
    [ $WORK_MEM -gt 256 ] && WORK_MEM=256
    [ $MAINTENANCE_WORK_MEM -gt 2048 ] && MAINTENANCE_WORK_MEM=2048
    
    # 查找PostgreSQL配置文件
    PG_VERSION=$(sudo -u postgres psql -t -c "SELECT version();" | grep -oP '\d+\.\d+' | head -1)
    PG_CONFIG_DIR="/etc/postgresql/$PG_VERSION/main"
    
    if [ ! -d "$PG_CONFIG_DIR" ]; then
        # 尝试其他可能的路径
        PG_CONFIG_DIR=$(sudo -u postgres psql -t -c "SHOW config_file;" | xargs dirname)
    fi
    
    if [ -d "$PG_CONFIG_DIR" ]; then
        # 备份原配置
        sudo cp "$PG_CONFIG_DIR/postgresql.conf" "$PG_CONFIG_DIR/postgresql.conf.backup.$(date +%Y%m%d_%H%M%S)"
        
        # 添加优化配置
        sudo tee -a "$PG_CONFIG_DIR/postgresql.conf" > /dev/null <<EOF

# JAB租赁平台性能优化配置
# 内存配置
shared_buffers = ${SHARED_BUFFERS}MB
effective_cache_size = ${EFFECTIVE_CACHE_SIZE}MB
work_mem = ${WORK_MEM}MB
maintenance_work_mem = ${MAINTENANCE_WORK_MEM}MB

# 连接配置
max_connections = 200

# WAL配置
wal_buffers = 16MB
checkpoint_completion_target = 0.9
wal_compression = on

# 查询优化
random_page_cost = 1.1
effective_io_concurrency = 200

# 日志配置
log_min_duration_statement = 1000
log_checkpoints = on
log_connections = on
log_disconnections = on
log_lock_waits = on

# 自动清理
autovacuum = on
autovacuum_max_workers = 3
autovacuum_naptime = 20s
EOF
        
        # 重启PostgreSQL服务
        sudo systemctl restart postgresql
        
        if sudo systemctl is-active --quiet postgresql; then
            log_success "PostgreSQL性能优化配置完成"
        else
            log_error "PostgreSQL重启失败，恢复备份配置"
            sudo cp "$PG_CONFIG_DIR/postgresql.conf.backup.$(date +%Y%m%d)"* "$PG_CONFIG_DIR/postgresql.conf"
            sudo systemctl restart postgresql
        fi
    else
        log_warning "未找到PostgreSQL配置文件，跳过性能优化"
    fi
}

# 配置Redis
setup_redis() {
    log_info "配置Redis..."
    
    # 检查Redis是否运行
    if ! redis-cli ping | grep -q PONG; then
        log_error "Redis服务未运行，请先运行 setup-traditional.sh"
        exit 1
    fi
    
    # 生成Redis密码
    REDIS_PASSWORD=$(generate_password)
    
    # 查找Redis配置文件
    REDIS_CONFIG="/etc/redis/redis.conf"
    if [ ! -f "$REDIS_CONFIG" ]; then
        REDIS_CONFIG="/etc/redis.conf"
    fi
    
    if [ -f "$REDIS_CONFIG" ]; then
        # 备份原配置
        sudo cp "$REDIS_CONFIG" "$REDIS_CONFIG.backup.$(date +%Y%m%d_%H%M%S)"
        
        # 配置Redis
        sudo sed -i "s/^# requirepass .*/requirepass $REDIS_PASSWORD/" "$REDIS_CONFIG"
        sudo sed -i "s/^requirepass .*/requirepass $REDIS_PASSWORD/" "$REDIS_CONFIG"
        
        # 如果没有requirepass行，添加它
        if ! grep -q "^requirepass" "$REDIS_CONFIG"; then
            echo "requirepass $REDIS_PASSWORD" | sudo tee -a "$REDIS_CONFIG" > /dev/null
        fi
        
        # 其他安全配置
        sudo sed -i 's/^bind 127.0.0.1/bind 127.0.0.1/' "$REDIS_CONFIG"
        sudo sed -i 's/^# maxmemory <bytes>/maxmemory 256mb/' "$REDIS_CONFIG"
        sudo sed -i 's/^# maxmemory-policy noeviction/maxmemory-policy allkeys-lru/' "$REDIS_CONFIG"
        
        # 重启Redis服务
        sudo systemctl restart redis-server || sudo systemctl restart redis
        
        # 测试连接
        if redis-cli -a "$REDIS_PASSWORD" ping | grep -q PONG; then
            log_success "Redis配置完成"
            log_info "Redis密码: $REDIS_PASSWORD"
        else
            log_error "Redis配置失败"
            exit 1
        fi
        
        # 保存Redis连接信息
        cat >> /tmp/db_credentials.txt <<EOF

# Redis连接信息
REDIS_URL="redis://:$REDIS_PASSWORD@localhost:6379"
REDIS_HOST="localhost"
REDIS_PORT="6379"
REDIS_PASSWORD="$REDIS_PASSWORD"
EOF
    else
        log_warning "未找到Redis配置文件，使用默认配置"
        
        # 保存默认Redis连接信息
        cat >> /tmp/db_credentials.txt <<EOF

# Redis连接信息（无密码）
REDIS_URL="redis://localhost:6379"
REDIS_HOST="localhost"
REDIS_PORT="6379"
REDIS_PASSWORD=""
EOF
    fi
}

# 创建环境配置文件
create_env_file() {
    log_info "创建环境配置文件..."
    
    # 读取数据库凭据
    source /tmp/db_credentials.txt
    
    # 生成其他必要的密钥
    NEXTAUTH_SECRET=$(generate_password)
    JWT_SECRET=$(generate_password)
    
    # 创建.env文件
    sudo -u jab tee /var/www/jab/.env > /dev/null <<EOF
# JAB租赁平台环境配置
# 生成时间: $(date)

# 应用配置
NODE_ENV=production
NEXT_PUBLIC_APP_URL=http://localhost:3000
PORT=3000

# 数据库配置
DATABASE_URL="$DATABASE_URL"
DB_HOST="$DB_HOST"
DB_PORT="$DB_PORT"
DB_NAME="$DB_NAME"
DB_USER="$DB_USER"
DB_PASSWORD="$DB_PASSWORD"

# Redis配置
REDIS_URL="$REDIS_URL"
REDIS_HOST="$REDIS_HOST"
REDIS_PORT="$REDIS_PORT"
REDIS_PASSWORD="$REDIS_PASSWORD"

# 认证配置
NEXTAUTH_SECRET="$NEXTAUTH_SECRET"
NEXTAUTH_URL="http://localhost:3000"
JWT_SECRET="$JWT_SECRET"

# 文件上传配置
UPLOAD_DIR="/var/www/jab/uploads"
MAX_FILE_SIZE=10485760

# 邮件配置（需要手动配置）
# SMTP_HOST="smtp.example.com"
# SMTP_PORT="587"
# SMTP_USER="your-email@example.com"
# SMTP_PASS="your-email-password"
# FROM_EMAIL="noreply@example.com"

# 支付配置（需要手动配置）
# STRIPE_PUBLIC_KEY="pk_test_..."
# STRIPE_SECRET_KEY="sk_test_..."
# STRIPE_WEBHOOK_SECRET="whsec_..."

# 其他配置
LOG_LEVEL="info"
SESSION_TIMEOUT=86400
EOF
    
    # 设置文件权限
    sudo chown jab:jab /var/www/jab/.env
    sudo chmod 600 /var/www/jab/.env
    
    log_success "环境配置文件创建完成: /var/www/jab/.env"
}

# 创建数据库备份脚本
create_backup_script() {
    log_info "创建数据库备份脚本..."
    
    # 读取数据库凭据
    source /tmp/db_credentials.txt
    
    cat > backup-database.sh <<EOF
#!/bin/bash
# backup-database.sh - 数据库备份脚本

set -e

# 配置
BACKUP_DIR="/var/backups/jab"
DATE=\$(date +%Y%m%d_%H%M%S)
DB_BACKUP_FILE="\$BACKUP_DIR/jab_rental_\$DATE.sql"
REDIS_BACKUP_FILE="\$BACKUP_DIR/redis_\$DATE.rdb"

# 创建备份目录
sudo mkdir -p \$BACKUP_DIR

echo "🗄️ 开始备份JAB租赁平台数据库..."

# 备份PostgreSQL
echo "📦 备份PostgreSQL数据库..."
export PGPASSWORD="$DB_PASSWORD"
pg_dump -h localhost -U jab_user -d jab_rental > \$DB_BACKUP_FILE

if [ \$? -eq 0 ]; then
    echo "✅ PostgreSQL备份完成: \$DB_BACKUP_FILE"
    # 压缩备份文件
    gzip \$DB_BACKUP_FILE
    echo "📦 备份文件已压缩: \$DB_BACKUP_FILE.gz"
else
    echo "❌ PostgreSQL备份失败"
    exit 1
fi

# 备份Redis（如果有密码）
if [ -n "$REDIS_PASSWORD" ]; then
    echo "📦 备份Redis数据库..."
    redis-cli -a "$REDIS_PASSWORD" --rdb \$REDIS_BACKUP_FILE
else
    echo "📦 备份Redis数据库..."
    redis-cli --rdb \$REDIS_BACKUP_FILE
fi

if [ \$? -eq 0 ]; then
    echo "✅ Redis备份完成: \$REDIS_BACKUP_FILE"
else
    echo "❌ Redis备份失败"
fi

# 清理旧备份（保留7天）
echo "🧹 清理旧备份文件..."
find \$BACKUP_DIR -name "*.sql.gz" -mtime +7 -delete
find \$BACKUP_DIR -name "*.rdb" -mtime +7 -delete

echo "✅ 数据库备份完成"
echo "📁 备份目录: \$BACKUP_DIR"
ls -la \$BACKUP_DIR
EOF
    
    chmod +x backup-database.sh
    
    # 创建定时备份的cron任务
    cat > setup-cron-backup.sh <<'EOF'
#!/bin/bash
# setup-cron-backup.sh - 设置定时备份

echo "⏰ 设置定时数据库备份..."

# 添加cron任务（每天凌晨2点备份）
(crontab -l 2>/dev/null; echo "0 2 * * * /home/$(whoami)/backup-database.sh >> /var/log/jab/backup.log 2>&1") | crontab -

echo "✅ 定时备份设置完成"
echo "📋 当前cron任务:"
crontab -l
EOF
    
    chmod +x setup-cron-backup.sh
    
    log_success "数据库备份脚本创建完成"
}

# 测试数据库连接
test_connections() {
    log_info "测试数据库连接..."
    
    # 读取数据库凭据
    source /tmp/db_credentials.txt
    
    # 测试PostgreSQL连接
    echo "🔍 测试PostgreSQL连接..."
    export PGPASSWORD="$DB_PASSWORD"
    if psql -h localhost -U jab_user -d jab_rental -c "SELECT version();" > /dev/null 2>&1; then
        log_success "PostgreSQL连接测试成功"
    else
        log_error "PostgreSQL连接测试失败"
        return 1
    fi
    
    # 测试Redis连接
    echo "🔍 测试Redis连接..."
    if [ -n "$REDIS_PASSWORD" ]; then
        if redis-cli -a "$REDIS_PASSWORD" ping | grep -q PONG; then
            log_success "Redis连接测试成功"
        else
            log_error "Redis连接测试失败"
            return 1
        fi
    else
        if redis-cli ping | grep -q PONG; then
            log_success "Redis连接测试成功"
        else
            log_error "Redis连接测试失败"
            return 1
        fi
    fi
    
    log_success "所有数据库连接测试通过"
}

# 显示配置总结
show_summary() {
    echo ""
    echo "🎉 JAB租赁平台数据库配置完成！"
    echo "================================================"
    echo ""
    echo "📋 数据库配置信息:"
    echo "   🐘 PostgreSQL:"
    echo "      - 数据库: jab_rental"
    echo "      - 用户: jab_user"
    echo "      - 端口: 5432"
    echo "   🔴 Redis:"
    echo "      - 端口: 6379"
    echo "      - 已配置密码认证"
    echo ""
    echo "📁 重要文件:"
    echo "   📄 环境配置: /var/www/jab/.env"
    echo "   🔐 数据库凭据: /tmp/db_credentials.txt"
    echo "   💾 备份脚本: ./backup-database.sh"
    echo ""
    echo "🔧 下一步操作:"
    echo "   1. 部署应用: ./deploy-app.sh"
    echo "   2. 启动服务: ./manage-service.sh start"
    echo "   3. 设置定时备份: ./setup-cron-backup.sh"
    echo ""
    echo "⚠️  重要提醒:"
    echo "   - 请妥善保管数据库密码"
    echo "   - 建议定期备份数据库"
    echo "   - 生产环境请配置邮件和支付服务"
    echo ""
}

# 主函数
main() {
    echo "🗄️ JAB租赁平台数据库配置脚本"
    echo "================================================"
    echo "⚠️  注意: 此脚本将配置PostgreSQL和Redis数据库"
    echo "⚠️  请确保已运行 setup-traditional.sh"
    echo ""
    read -p "是否继续配置数据库? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "配置已取消"
        exit 0
    fi
    
    echo ""
    echo "🚀 开始配置数据库..."
    echo ""
    
    # 执行配置步骤
    setup_postgresql
    setup_redis
    create_env_file
    create_backup_script
    test_connections
    
    # 显示总结
    show_summary
    
    # 清理临时文件
    rm -f /tmp/db_credentials.txt
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi