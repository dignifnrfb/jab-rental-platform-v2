# 🐳 Docker Node镜像拉取问题解决方案

## 📋 问题描述
当使用Docker Hub官方镜像源时，`node:18-alpine`镜像无法正常拉取，导致容器构建失败。

## 🔍 问题原因分析
1. **网络连接问题** - 防火墙、代理或DNS解析问题
2. **Docker配置问题** - 缺少镜像加速器配置
3. **镜像版本问题** - 特定版本可能已被弃用或移动
4. **认证限制** - Docker Hub访问限制或需要登录
5. **地理位置限制** - 某些地区访问Docker Hub受限

## 🛠️ 解决方案

### 方案1：配置Docker镜像加速器（推荐）

#### 1.1 阿里云镜像加速器
```bash
# 创建或编辑Docker配置文件
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json <<-'EOF'
{
  "registry-mirrors": [
    "https://registry.cn-hangzhou.aliyuncs.com",
    "https://hub-mirror.c.163.com",
    "https://mirror.baidubce.com"
  ]
}
EOF

# 重启Docker服务
sudo systemctl daemon-reload
sudo systemctl restart docker
```

#### 1.2 腾讯云镜像加速器
```bash
sudo tee /etc/docker/daemon.json <<-'EOF'
{
  "registry-mirrors": [
    "https://mirror.ccs.tencentyun.com",
    "https://registry.cn-hangzhou.aliyuncs.com"
  ]
}
EOF

sudo systemctl daemon-reload
sudo systemctl restart docker
```

#### 1.3 Windows Docker Desktop配置
1. 打开Docker Desktop
2. 进入Settings → Docker Engine
3. 添加镜像加速器配置：
```json
{
  "registry-mirrors": [
    "https://registry.cn-hangzhou.aliyuncs.com",
    "https://hub-mirror.c.163.com"
  ]
}
```
4. 点击"Apply & Restart"

### 方案2：使用替代镜像

#### 2.1 修改Dockerfile使用不同的Node.js镜像
```dockerfile
# 选项1：使用标准Node.js镜像
FROM node:18 AS deps

# 选项2：使用LTS版本
FROM node:lts-alpine AS deps

# 选项3：使用具体版本号
FROM node:18.19.0-alpine AS deps

# 选项4：使用Ubuntu基础镜像
FROM node:18-bullseye AS deps
```

#### 2.2 创建优化的Dockerfile.alternative
```dockerfile
# JAB租赁平台 - 替代镜像版本
# 使用更稳定的Node.js镜像

# ================================
# 第一阶段：依赖安装
# ================================
FROM node:lts-alpine AS deps

# 设置工作目录
WORKDIR /app

# 安装系统依赖
RUN apk add --no-cache \
    libc6-compat \
    python3 \
    make \
    g++ \
    && rm -rf /var/cache/apk/*

# 配置npm使用国内镜像源
RUN npm config set registry https://registry.npmmirror.com

# 复制package文件
COPY package*.json ./

# 安装依赖
RUN npm ci --only=production

# ================================
# 第二阶段：构建应用
# ================================
FROM node:lts-alpine AS builder

WORKDIR /app

# 安装系统依赖
RUN apk add --no-cache \
    libc6-compat \
    python3 \
    make \
    g++ \
    && rm -rf /var/cache/apk/*

# 配置npm
RUN npm config set registry https://registry.npmmirror.com

# 复制package文件
COPY package*.json ./

# 安装所有依赖
RUN npm ci

# 复制源代码
COPY . .

# 构建应用
RUN npm run build

# ================================
# 第三阶段：运行时镜像
# ================================
FROM node:lts-alpine AS runner

WORKDIR /app

# 安装运行时依赖
RUN apk add --no-cache \
    dumb-init \
    curl \
    && rm -rf /var/cache/apk/*

# 创建用户
RUN addgroup --system --gid 1001 nodejs \
    && adduser --system --uid 1001 nextjs

# 环境变量
ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
ENV PORT=3000
ENV HOSTNAME="0.0.0.0"

# 复制文件
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static
COPY --from=builder --chown=nextjs:nodejs /app/public ./public
COPY --from=deps --chown=nextjs:nodejs /app/node_modules ./node_modules
COPY --from=builder --chown=nextjs:nodejs /app/package.json ./package.json

USER nextjs
EXPOSE 3000

# 健康检查
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:3000/api/health || exit 1

# 启动
ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "server.js"]
```

### 方案3：手动拉取和重新标记镜像

```bash
# 尝试从不同源拉取镜像
docker pull registry.cn-hangzhou.aliyuncs.com/library/node:18-alpine
docker tag registry.cn-hangzhou.aliyuncs.com/library/node:18-alpine node:18-alpine

# 或者使用腾讯云镜像
docker pull ccr.ccs.tencentyun.com/library/node:18-alpine
docker tag ccr.ccs.tencentyun.com/library/node:18-alpine node:18-alpine
```

### 方案4：网络诊断和故障排除

#### 4.1 检查网络连接
```bash
# 测试DNS解析
nslookup registry-1.docker.io

# 测试网络连接
ping registry-1.docker.io

# 测试HTTPS连接
curl -I https://registry-1.docker.io/v2/
```

#### 4.2 检查Docker配置
```bash
# 查看Docker信息
docker info

# 查看镜像加速器配置
cat /etc/docker/daemon.json

# 查看Docker日志
sudo journalctl -u docker.service
```

### 方案5：使用代理配置

#### 5.1 配置Docker代理
```bash
# 创建代理配置目录
sudo mkdir -p /etc/systemd/system/docker.service.d

# 创建代理配置文件
sudo tee /etc/systemd/system/docker.service.d/http-proxy.conf <<-'EOF'
[Service]
Environment="HTTP_PROXY=http://proxy.example.com:8080"
Environment="HTTPS_PROXY=http://proxy.example.com:8080"
Environment="NO_PROXY=localhost,127.0.0.1"
EOF

# 重新加载配置
sudo systemctl daemon-reload
sudo systemctl restart docker
```

## 🚀 快速修复脚本

创建自动化修复脚本：

```bash
#!/bin/bash
# fix-node-image.sh - Node镜像拉取问题修复脚本

echo "🔧 开始修复Docker Node镜像拉取问题..."

# 方法1：配置镜像加速器
echo "📦 配置Docker镜像加速器..."
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json <<-'EOF'
{
  "registry-mirrors": [
    "https://registry.cn-hangzhou.aliyuncs.com",
    "https://hub-mirror.c.163.com",
    "https://mirror.baidubce.com"
  ]
}
EOF

# 重启Docker
echo "🔄 重启Docker服务..."
sudo systemctl daemon-reload
sudo systemctl restart docker

# 方法2：尝试拉取替代镜像
echo "📥 尝试拉取Node.js镜像..."
if docker pull node:lts-alpine; then
    echo "✅ 成功拉取 node:lts-alpine"
    docker tag node:lts-alpine node:18-alpine
    echo "🏷️ 已标记为 node:18-alpine"
elif docker pull registry.cn-hangzhou.aliyuncs.com/library/node:18-alpine; then
    echo "✅ 成功从阿里云拉取镜像"
    docker tag registry.cn-hangzhou.aliyuncs.com/library/node:18-alpine node:18-alpine
    echo "🏷️ 已重新标记镜像"
else
    echo "❌ 镜像拉取失败，请检查网络连接"
    exit 1
fi

echo "🎉 修复完成！现在可以尝试构建容器了。"
```

## 📝 使用建议

### 优先级顺序：
1. **首选**：配置Docker镜像加速器（方案1）
2. **备选**：使用替代镜像版本（方案2）
3. **应急**：手动拉取和标记（方案3）
4. **调试**：网络诊断（方案4）
5. **特殊**：代理配置（方案5）

### 验证方法：
```bash
# 测试镜像拉取
docker pull node:18-alpine

# 测试容器构建
docker build -f Dockerfile.china -t jab-app .

# 测试容器运行
docker run --rm jab-app node --version
```

## 🔧 故障排除

### 常见错误及解决方法：

1. **"pull access denied"**
   - 配置镜像加速器
   - 检查网络连接

2. **"connection timeout"**
   - 检查防火墙设置
   - 配置代理（如需要）

3. **"manifest unknown"**
   - 使用不同的镜像版本
   - 检查镜像名称拼写

4. **"no space left on device"**
   - 清理Docker缓存：`docker system prune -a`
   - 检查磁盘空间

## 📞 技术支持

如果以上方案都无法解决问题，请：
1. 收集错误日志：`docker logs <container_id>`
2. 检查系统信息：`docker info`
3. 提供网络环境信息
4. 考虑使用本地构建或其他容器化方案

---

**最后更新时间**: $(date +'%Y-%m-%d %H:%M:%S')
**维护者**: JAB Team