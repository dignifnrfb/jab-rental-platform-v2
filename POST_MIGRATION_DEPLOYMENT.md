# 数据迁移后的完整部署步骤

## 概述

数据迁移完成后，JAB租赁平台的部署还需要完成以下关键步骤才能正式上线运行。

## 📋 部署检查清单

### ✅ 已完成
- [x] PostgreSQL 数据库安装和配置
- [x] 数据库用户和权限设置
- [x] 环境变量配置 (.env)
- [x] Prisma 数据库迁移

### 🔄 接下来需要完成

## 1. 安装项目依赖

```bash
# 确保在项目根目录
cd ~/jab-rental-platform-v2

# 安装 Node.js 依赖
npm install

# 或使用 yarn
yarn install
```

## 2. 生成 Prisma 客户端

```bash
# 生成 Prisma 客户端代码
npx prisma generate

# 验证数据库连接
npx prisma db pull
```

## 3. 构建生产版本

```bash
# 构建 Next.js 应用
npm run build

# 检查构建是否成功
ls -la .next/
```

## 4. 配置进程管理器 (PM2)

### 安装 PM2
```bash
# 全局安装 PM2
npm install -g pm2

# 验证安装
pm2 --version
```

### 配置 PM2 生态系统文件
```bash
# 使用项目中的 ecosystem.config.js
# 或创建新的配置文件
cat > ecosystem.config.js << 'EOF'
module.exports = {
  apps: [{
    name: 'jab-rental-platform',
    script: 'npm',
    args: 'start',
    cwd: '/home/ubuntu/jab-rental-platform-v2',
    instances: 1,
    autorestart: true,
    watch: false,
    max_memory_restart: '1G',
    env: {
      NODE_ENV: 'production',
      PORT: 3000
    },
    error_file: '/var/log/jab/error.log',
    out_file: '/var/log/jab/out.log',
    log_file: '/var/log/jab/combined.log',
    time: true
  }]
};
EOF
```

### 启动应用
```bash
# 创建日志目录
sudo mkdir -p /var/log/jab
sudo chown $USER:$USER /var/log/jab

# 启动应用
pm2 start ecosystem.config.js

# 查看应用状态
pm2 status
pm2 logs jab-rental-platform
```

## 5. 配置 Nginx 反向代理

### 安装 Nginx
```bash
sudo apt update
sudo apt install nginx -y
```

### 配置 Nginx
```bash
# 创建站点配置
sudo tee /etc/nginx/sites-available/jab-rental << 'EOF'
server {
    listen 80;
    server_name your-domain.com www.your-domain.com;
    
    # 安全头
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline'" always;
    
    # 静态文件缓存
    location /_next/static {
        alias /home/ubuntu/jab-rental-platform-v2/.next/static;
        expires 365d;
        access_log off;
    }
    
    # 上传文件
    location /uploads {
        alias /var/www/jab/uploads;
        expires 30d;
    }
    
    # 主应用代理
    location / {
        proxy_pass http://localhost:3000;
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
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
}
EOF

# 启用站点
sudo ln -s /etc/nginx/sites-available/jab-rental /etc/nginx/sites-enabled/

# 测试配置
sudo nginx -t

# 重启 Nginx
sudo systemctl restart nginx
sudo systemctl enable nginx
```

## 6. 配置防火墙

```bash
# 配置 UFW 防火墙
sudo ufw allow ssh
sudo ufw allow 'Nginx Full'
sudo ufw --force enable

# 检查状态
sudo ufw status
```

## 7. 设置 SSL 证书 (可选但推荐)

```bash
# 安装 Certbot
sudo apt install certbot python3-certbot-nginx -y

# 获取 SSL 证书
sudo certbot --nginx -d your-domain.com -d www.your-domain.com

# 设置自动续期
sudo crontab -e
# 添加以下行：
# 0 12 * * * /usr/bin/certbot renew --quiet
```

## 8. 配置系统服务 (可选)

```bash
# 创建 systemd 服务文件
sudo tee /etc/systemd/system/jab-rental.service << 'EOF'
[Unit]
Description=JAB Rental Platform
After=network.target

[Service]
Type=forking
User=ubuntu
WorkingDirectory=/home/ubuntu/jab-rental-platform-v2
ExecStart=/usr/bin/pm2 start ecosystem.config.js
ExecReload=/usr/bin/pm2 reload ecosystem.config.js
ExecStop=/usr/bin/pm2 stop ecosystem.config.js
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# 启用服务
sudo systemctl daemon-reload
sudo systemctl enable jab-rental
sudo systemctl start jab-rental
```

## 9. 部署验证

### 基础功能测试
```bash
# 检查应用状态
pm2 status
pm2 logs jab-rental-platform --lines 50

# 检查端口监听
sudo netstat -tlnp | grep :3000

# 测试本地访问
curl -I http://localhost:3000

# 测试 Nginx 代理
curl -I http://localhost
```

### 数据库连接测试
```bash
# 测试数据库连接
node -e "const { PrismaClient } = require('@prisma/client'); const prisma = new PrismaClient(); prisma.\$connect().then(() => console.log('数据库连接成功')).catch(e => console.error('数据库连接失败:', e));"
```

### 功能测试清单
- [ ] 首页加载正常
- [ ] 用户注册/登录功能
- [ ] 商品浏览功能
- [ ] 搜索功能
- [ ] 购物车功能
- [ ] 订单创建功能
- [ ] 支付功能 (如果配置了 Stripe)
- [ ] 管理后台访问
- [ ] 文件上传功能
- [ ] 邮件发送功能 (如果配置了 SMTP)

## 10. 监控和日志

### 设置日志轮转
```bash
# 配置 logrotate
sudo tee /etc/logrotate.d/jab-rental << 'EOF'
/var/log/jab/*.log {
    daily
    missingok
    rotate 52
    compress
    delaycompress
    notifempty
    create 644 ubuntu ubuntu
    postrotate
        pm2 reloadLogs
    endscript
}
EOF
```

### 监控脚本
```bash
# 创建健康检查脚本
cat > ~/health-check.sh << 'EOF'
#!/bin/bash

# 检查应用状态
if ! pm2 describe jab-rental-platform > /dev/null 2>&1; then
    echo "$(date): 应用未运行，尝试重启" >> /var/log/jab/health-check.log
    pm2 restart jab-rental-platform
fi

# 检查数据库连接
if ! pg_isready -h localhost -p 5432 -U jab_user > /dev/null 2>&1; then
    echo "$(date): 数据库连接失败" >> /var/log/jab/health-check.log
fi

# 检查磁盘空间
DISK_USAGE=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
if [ $DISK_USAGE -gt 80 ]; then
    echo "$(date): 磁盘使用率过高: ${DISK_USAGE}%" >> /var/log/jab/health-check.log
fi
EOF

chmod +x ~/health-check.sh

# 添加到 crontab
(crontab -l 2>/dev/null; echo "*/5 * * * * /home/ubuntu/health-check.sh") | crontab -
```

## 11. 备份策略

```bash
# 创建备份脚本
cat > ~/backup.sh << 'EOF'
#!/bin/bash

BACKUP_DIR="/var/backups/jab"
DATE=$(date +%Y%m%d_%H%M%S)

# 创建备份目录
mkdir -p $BACKUP_DIR

# 备份数据库
pg_dump -h localhost -U jab_user jab_rental | gzip > $BACKUP_DIR/database_$DATE.sql.gz

# 备份上传文件
tar -czf $BACKUP_DIR/uploads_$DATE.tar.gz /var/www/jab/uploads/

# 备份应用代码
tar -czf $BACKUP_DIR/app_$DATE.tar.gz /home/ubuntu/jab-rental-platform-v2/ --exclude=node_modules --exclude=.next

# 清理旧备份 (保留7天)
find $BACKUP_DIR -name "*.gz" -mtime +7 -delete

echo "$(date): 备份完成" >> /var/log/jab/backup.log
EOF

chmod +x ~/backup.sh

# 添加到 crontab (每天凌晨2点备份)
(crontab -l 2>/dev/null; echo "0 2 * * * /home/ubuntu/backup.sh") | crontab -
```

## 🎯 部署完成确认

当以下所有项目都完成后，JAB租赁平台就正式部署完成了：

### 必需项目
- [ ] 应用成功构建并启动
- [ ] PM2 进程管理器正常运行
- [ ] Nginx 反向代理配置正确
- [ ] 数据库连接正常
- [ ] 基础功能测试通过
- [ ] 防火墙配置完成

### 推荐项目
- [ ] SSL 证书配置
- [ ] 系统服务配置
- [ ] 监控和日志配置
- [ ] 备份策略实施
- [ ] 性能优化

## 🚀 访问应用

部署完成后，您可以通过以下方式访问应用：

- **本地访问**: http://localhost:3000
- **Nginx 代理**: http://your-server-ip
- **域名访问**: http://your-domain.com (如果配置了域名)
- **HTTPS 访问**: https://your-domain.com (如果配置了 SSL)

## 📞 故障排除

如果遇到问题，请参考：
- `TROUBLESHOOTING_P1000.md` - 数据库认证问题
- `DEPLOYMENT_ALTERNATIVES.md` - 部署方案选择
- `ENV_SETUP_GUIDE.md` - 环境配置指南

或查看日志文件：
```bash
# 应用日志
pm2 logs jab-rental-platform

# Nginx 日志
sudo tail -f /var/log/nginx/error.log

# 系统日志
sudo journalctl -u jab-rental -f
```

---

**恭喜！** 🎉 按照以上步骤完成后，您的 JAB 租赁平台就正式部署完成并可以投入使用了。
