# Ubuntu 24.04 Docker 部署指南

## 问题解决方案

### 原始错误
```
=> ERROR [deps 4/4] RUN npm ci --only=production --registry=https://registry.npmmirror.com
npm error code EJSONPARSE
npm error path /app/package.json
npm error JSON.parse Unexpected token "]" (0x5D) in JSON at position 1940
```

### 修复内容

#### 1. 修复 Dockerfile 配置
- ✅ 移除了错误的 `--only=production` 参数
- ✅ 修复了 npm registry URL 格式
- ✅ 添加了 npm 缓存清理
- ✅ 优化了多阶段构建流程
- ✅ 添加了 Next.js standalone 模式支持

#### 2. 修复 package.json 格式
- ✅ 确保 JSON 语法完全正确
- ✅ 移除了可能的编码问题
- ✅ 验证了所有依赖配置

#### 3. 添加 Next.js 配置
- ✅ 启用 `output: 'standalone'` 模式
- ✅ 优化 Docker 部署支持

#### 4. 添加健康检查
- ✅ 创建 `/api/health` 端点
- ✅ 添加 Docker 健康检查脚本
- ✅ 支持服务监控

## 部署步骤

### 1. 克隆项目
```bash
git clone https://github.com/dignifnrfb/jab-rental-platform-v2.git
cd jab-rental-platform-v2
```

### 2. 配置环境变量
```bash
cp .env.example .env
# 编辑 .env 文件，配置数据库连接等信息
```

### 3. 使用自动化部署脚本
```bash
chmod +x deploy.sh
./deploy.sh
```

### 4. 手动部署（可选）
```bash
# 构建并启动服务
docker-compose build --no-cache
docker-compose up -d

# 检查服务状态
docker-compose ps
docker-compose logs -f
```

## 服务访问

- **应用地址**: http://localhost:3000
- **健康检查**: http://localhost:3000/api/health
- **数据库**: PostgreSQL (端口 5432)
- **缓存**: Redis (端口 6379)

## 常用命令

```bash
# 查看日志
docker-compose logs -f

# 停止服务
docker-compose down

# 重启服务
docker-compose restart

# 查看状态
docker-compose ps

# 进入容器
docker-compose exec app sh

# 清理资源
docker-compose down --volumes --remove-orphans
docker system prune -f
```

## 故障排除

### 1. 构建失败
```bash
# 清理 Docker 缓存
docker builder prune -f
docker-compose build --no-cache
```

### 2. 端口冲突
```bash
# 检查端口占用
netstat -tulpn | grep :3000
# 或修改 docker-compose.yml 中的端口映射
```

### 3. 权限问题
```bash
# 确保脚本有执行权限
chmod +x deploy.sh
# 确保 Docker 用户权限
sudo usermod -aG docker $USER
```

### 4. 内存不足
```bash
# 检查系统资源
free -h
df -h
# 调整 Docker 内存限制
```

## 性能优化

### 1. 生产环境配置
- 启用 Next.js 生产模式
- 配置 Nginx 反向代理
- 启用 Gzip 压缩
- 配置 CDN

### 2. 数据库优化
- 配置 PostgreSQL 连接池
- 启用查询缓存
- 定期备份数据

### 3. 监控配置
- 配置日志收集
- 设置性能监控
- 配置告警通知

## 安全建议

1. **环境变量**: 不要在代码中硬编码敏感信息
2. **网络安全**: 配置防火墙规则
3. **SSL证书**: 生产环境启用 HTTPS
4. **定期更新**: 保持依赖包最新版本
5. **备份策略**: 定期备份数据库和配置

## 技术栈

- **前端**: Next.js 14 + React 18 + TypeScript
- **样式**: Tailwind CSS + Framer Motion
- **状态管理**: Zustand
- **数据库**: PostgreSQL + Prisma ORM
- **缓存**: Redis
- **部署**: Docker + Docker Compose
- **代理**: Nginx

## 联系支持

如果遇到部署问题，请：
1. 检查日志输出
2. 确认环境配置
3. 参考故障排除指南
4. 提交 GitHub Issue