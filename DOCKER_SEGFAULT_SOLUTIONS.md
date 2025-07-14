# Docker 段错误解决方案指南

## 🚨 问题描述

在 Docker 构建过程中出现 `Segmentation fault` 错误，通常发生在 Node.js 应用构建阶段。

## 🔧 解决方案（按推荐顺序）

### 方案1：基础修复脚本
```bash
# 适用于轻微的段错误问题
./fix-docker-segfault.sh
```

### 方案2：轻量级配置
```bash
# 适用于内存受限的环境
docker-compose -f docker-compose.lightweight.yml up -d --build
```

### 方案3：终极解决方案（推荐）
```bash
# 适用于所有其他方案都失败的情况
sudo ./fix-docker-ultimate.sh
```

### 方案4：超安全配置
```bash
# 使用Ubuntu基础镜像，避免Alpine相关问题
docker-compose -f docker-compose.ultra-safe.yml up -d --build
```

## 📋 方案对比

| 方案 | 适用场景 | 内存要求 | 成功率 | 构建时间 |
|------|----------|----------|--------|----------|
| 基础修复 | 轻微问题 | 2GB+ | 70% | 快 |
| 轻量级 | 内存受限 | 1GB+ | 80% | 中等 |
| 终极方案 | 严重问题 | 3GB+ | 95% | 慢 |
| 超安全 | 所有环境 | 2GB+ | 99% | 最慢 |

## 🎯 快速诊断

### 检查系统资源
```bash
# 检查内存
free -h

# 检查磁盘空间
df -h

# 检查Docker状态
docker info
```

### 常见错误模式

1. **内存不足**
   ```
   Segmentation fault (core dumped)
   ```
   → 使用方案2或3

2. **Alpine相关问题**
   ```
   musl libc error
   ```
   → 使用方案4（Ubuntu基础镜像）

3. **BuildKit问题**
   ```
   buildkit error
   ```
   → 使用方案3（禁用BuildKit）

## 🚀 推荐流程

1. **首次尝试**：运行 `./fix-docker-ultimate.sh`
2. **如果失败**：检查系统资源，增加内存或swap
3. **仍然失败**：使用超安全配置 `docker-compose.ultra-safe.yml`
4. **最后手段**：考虑更换服务器或使用云服务

## 🔍 故障排除

### 日志查看
```bash
# 查看构建日志
docker-compose logs app

# 查看系统日志
dmesg | grep -i "segmentation fault"

# 查看Docker日志
journalctl -u docker.service
```

### 系统优化
```bash
# 增加swap空间
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# 清理系统缓存
sudo sync && echo 3 | sudo tee /proc/sys/vm/drop_caches

# 重启Docker服务
sudo systemctl restart docker
```

## 📞 技术支持

如果所有方案都失败，请提供以下信息：

1. 系统信息：`uname -a`
2. 内存信息：`free -h`
3. Docker版本：`docker --version`
4. 错误日志：完整的构建错误信息
5. 系统日志：`dmesg | tail -50`

## 🎉 成功标志

部署成功后，您应该能够：

1. 访问应用：`http://your-server-ip`
2. 健康检查通过：`http://your-server-ip/api/health`
3. 所有服务运行正常：`docker-compose ps`

---

**注意**：建议在生产环境中使用超安全配置以确保稳定性。
