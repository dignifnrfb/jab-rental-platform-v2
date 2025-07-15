# Docker服务紧急修复指南

> **紧急情况专用指南** - 当Docker服务完全无法启动时的快速诊断和修复方案

## 🚨 紧急情况概述

当您遇到以下情况时，请使用此紧急指南：

- ✗ Docker服务启动失败 (`systemctl start docker` 失败)
- ✗ 无法连接到Docker daemon (`Cannot connect to the Docker daemon`)
- ✗ 所有DNS服务器无法连接
- ✗ Docker网络配置损坏
- ✗ 系统网络配置异常

## 🔍 快速诊断清单

### 1. 检查Docker服务状态
```bash
# 查看Docker服务状态
sudo systemctl status docker.service

# 查看详细错误日志
sudo journalctl -xeu docker.service --since "10 minutes ago"

# 检查Docker socket
ls -la /var/run/docker.sock
```

### 2. 检查系统资源
```bash
# 检查内存使用
free -h

# 检查磁盘空间
df -h /var/lib/docker

# 检查系统负载
uptime
```

### 3. 检查网络连接
```bash
# 测试基本网络连接
ping -c 3 8.8.8.8
ping -c 3 114.114.114.114

# 检查DNS配置
cat /etc/resolv.conf

# 检查网络接口
ip addr show
```

## 🛠️ 自动修复方案

### 方案1: 紧急修复脚本（推荐）

```bash
# 下载并运行紧急修复脚本
wget https://raw.githubusercontent.com/dignifnrfb/jab-rental-platform-v2/main/fix-docker-service-emergency.sh
chmod +x fix-docker-service-emergency.sh
sudo ./fix-docker-service-emergency.sh
```

**脚本功能：**
- 🔍 全面诊断Docker服务和系统状态
- 🔧 自动修复Docker配置文件
- 🌐 修复系统DNS配置
- 🧹 清理损坏的Docker进程和文件
- 🔄 重新安装Docker服务文件
- ✅ 验证修复结果

### 方案2: 增强版修复脚本

```bash
# 如果紧急修复成功，可以运行增强版脚本进行优化
wget https://raw.githubusercontent.com/dignifnrfb/jab-rental-platform-v2/main/fix-docker-runtime-errors.sh
chmod +x fix-docker-runtime-errors.sh
sudo ./fix-docker-runtime-errors.sh
```

## 🔧 手动修复步骤

### 步骤1: 清理Docker进程和配置

```bash
# 停止所有Docker相关服务
sudo systemctl stop docker.socket docker.service containerd.service

# 清理残留进程
sudo pkill -f docker
sudo pkill -f containerd

# 清理Docker socket
sudo rm -f /var/run/docker.sock /var/run/docker.pid
```

### 步骤2: 修复Docker配置文件

```bash
# 备份当前配置
sudo cp /etc/docker/daemon.json /etc/docker/daemon.json.backup.$(date +%Y%m%d-%H%M%S)

# 创建最小化安全配置
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "live-restore": true
}
EOF
```

### 步骤3: 修复系统DNS配置

```bash
# 备份DNS配置
sudo cp /etc/resolv.conf /etc/resolv.conf.backup.$(date +%Y%m%d-%H%M%S)

# 创建基本DNS配置
sudo tee /etc/resolv.conf > /dev/null <<EOF
nameserver 8.8.8.8
nameserver 114.114.114.114
nameserver 223.5.5.5
options timeout:2 attempts:3
EOF
```

### 步骤4: 重新启动Docker服务

```bash
# 重新加载systemd配置
sudo systemctl daemon-reload

# 启动containerd服务
sudo systemctl start containerd.service

# 启动Docker服务
sudo systemctl start docker.service

# 检查服务状态
sudo systemctl status docker.service
```

### 步骤5: 验证修复结果

```bash
# 测试Docker基本功能
docker --version
docker info

# 测试容器运行
docker run --rm hello-world
```

## 🔍 常见问题诊断

### 问题1: DNS解析失败

**症状：** 所有DNS服务器都无法连接

**解决方案：**
```bash
# 检查网络接口状态
ip link show

# 重启网络服务
sudo systemctl restart NetworkManager
# 或者
sudo systemctl restart networking

# 手动配置DNS
sudo echo "nameserver 8.8.8.8" > /etc/resolv.conf
```

### 问题2: Docker daemon启动失败

**症状：** `Job for docker.service failed`

**解决方案：**
```bash
# 查看详细错误
sudo journalctl -xeu docker.service

# 检查配置文件语法
python3 -m json.tool /etc/docker/daemon.json

# 重置配置文件
sudo mv /etc/docker/daemon.json /etc/docker/daemon.json.broken
sudo systemctl start docker.service
```

### 问题3: 权限和Socket问题

**症状：** `permission denied` 或 socket连接失败

**解决方案：**
```bash
# 检查Docker组
sudo groupadd docker
sudo usermod -aG docker $USER

# 重新登录或刷新组权限
newgrp docker

# 检查socket权限
sudo chown root:docker /var/run/docker.sock
sudo chmod 660 /var/run/docker.sock
```

## 📊 故障排除流程图

```
开始
  ↓
检查Docker服务状态
  ↓
服务启动失败？
  ├─ 是 → 检查配置文件 → 修复配置 → 重启服务
  └─ 否 → 检查网络连接
      ↓
    网络异常？
      ├─ 是 → 修复DNS配置 → 重启网络服务
      └─ 否 → 检查Docker功能
          ↓
        功能异常？
          ├─ 是 → 运行紧急修复脚本
          └─ 否 → 问题解决
```

## 🛡️ 预防措施

### 定期维护

```bash
# 每周清理Docker缓存
docker system prune -f

# 每月备份Docker配置
sudo cp /etc/docker/daemon.json /backup/docker-config-$(date +%Y%m%d).json

# 监控磁盘空间
df -h /var/lib/docker
```

### 监控配置

```bash
# 设置Docker服务监控
sudo systemctl enable docker.service
sudo systemctl enable containerd.service

# 检查服务自启动状态
systemctl is-enabled docker.service
```

### 网络配置优化

```bash
# 配置可靠的DNS服务器
echo "nameserver 8.8.8.8" | sudo tee -a /etc/resolv.conf
echo "nameserver 114.114.114.114" | sudo tee -a /etc/resolv.conf

# 配置Docker镜像源
sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "registry-mirrors": [
    "https://registry.cn-hangzhou.aliyuncs.com",
    "https://registry.cn-shanghai.aliyuncs.com"
  ],
  "dns": ["8.8.8.8", "114.114.114.114"]
}
EOF
```

## 📞 获取帮助

### 收集诊断信息

```bash
# 生成完整诊断报告
sudo docker info > docker-diagnostic-$(date +%Y%m%d-%H%M%S).log 2>&1
sudo systemctl status docker.service >> docker-diagnostic-$(date +%Y%m%d-%H%M%S).log
sudo journalctl -xeu docker.service --since "1 hour ago" >> docker-diagnostic-$(date +%Y%m%d-%H%M%S).log
```

### 联系支持

- 📧 技术支持邮箱: support@jab-rental.com
- 📱 紧急热线: +86-400-XXX-XXXX
- 💬 在线支持: https://support.jab-rental.com

### 社区资源

- 🐛 问题反馈: [GitHub Issues](https://github.com/dignifnrfb/jab-rental-platform-v2/issues)
- 📚 文档中心: [JAB租赁平台文档](https://docs.jab-rental.com)
- 💡 最佳实践: [Docker运维指南](https://docs.jab-rental.com/docker-ops)

## 📝 更新日志

### v1.0.0 (2025-01-14)
- ✨ 创建Docker服务紧急修复指南
- 🔧 添加自动修复脚本
- 📋 提供详细的手动修复步骤
- 🔍 包含常见问题诊断方案
- 🛡️ 添加预防措施和监控建议

---

> **重要提醒：** 在生产环境中执行任何修复操作前，请务必备份重要数据和配置文件。如果问题仍然存在，请联系技术支持团队获取专业帮助。