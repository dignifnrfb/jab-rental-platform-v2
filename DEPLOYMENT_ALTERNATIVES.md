# 🚀 JAB租赁平台部署替代方案

## 📋 概述

本文档提供了JAB租赁平台的多种部署方案，解决Docker镜像拉取问题，并提供传统部署选择。

## 🐳 Docker替代镜像方案

### 方案1：使用稳定的Node.js镜像

#### 1.1 使用Node.js LTS镜像
```dockerfile
# 替换 node:18-alpine 为更稳定的镜像
FROM node:lts AS deps
FROM node:lts AS builder  
FROM node:lts AS runner
```

#### 1.2 使用Debian基础镜像
```dockerfile
# 使用Debian基础的Node.js镜像
FROM node:18-bullseye AS deps
FROM node:18-bullseye AS builder
FROM node:18-bullseye AS runner
```

#### 1.3 使用Ubuntu基础镜像
```dockerfile
# 使用Ubuntu基础镜像手动安装Node.js
FROM ubuntu:22.04 AS deps

# 安装Node.js和npm
RUN apt-get update && apt-get install -y \\
    curl \\
    ca-certificates \\
    gnupg \\
    lsb-release \\
    && curl -fsSL https://deb.nodesource.com/setup_18.x | bash - \\
    && apt-get install -y nodejs \\
    && apt-get clean \\
    && rm -rf /var/lib/apt/lists/*
```

### 方案2：单阶段构建（简化版）

```dockerfile
# 简化的单阶段构建
FROM node:lts

WORKDIR /app

# 安装系统依赖
RUN apt-get update && apt-get install -y \\
    curl \\
    && apt-get clean \\
    && rm -rf /var/lib/apt/lists/*

# 配置npm镜像源
RUN npm config set registry https://registry.npmmirror.com

# 复制并安装依赖
COPY package*.json ./
RUN npm ci

# 复制源代码
COPY . .

# 构建应用
RUN npm run build

# 创建非root用户
RUN useradd --create-home --shell /bin/bash app
USER app

EXPOSE 3000

# 健康检查
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \\
    CMD curl -f http://localhost:3000/api/health || exit 1

CMD [\"npm\", \"start\"]
```

## 🖥️ 传统部署方案（无Docker）

### 方案3：直接服务器部署

#### 3.1 环境要求
- Ubuntu 20.04+ / CentOS 8+ / Debian 11+
- Node.js 18+
- PostgreSQL 13+
- Redis 6+
- Nginx 1.18+
- PM2（进程管理）

#### 3.2 完整部署脚本

```bash
#!/bin/bash
# setup-traditional.sh - 传统部署脚本

set -e

echo \"🚀 开始JAB租赁平台传统部署...\"

# 更新系统
sudo apt update && sudo apt upgrade -y

# 安装基础依赖
sudo apt install -y curl wget gnupg2 software-properties-common apt-transport-https ca-certificates

# 安装Node.js 18
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt install -y nodejs

# 安装PostgreSQL
sudo apt install -y postgresql postgresql-contrib
sudo systemctl start postgresql
sudo systemctl enable postgresql

# 安装Redis
sudo apt install -y redis-server
sudo systemctl start redis-server
sudo systemctl enable redis-server

# 安装Nginx
sudo apt install -y nginx
sudo systemctl start nginx
sudo systemctl enable nginx

# 安装PM2
sudo npm install -g pm2

# 创建应用用户
sudo useradd -m -s /bin/bash jab
sudo usermod -aG sudo jab

# 创建应用目录
sudo mkdir -p /var/www/jab
sudo chown jab:jab /var/www/jab

echo \"✅ 基础环境安装完成\"
echo \"📋 下一步：配置数据库和部署应用\"
```

#### 3.3 数据库配置

```bash
#!/bin/bash
# setup-database.sh - 数据库配置脚本

# 配置PostgreSQL
sudo -u postgres psql <<EOF
CREATE DATABASE jab_rental;
CREATE USER jab_user WITH ENCRYPTED PASSWORD 'your_secure_password';
GRANT ALL PRIVILEGES ON DATABASE jab_rental TO jab_user;
\\q
EOF

# 配置Redis（如需密码）
echo \"requirepass your_redis_password\" | sudo tee -a /etc/redis/redis.conf
sudo systemctl restart redis-server

echo \"✅ 数据库配置完成\"
```

#### 3.4 应用部署

```bash
#!/bin/bash
# deploy-app.sh - 应用部署脚本

APP_DIR=\"/var/www/jab\"
REPO_URL=\"https://github.com/dignifnrfb/jab-rental-platform-v2.git\"

# 切换到应用用户
sudo -u jab bash <<EOF
cd $APP_DIR

# 克隆或更新代码
if [ -d \".git\" ]; then
    git pull origin main
else
    git clone $REPO_URL .
fi

# 安装依赖（解决husky错误）
echo \"📦 安装依赖...\"
# 先安装husky以避免prepare脚本失败
npm install husky --save-dev
npm ci --production

# 构建应用
npm run build

# 生成Prisma客户端
npx prisma generate

# 运行数据库迁移
npx prisma migrate deploy
EOF

echo \"✅ 应用部署完成\"
```

### 方案4：PM2进程管理配置

#### 4.1 PM2配置文件

```json
{
  \"apps\": [
    {
      \"name\": \"jab-rental\",
      \"script\": \"npm\",
      \"args\": \"start\",
      \"cwd\": \"/var/www/jab\",
      \"instances\": \"max\",
      \"exec_mode\": \"cluster\",
      \"env\": {
        \"NODE_ENV\": \"production\",
        \"PORT\": \"3000\",
        \"DATABASE_URL\": \"postgresql://jab_user:your_secure_password@localhost:5432/jab_rental\",
        \"REDIS_URL\": \"redis://localhost:6379\",
        \"NEXTAUTH_SECRET\": \"your_nextauth_secret\",
        \"NEXTAUTH_URL\": \"https://yourdomain.com\"
      },
      \"log_date_format\": \"YYYY-MM-DD HH:mm Z\",
      \"error_file\": \"/var/log/jab/error.log\",
      \"out_file\": \"/var/log/jab/out.log\",
      \"log_file\": \"/var/log/jab/combined.log\",
      \"time\": true,
      \"max_memory_restart\": \"1G\",
      \"node_args\": \"--max_old_space_size=1024\",
      \"restart_delay\": 4000,
      \"max_restarts\": 10,
      \"min_uptime\": \"10s\"
    }
  ]
}
```

#### 4.2 PM2启动脚本

```bash
#!/bin/bash
# start-pm2.sh - PM2启动脚本

# 创建日志目录
sudo mkdir -p /var/log/jab
sudo chown jab:jab /var/log/jab

# 启动应用
sudo -u jab bash <<EOF
cd /var/www/jab
pm2 start ecosystem.config.json
pm2 save
pm2 startup
EOF

echo \"✅ PM2应用启动完成\"
```

### 方案5：Nginx反向代理配置

#### 5.1 Nginx站点配置

```nginx
# /etc/nginx/sites-available/jab-rental
server {
    listen 80;
    server_name yourdomain.com www.yourdomain.com;
    
    # 重定向到HTTPS
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name yourdomain.com www.yourdomain.com;
    
    # SSL配置
    ssl_certificate /etc/ssl/certs/yourdomain.com.crt;
    ssl_certificate_key /etc/ssl/private/yourdomain.com.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    
    # 安全头
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection \"1; mode=block\";
    add_header Strict-Transport-Security \"max-age=31536000; includeSubDomains\" always;
    
    # 日志
    access_log /var/log/nginx/jab-rental.access.log;
    error_log /var/log/nginx/jab-rental.error.log;
    
    # 静态文件缓存
    location /_next/static/ {
        alias /var/www/jab/.next/static/;
        expires 1y;
        add_header Cache-Control \"public, immutable\";
    }
    
    location /public/ {
        alias /var/www/jab/public/;
        expires 1y;
        add_header Cache-Control \"public\";
    }
    
    # API和页面代理
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        
        # 超时设置
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
    
    # 健康检查
    location /health {
        access_log off;
        proxy_pass http://127.0.0.1:3000/api/health;
    }
}
```

#### 5.2 Nginx配置脚本

```bash
#!/bin/bash
# setup-nginx.sh - Nginx配置脚本

# 创建站点配置
sudo cp nginx-jab-rental.conf /etc/nginx/sites-available/jab-rental

# 启用站点
sudo ln -sf /etc/nginx/sites-available/jab-rental /etc/nginx/sites-enabled/

# 删除默认站点
sudo rm -f /etc/nginx/sites-enabled/default

# 测试配置
sudo nginx -t

# 重启Nginx
sudo systemctl restart nginx

echo \"✅ Nginx配置完成\"
```

### 方案6：Systemd服务配置

#### 6.1 Systemd服务文件

```ini
# /etc/systemd/system/jab-rental.service
[Unit]
Description=JAB Rental Platform
After=network.target postgresql.service redis.service
Wants=postgresql.service redis.service

[Service]
Type=forking
User=jab
Group=jab
WorkingDirectory=/var/www/jab
Environment=NODE_ENV=production
Environment=PORT=3000
ExecStart=/usr/bin/pm2 start ecosystem.config.json --no-daemon
ExecReload=/usr/bin/pm2 reload ecosystem.config.json
ExecStop=/usr/bin/pm2 stop ecosystem.config.json
Restart=always
RestartSec=10

# 安全设置
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/www/jab /var/log/jab

[Install]
WantedBy=multi-user.target
```

#### 6.2 服务管理脚本

```bash
#!/bin/bash
# manage-service.sh - 服务管理脚本

case \"$1\" in
    install)
        sudo cp jab-rental.service /etc/systemd/system/
        sudo systemctl daemon-reload
        sudo systemctl enable jab-rental
        echo \"✅ 服务安装完成\"
        ;;
    start)
        sudo systemctl start jab-rental
        echo \"✅ 服务启动完成\"
        ;;
    stop)
        sudo systemctl stop jab-rental
        echo \"✅ 服务停止完成\"
        ;;
    restart)
        sudo systemctl restart jab-rental
        echo \"✅ 服务重启完成\"
        ;;
    status)
        sudo systemctl status jab-rental
        ;;
    logs)
        sudo journalctl -u jab-rental -f
        ;;
    *)
        echo \"用法: $0 {install|start|stop|restart|status|logs}\"
        exit 1
        ;;
esac
```

## 🔄 混合部署方案

### 方案7：数据库Docker + 应用传统部署

#### 7.1 数据库Docker Compose

```yaml
# docker-compose.db-only.yml
version: '3.8'

services:
  postgres:
    image: postgres:15-alpine
    container_name: jab-postgres
    environment:
      POSTGRES_DB: jab_rental
      POSTGRES_USER: jab_user
      POSTGRES_PASSWORD: your_secure_password
    ports:
      - \"5432:5432\"
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./docker/postgres/init.sql:/docker-entrypoint-initdb.d/init.sql
    restart: unless-stopped
    healthcheck:
      test: [\"CMD-SHELL\", \"pg_isready -U jab_user -d jab_rental\"]
      interval: 30s
      timeout: 10s
      retries: 3

  redis:
    image: redis:7-alpine
    container_name: jab-redis
    ports:
      - \"6379:6379\"
    volumes:
      - redis_data:/data
    restart: unless-stopped
    healthcheck:
      test: [\"CMD\", \"redis-cli\", \"ping\"]
      interval: 30s
      timeout: 10s
      retries: 3

volumes:
  postgres_data:
  redis_data:

networks:
  default:
    name: jab-network
```

## 📊 方案对比

| 方案 | 优点 | 缺点 | 适用场景 |
|------|------|------|----------|
| Docker替代镜像 | 环境一致性、易部署 | 仍需Docker环境 | 有Docker但镜像拉取困难 |
| 传统部署 | 无Docker依赖、性能好 | 环境配置复杂 | 传统服务器环境 |
| PM2管理 | 进程监控、自动重启 | 需要手动配置 | 生产环境推荐 |
| Systemd服务 | 系统级管理、开机自启 | Linux限定 | 系统服务化部署 |
| 混合方案 | 灵活性高 | 配置复杂 | 部分容器化需求 |

## 🚀 快速开始

### 选择方案1：Docker替代镜像
```bash
# 使用稳定镜像构建
docker build -f Dockerfile.stable -t jab-app .
docker compose -f docker-compose.stable.yml up -d
```

### 选择方案2：传统部署
```bash
# 运行完整部署脚本
chmod +x setup-traditional.sh
./setup-traditional.sh

# 配置数据库
./setup-database.sh

# 部署应用
./deploy-app.sh

# 启动服务
./start-pm2.sh
```

### 选择方案3：混合部署
```bash
# 启动数据库容器
docker compose -f docker-compose.db-only.yml up -d

# 传统方式部署应用
./deploy-app.sh
./start-pm2.sh
```

## 🔧 故障排除

### 常见问题

1. **Husky错误 (husky: not found)**
   ```bash
   # 问题：npm prepare脚本执行时找不到husky
   # 解决方案1：预安装husky
   npm install husky --save-dev
   npm install --global husky
   
   # 解决方案2：跳过npm脚本
   npm ci --production --ignore-scripts
   
   # 解决方案3：使用修复脚本
   chmod +x fix-husky-error.sh
   ./fix-husky-error.sh
   ```

2. **Node.js版本不兼容**
   ```bash
   # 使用nvm管理Node.js版本
   curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
   nvm install 18
   nvm use 18
   ```

3. **数据库连接失败**
   ```bash
   # 检查PostgreSQL状态
   sudo systemctl status postgresql
   
   # 测试连接
   psql -h localhost -U jab_user -d jab_rental
   ```

4. **端口占用**
   ```bash
   # 查看端口占用
   sudo netstat -tlnp | grep :3000
   
   # 杀死占用进程
   sudo kill -9 <PID>
   ```

5. **权限问题**
   ```bash
   # 修复文件权限
   sudo chown -R jab:jab /var/www/jab
   sudo chmod -R 755 /var/www/jab
   ```

## 📞 技术支持

如需帮助，请：
1. 查看应用日志：`pm2 logs jab-rental`
2. 查看系统日志：`sudo journalctl -u jab-rental`
3. 检查Nginx日志：`sudo tail -f /var/log/nginx/jab-rental.error.log`
4. 验证服务状态：`sudo systemctl status jab-rental`

---

**最后更新**: 2024-12-19
**维护者**: JAB Team