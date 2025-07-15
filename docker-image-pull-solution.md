# Docker镜像拉取失败解决方案

## 问题描述

在执行 `docker compose up -d --build` 时遇到以下错误：

```
failed to solve: node:18-alpine: failed to resolve source metadata for docker.io/library/node:18-alpine: not found
```

这个错误表明Docker无法从Docker Hub拉取 `node:18-alpine` 镜像。

## 问题原因分析

1. **网络连接问题**：无法访问Docker Hub官方镜像仓库
2. **DNS解析问题**：无法正确解析docker.io域名
3. **镜像源配置问题**：未配置国内镜像源，访问速度慢或被阻断
4. **Docker配置问题**：daemon.json配置不当或缺失
5. **防火墙/代理问题**：网络策略阻止了Docker镜像下载

## 解决方案

### 方案一：使用自动修复脚本（推荐）

我已经为您创建了专门的Docker镜像拉取修复脚本，该脚本已上传到GitHub仓库。

#### 1. 下载并运行修复脚本

```bash
# 下载脚本
wget https://raw.githubusercontent.com/dignifnrfb/jab-rental-platform-v2/main/fix-docker-image-pull.sh

# 添加执行权限
chmod +x fix-docker-image-pull.sh

# 运行脚本（需要root权限）
sudo ./fix-docker-image-pull.sh
```

#### 2. 脚本功能说明

该脚本会自动执行以下操作：

- **网络诊断**：测试基本网络连接、DNS解析和Docker Hub连接
- **Docker配置检查**：检查Docker服务状态和当前配置
- **镜像源配置**：自动测试并配置可用的国内镜像源
- **DNS修复**：配置可靠的DNS服务器
- **服务重启**：重启Docker服务使配置生效
- **功能验证**：测试镜像拉取功能
- **缓存清理**：清理可能损坏的Docker缓存

### 方案二：手动配置（备选方案）

如果自动脚本无法解决问题，可以尝试手动配置：

#### 1. 配置Docker镜像源

创建或编辑 `/etc/docker/daemon.json` 文件：

```bash
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json <<EOF
{
    "registry-mirrors": [
        "https://docker.mirrors.ustc.edu.cn",
        "https://hub-mirror.c.163.com",
        "https://mirror.baidubce.com",
        "https://ccr.ccs.tencentyun.com"
    ],
    "dns": ["8.8.8.8", "114.114.114.114"],
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    }
}
EOF
```

#### 2. 重启Docker服务

```bash
sudo systemctl daemon-reload
sudo systemctl restart docker
```

#### 3. 验证配置

```bash
# 检查Docker信息
docker info | grep -A 10 "Registry Mirrors"

# 测试镜像拉取
docker pull hello-world
docker pull node:18-alpine
```

### 方案三：使用替代镜像

如果上述方案都无法解决，可以考虑修改Dockerfile使用替代镜像：

#### 1. 使用阿里云镜像

修改Dockerfile中的基础镜像：

```dockerfile
# 原始配置
FROM node:18-alpine AS runner

# 替换为阿里云镜像
FROM registry.cn-hangzhou.aliyuncs.com/library/node:18-alpine AS runner
```

#### 2. 使用腾讯云镜像

```dockerfile
FROM ccr.ccs.tencentyun.com/library/node:18-alpine AS runner
```

#### 3. 使用华为云镜像

```dockerfile
FROM swr.cn-north-4.myhuaweicloud.com/library/node:18-alpine AS runner
```

## 验证解决方案

### 1. 测试镜像拉取

```bash
# 测试基础镜像
docker pull node:18-alpine

# 测试其他常用镜像
docker pull nginx:alpine
docker pull redis:alpine
```

### 2. 重新构建项目

```bash
# 清理现有构建缓存
docker system prune -a

# 重新构建项目
docker compose up -d --build
```

### 3. 检查容器状态

```bash
# 查看容器状态
docker compose ps

# 查看构建日志
docker compose logs
```

## 常见问题排查

### 1. 网络连接问题

```bash
# 测试网络连接
ping 8.8.8.8
ping docker.io

# 测试DNS解析
nslookup docker.io
nslookup registry-1.docker.io
```

### 2. 防火墙问题

```bash
# 检查防火墙状态
sudo ufw status

# 如果需要，临时关闭防火墙测试
sudo ufw disable
```

### 3. 代理设置问题

如果服务器使用代理，需要配置Docker代理：

```bash
sudo mkdir -p /etc/systemd/system/docker.service.d
sudo tee /etc/systemd/system/docker.service.d/http-proxy.conf <<EOF
[Service]
Environment="HTTP_PROXY=http://proxy.example.com:8080"
Environment="HTTPS_PROXY=http://proxy.example.com:8080"
Environment="NO_PROXY=localhost,127.0.0.1"
EOF

sudo systemctl daemon-reload
sudo systemctl restart docker
```

## 预防措施

### 1. 定期更新镜像源配置

建议定期检查和更新镜像源配置，确保使用可用的镜像源。

### 2. 使用本地镜像缓存

对于频繁使用的镜像，可以考虑搭建本地镜像仓库。

### 3. 监控网络状态

定期检查服务器的网络连接状态和DNS配置。

## 总结

推荐首先使用自动修复脚本 `fix-docker-image-pull.sh`，该脚本会自动诊断问题并应用最佳配置。如果自动脚本无法解决问题，再考虑手动配置或使用替代镜像源。

大多数Docker镜像拉取问题都是由于网络连接或镜像源配置问题引起的，通过正确配置国内镜像源通常可以解决这类问题。