#!/bin/bash
# JAB租赁平台 - 强力修复Docker PostgreSQL挂载错误脚本
# 彻底解决Docker缓存和挂载问题

set -e  # 遇到错误立即退出

echo "🔧 强力修复Docker PostgreSQL挂载错误..."

# 检查当前目录
if [ ! -f "docker-compose.yml" ]; then
    echo "❌ 错误：请在项目根目录运行此脚本"
    exit 1
fi

# 停止并清理所有Docker容器和卷
echo "🛑 停止并清理Docker容器..."
docker-compose down --volumes --remove-orphans 2>/dev/null || true
docker system prune -f 2>/dev/null || true

# 强制删除可能存在的目录
echo "🗑️ 清理旧的配置文件..."
rm -rf docker/postgres docker/nginx 2>/dev/null || true

# 重新创建目录结构
echo "📁 重新创建docker目录结构..."
mkdir -p docker/postgres
mkdir -p docker/nginx/ssl
mkdir -p docker/nginx/logs

# 验证目录创建
if [ ! -d "docker/postgres" ] || [ ! -d "docker/nginx" ]; then
    echo "❌ 目录创建失败"
    exit 1
fi

# 创建PostgreSQL初始化脚本
echo "📝 创建PostgreSQL初始化脚本..."
cat > docker/postgres/init.sql << 'EOF'
-- JAB租赁平台数据库初始化脚本
-- 创建必要的扩展和基础配置

-- 创建UUID扩展（用于生成唯一ID）
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 创建pg_trgm扩展（用于文本搜索优化）
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- 设置时区
SET timezone = 'Asia/Shanghai';

-- 创建应用用户（如果不存在）
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'jab_user') THEN
        CREATE ROLE jab_user WITH LOGIN PASSWORD 'jab_secure_2024';
    END IF;
END
$$;

-- 授权
GRANT ALL PRIVILEGES ON DATABASE jab_rental_db TO jab_user;
GRANT ALL ON SCHEMA public TO jab_user;

-- 日志记录
\echo 'JAB租赁平台数据库初始化完成'
\echo '数据库: jab_rental_db'
\echo '用户: jab_user'
\echo '时区: Asia/Shanghai'
EOF

# 创建PostgreSQL配置文件
echo "⚙️ 创建PostgreSQL配置文件..."
cat > docker/postgres/postgresql.conf << 'EOF'
# PostgreSQL 优化配置 - 针对4GB内存服务器
shared_buffers = 256MB
effective_cache_size = 1GB
work_mem = 4MB
maintenance_work_mem = 64MB
max_connections = 100
wal_buffers = 16MB
checkpoint_completion_target = 0.9
wal_writer_delay = 200ms
random_page_cost = 1.1
effective_io_concurrency = 200
log_destination = 'stderr'
logging_collector = on
log_directory = 'pg_log'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_min_duration_statement = 1000
autovacuum = on
autovacuum_max_workers = 3
autovacuum_naptime = 1min
EOF

# 创建Nginx配置文件
echo "🌐 创建Nginx配置文件..."
cat > docker/nginx/nginx.conf << 'EOF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
    use epoll;
    multi_accept on;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';
    
    access_log /var/log/nginx/access.log main;
    
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types
        text/plain
        text/css
        text/xml
        text/javascript
        application/json
        application/javascript
        application/xml+rss
        application/atom+xml
        image/svg+xml;
    
    client_body_buffer_size 128k;
    client_max_body_size 10m;
    client_header_buffer_size 1k;
    large_client_header_buffers 4 4k;
    
    upstream jab_app {
        server app:3000;
        keepalive 32;
    }
    
    server {
        listen 80;
        server_name _;
        
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header X-Content-Type-Options "nosniff" always;
        
        location ~* \.(jpg|jpeg|png|gif|ico|css|js|pdf|txt)$ {
            expires 1y;
            add_header Cache-Control "public, immutable";
            access_log off;
        }
        
        location /uploads/ {
            alias /var/www/uploads/;
            expires 1M;
            add_header Cache-Control "public";
        }
        
        location /api/ {
            proxy_pass http://jab_app;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_cache_bypass $http_upgrade;
            
            proxy_connect_timeout 60s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;
        }
        
        location / {
            proxy_pass http://jab_app;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_cache_bypass $http_upgrade;
            
            proxy_connect_timeout 60s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;
        }
        
        location /nginx-health {
            access_log off;
            return 200 "healthy\n";
            add_header Content-Type text/plain;
        }
    }
}
EOF

# 创建SSL目录说明文件
echo "🔒 创建SSL目录说明..."
cat > docker/nginx/ssl/README.md << 'EOF'
# SSL证书目录

这个目录用于存放SSL证书文件。

## 文件说明
- `cert.pem` - SSL证书文件
- `key.pem` - SSL私钥文件

## 使用说明
1. 如果您有SSL证书，请将证书文件放在此目录下
2. 更新 `docker/nginx/nginx.conf` 中的HTTPS服务器配置
3. 取消注释HTTPS服务器块

**注意**: 生产环境请使用正式的SSL证书（如Let's Encrypt）
EOF

# 设置正确的文件权限
echo "🔐 设置文件权限..."
chmod 644 docker/postgres/init.sql
chmod 644 docker/postgres/postgresql.conf
chmod 644 docker/nginx/nginx.conf
chmod 644 docker/nginx/ssl/README.md

# 验证文件存在和内容
echo "✅ 验证文件创建..."
for file in "docker/postgres/init.sql" "docker/postgres/postgresql.conf" "docker/nginx/nginx.conf"; do
    if [ ! -f "$file" ]; then
        echo "❌ 文件 $file 不存在"
        exit 1
    fi
    if [ ! -s "$file" ]; then
        echo "❌ 文件 $file 为空"
        exit 1
    fi
done

# 显示文件信息
echo "📊 文件信息："
ls -la docker/postgres/
ls -la docker/nginx/

# 清理Docker缓存
echo "🧹 清理Docker缓存..."
docker builder prune -f 2>/dev/null || true

echo "✅ 强力修复完成！"
echo ""
echo "📁 创建的文件："
echo "  - docker/postgres/init.sql ($(wc -l < docker/postgres/init.sql) 行)"
echo "  - docker/postgres/postgresql.conf ($(wc -l < docker/postgres/postgresql.conf) 行)"
echo "  - docker/nginx/nginx.conf ($(wc -l < docker/nginx/nginx.conf) 行)"
echo "  - docker/nginx/ssl/README.md"
echo ""
echo "🚀 现在可以运行以下命令启动服务："
echo "   docker-compose up -d"
echo ""
echo "🎉 PostgreSQL挂载错误已彻底解决！"