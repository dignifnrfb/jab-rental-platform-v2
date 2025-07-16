# Husky错误修复指南

## 问题描述
在部署过程中遇到以下错误：

### Docker环境
```
> modern-rental-platform@0.1.0 prepare
> husky install

sh: 1: husky: not found
npm error code 127
```

### 传统部署环境
```bash
root@server:~/jab-rental-platform-v2# ./deploy-app.sh
🚀 开始部署JAB租赁平台...
📦 安装依赖...
> modern-rental-platform@0.1.0 prepare
> husky install

sh: 1: husky: not found
npm error code 127
```

## 原因分析
1. **npm prepare脚本自动执行**：在运行 `npm ci` 时，package.json中的prepare脚本会自动执行
2. **生产环境缺少husky**：使用 `--only=production` 时，husky作为开发依赖不会被安装
3. **脚本执行冲突**：prepare脚本尝试运行不存在的husky命令

## 解决方案

### Docker环境

#### 方法1：使用自动修复脚本（推荐）
```bash
# 给脚本添加执行权限
chmod +x fix-husky-error.sh

# 运行修复脚本
./fix-husky-error.sh
```

#### 方法2：手动修复
1. **禁用npm脚本执行**：
   ```bash
   npm config set ignore-scripts true
   npm ci --only=production --ignore-scripts
   ```

2. **修改Dockerfile**：
   在npm install命令中添加 `--ignore-scripts` 参数

3. **使用修复后的配置**：
   ```bash
   docker-compose -f docker-compose.ultra-safe.yml up --build
   ```

### 传统部署环境

#### 方法1：预安装husky（推荐）
```bash
# 在运行npm ci之前先安装husky
npm install husky --save-dev
npm install --global husky
npm ci --production
```

#### 方法2：跳过npm脚本
```bash
# 使用--ignore-scripts参数跳过prepare脚本
npm ci --production --ignore-scripts
```

#### 方法3：修改部署脚本
在deploy-app.sh中的依赖安装部分添加husky预安装：
```bash
# 安装依赖（解决husky错误）
echo \"📦 安装依赖...\"
# 先安装husky以避免prepare脚本失败
npm install husky --save-dev
npm ci --production
```

## 修复效果
- ✅ 完全解决husky错误
- ✅ 保持所有安全配置
- ✅ 不影响应用功能
- ✅ 适用于生产环境

## 验证修复
```bash
# 检查构建日志，应该不再出现husky错误
docker-compose logs | grep -i husky

# 验证服务正常运行
docker-compose ps
curl http://localhost:3000/api/health
```

## 预防措施
1. **生产环境配置**：始终使用 `--ignore-scripts` 参数
2. **CI/CD配置**：在自动化部署中禁用npm脚本
3. **环境分离**：开发和生产环境使用不同的npm配置

## 技术细节
- **ignore-scripts配置**：防止npm自动执行package.json中的脚本
- **生产依赖隔离**：确保只安装运行时必需的依赖
- **构建优化**：减少构建时间和潜在错误

---

**注意**：此修复方案专门针对husky错误，如果遇到其他Docker构建问题，请参考 `DOCKER_SEGFAULT_SOLUTIONS.md`。