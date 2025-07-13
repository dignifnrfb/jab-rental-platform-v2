# JAB租赁平台 - Docker部署方案（优化版）
# 使用官方Node.js 18 Alpine镜像作为基础镜像
FROM node:18-alpine AS base

# 设置工作目录
WORKDIR /app

# 配置Alpine镜像源为国内源（阿里云）加速包安装
RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories && \
    echo "https://mirrors.aliyun.com/alpine/v3.21/main" > /etc/apk/repositories && \
    echo "https://mirrors.aliyun.com/alpine/v3.21/community" >> /etc/apk/repositories

# 配置npm使用国内镜像源
RUN npm config set registry https://registry.npmmirror.com

# 更新包索引并安装系统依赖（合并命令减少层数）
RUN apk update && apk add --no-cache libc6-compat

# 依赖安装阶段
FROM base AS deps

# 复制package文件
COPY package.json package-lock.json* ./

# 清理npm缓存并安装依赖
RUN npm cache clean --force && \
    npm ci --registry=https://registry.npmmirror.com

# 构建阶段
FROM base AS builder

# 复制依赖
COPY --from=deps /app/node_modules ./node_modules

# 复制源代码
COPY . .

# 设置环境变量
ENV NEXT_TELEMETRY_DISABLED=1
ENV NODE_ENV=production

# 生成Prisma客户端（如果存在）
RUN if [ -f "prisma/schema.prisma" ]; then npx prisma generate; fi

# 构建应用
RUN npm run build

# 生产运行阶段
FROM base AS runner

# 设置环境变量
ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
ENV PORT=3000
ENV HOSTNAME="0.0.0.0"

# 创建非root用户
RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 nextjs

# 复制public文件夹
COPY --from=builder /app/public ./public

# 复制Next.js构建输出
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

# 切换到非root用户
USER nextjs

# 暴露端口
EXPOSE 3000

# 健康检查
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node healthcheck.js || exit 1

# 启动应用
CMD ["node", "server.js"]
