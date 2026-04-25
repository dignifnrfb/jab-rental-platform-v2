# JAB 租赁平台 / JAB Rental Platform

专业键鼠设备租赁系统，基于 Next.js 14、TypeScript、Prisma 和 Tailwind CSS 构建的现代化 Web 应用。

A modern peripherals (keyboard / mouse) rental platform built on Next.js 14, TypeScript, Prisma and Tailwind CSS, with full Docker deployment for Alibaba Cloud ECS.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Next.js](https://img.shields.io/badge/Next.js-14-000000?logo=next.js&logoColor=white)
![TypeScript](https://img.shields.io/badge/TypeScript-5-3178C6?logo=typescript&logoColor=white)
![Prisma](https://img.shields.io/badge/Prisma-2D3748?logo=prisma&logoColor=white)
![Tailwind](https://img.shields.io/badge/Tailwind-38B2AC?logo=tailwind-css&logoColor=white)

> **Security note:** an early version of this repo had `.env` tracked. See [`SECURITY.md`](SECURITY.md) for details and rotation steps.

## 🚀 项目特性

- **现代化技术栈**: Next.js 14 + TypeScript + Tailwind CSS
- **数据库**: PostgreSQL + Prisma ORM
- **状态管理**: Zustand
- **动画效果**: Framer Motion + React Spring
- **UI 组件**: 自定义现代化设计系统
- **PWA 支持**: 渐进式 Web 应用
- **Docker 部署**: 完整的容器化部署方案
- **阿里云优化**: 专为阿里云 ECS 优化的部署脚本

## 🛠️ 技术栈

### 前端
- **框架**: Next.js 14 (App Router)
- **语言**: TypeScript
- **样式**: Tailwind CSS
- **状态管理**: Zustand
- **动画**: Framer Motion, React Spring
- **图标**: Lucide React
- **PWA**: Next-PWA

### 后端
- **数据库**: PostgreSQL
- **ORM**: Prisma
- **缓存**: Redis
- **认证**: NextAuth.js
- **支付**: Stripe

### 部署
- **容器化**: Docker + Docker Compose
- **反向代理**: Nginx
- **云平台**: 阿里云 ECS
- **监控**: Watchtower

## 📁 项目结构

```
jab-rental-platform/
├── src/
│   ├── app/                 # Next.js App Router
│   ├── components/          # React 组件
│   ├── lib/                 # 工具库
│   ├── store/               # 状态管理
│   └── types/               # TypeScript 类型定义
├── prisma/                  # 数据库模式
├── docker/                  # Docker 配置
├── public/                  # 静态资源
└── docs/                    # 项目文档
```

## 🚀 快速开始

### 环境要求
- Node.js 18+
- PostgreSQL 15+
- Redis 7+

### 本地开发

1. **克隆项目**
```bash
git clone https://github.com/dignifnrfb/jab-rental-platform-v2.git
cd jab-rental-platform-v2
```

2. **安装依赖**
```bash
npm install
```

3. **环境配置**
```bash
cp .env.example .env.local
# 编辑 .env.local 配置数据库连接等信息
```

4. **数据库设置**
```bash
npm run db:generate
npm run db:push
npm run db:seed
```

5. **启动开发服务器**
```bash
npm run dev
```

访问 [http://localhost:3000](http://localhost:3000) 查看应用。

### Docker 部署

1. **本地 Docker 部署**
```bash
npm run docker:compose
```

2. **阿里云一键部署**
```bash
npm run deploy:aliyun
```

## 🎨 设计系统

项目采用现代化设计系统，包含：

- **颜色系统**: 基于现代灰度和品牌蓝色
- **字体系统**: Inter 字体家族
- **间距系统**: 基于 4px 网格的间距标准
- **组件库**: 现代化 UI 组件
- **动画系统**: 流畅的交互动画

## 📱 PWA 功能

- 离线访问支持
- 应用安装提示
- 推送通知
- 后台同步

## 🔧 开发指南

### 代码规范
- ESLint + TypeScript 严格模式
- Prettier 代码格式化
- 组件化开发
- TypeScript 类型安全

### 提交规范
```
feat: 新功能
fix: 修复问题
docs: 文档更新
style: 代码格式调整
refactor: 代码重构
test: 测试相关
chore: 构建/工具链更新
```

### 分支管理
- `main`: 主分支，生产环境代码
- `develop`: 开发分支
- `feature/*`: 功能分支
- `hotfix/*`: 热修复分支

## 🚀 部署指南

### 阿里云 ECS 部署

项目提供了专为阿里云 ECS 优化的一键部署脚本：

```bash
chmod +x aliyun-docker-deploy.sh
./aliyun-docker-deploy.sh
```

**推荐配置**:
- CPU: 2核
- 内存: 4GB
- 存储: 40GB SSD
- 带宽: 5Mbps

### 环境变量

详细的环境变量配置请参考 `.env.example` 文件。

主要配置项：
- `DATABASE_URL`: PostgreSQL 连接字符串
- `REDIS_URL`: Redis 连接字符串
- `NEXTAUTH_SECRET`: NextAuth 密钥
- `STRIPE_*`: Stripe 支付配置

## 🤝 贡献指南

1. Fork 项目
2. 创建功能分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 创建 Pull Request

## 📄 许可证

本项目采用 MIT 许可证 - 查看 [LICENSE](LICENSE) 文件了解详情。

## 📞 联系我们

- 项目主页: [GitHub](https://github.com/dignifnrfb/jab-rental-platform-v2)
- 问题反馈: [Issues](https://github.com/dignifnrfb/jab-rental-platform-v2/issues)

---

⭐ 如果这个项目对你有帮助，请给我们一个 Star！