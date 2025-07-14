#!/bin/bash
# JAB租赁平台 - 修复Docker PostgreSQL挂载错误脚本
# 用于在服务器上创建缺失的配置文件

echo "🔧 修复Docker PostgreSQL挂载错误..."

# 检查当前目录
if [ ! -f "docker-compose.yml" ]; then
    echo "❌ 错误：请在项目根目录运行此脚本"
    exit 1
fi

# 创建docker目录结构
echo "📁 创建docker目录结构..."
mkdir -p docker/postgres
mkdir -p docker/nginx/ssl

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

-- 创建基础表结构（如果使用Prisma，这部分会被覆盖）
-- 这里只是确保数据库可以正常启动

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
# 适用于阿里云ECS等小内存服务器

# 内存配置
shared_buffers = 256MB                    # 共享缓冲区，约为总内存的25%
effective_cache_size = 1GB                # 操作系统缓存大小估计
work_mem = 4MB                           # 单个查询操作的内存
maintenance_work_mem = 64MB              # 维护操作内存

# 连接配置
max_connections = 100                     # 最大连接数
shared_preload_libraries = ''           # 预加载库

# WAL配置
wal_buffers = 16MB                       # WAL缓冲区
checkpoint_completion_target = 0.9       # 检查点完成目标
wal_writer_delay = 200ms                 # WAL写入延迟

# 查询优化
random_page_cost = 1.1                   # SSD优化
effective_io_concurrency = 200          # SSD并发IO

# 日志配置
log_destination = 'stderr'
logging_collector = on
log_directory = 'pg_log'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_min_duration_statement = 1000       # 记录超过1秒的查询

# 自动清理
autovacuum = on
autovacuum_max_workers = 3
autovacuum_naptime = 1min
EOF

# 创建Nginx配置文件
echo "🌐 创建Nginx配置文件..."
cat > docker/nginx/nginx.conf << 'EOF'
# JAB租赁平台 Nginx 配置
# 针对阿里云ECS优化的高性能配置

user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

# 事件配置
events {
    worker_connections 1024;
    use epoll;
    multi_accept on;
}

http {
    # 基础配置
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    # 日志格式
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';
    
    access_log /var/log/nginx/access.log main;
    
    # 性能优化
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    
    # Gzip压缩
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
    
    # 缓冲区配置
    client_body_buffer_size 128k;
    client_max_body_size 10m;
    client_header_buffer_size 1k;
    large_client_header_buffers 4 4k;
    output_buffers 1 32k;
    postpone_output 1460;
    
    # 上游服务器配置
    upstream jab_app {
        server app:3000;
        keepalive 32;
    }
    
    # HTTP服务器配置
    server {
        listen 80;
        server_name _;
        
        # 安全头
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header Referrer-Policy "no-referrer-when-downgrade" always;
        add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline'" always;
        
        # 静态文件缓存
        location ~* \.(jpg|jpeg|png|gif|ico|css|js|pdf|txt)$ {
            expires 1y;
            add_header Cache-Control "public, immutable";
            access_log off;
        }
        
        # 上传文件服务
        location /uploads/ {
            alias /var/www/uploads/;
            expires 1M;
            add_header Cache-Control "public";
        }
        
        # API代理
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
            
            # 超时配置
            proxy_connect_timeout 60s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;
        }
        
        # 主应用代理
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
            
            # 超时配置
            proxy_connect_timeout 60s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;
        }
        
        # 健康检查
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

## 自签名证书生成（仅用于开发环境）

```bash
# 生成自签名证书（仅用于测试）
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout key.pem \
  -out cert.pem \
  -subj "/C=CN/ST=Beijing/L=Beijing/O=JAB/CN=localhost"
```

**注意**: 生产环境请使用正式的SSL证书（如Let's Encrypt）
EOF

# 设置文件权限
echo "🔐 设置文件权限..."
chmod 644 docker/postgres/init.sql
chmod 644 docker/postgres/postgresql.conf
chmod 644 docker/nginx/nginx.conf
chmod 644 docker/nginx/ssl/README.md

# 验证文件创建
echo "✅ 验证文件创建..."
if [ -f "docker/postgres/init.sql" ] && [ -f "docker/postgres/postgresql.conf" ] && [ -f "docker/nginx/nginx.conf" ]; then
    echo "✅ 所有配置文件创建成功！"
    echo ""
    echo "📁 创建的文件："
    echo "  - docker/postgres/init.sql"
    echo "  - docker/postgres/postgresql.conf"
    echo "  - docker/nginx/nginx.conf"
    echo "  - docker/nginx/ssl/README.md"
    echo ""
    echo "🚀 现在可以运行 docker-compose up -d 启动服务"
else
    echo "❌ 文件创建失败，请检查权限"
    exit 1
fi

echo "🎉 修复完成！PostgreSQL挂载错误已解决。"