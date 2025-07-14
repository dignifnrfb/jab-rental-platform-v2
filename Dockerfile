# JAB租赁平台 - 优化的多阶段Docker构建
# 基于Node.js 18 Alpine，针对生产环境优化

# 第一阶段：依赖安装
FROM node:18-alpine AS deps
LABEL maintainer="JAB Rental Platform Team"
LABEL description="JAB租赁平台 - 现代化设备租赁管理系统"

# 设置工作目录
WORKDIR /app

# 安装系统依赖
RUN apk add --no-cache \
    libc6-compat \
    python3 \
    make \
    g++ \
    && rm -rf /var/cache/apk/*

# 复制依赖文件
COPY package.json package-lock.json ./

# 配置npm镜像源（国内优化）
RUN npm config set registry https://registry.npmmirror.com

# 安装依赖（仅生产依赖）
RUN npm ci --only=production --no-audit --no-fund && \
    npm cache clean --force

# 第二阶段：构建应用
FROM node:18-alpine AS builder
WORKDIR /app

# 复制依赖文件
COPY package.json package-lock.json ./

# 配置npm镜像源
RUN npm config set registry https://registry.npmmirror.com

# 安装所有依赖（包括开发依赖）
RUN npm ci --no-audit --no-fund

# 复制源代码
COPY . .

# 设置环境变量
ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1

# 构建应用
RUN npm run build

# 第三阶段：运行时镜像
FROM node:18-alpine AS runner
WORKDIR /app

# 创建非root用户
RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 nextjs

# 安装运行时依赖
RUN apk add --no-cache \
    dumb-init \
    curl \
    && rm -rf /var/cache/apk/*

# 设置环境变量
ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
ENV PORT=3000
ENV HOSTNAME="0.0.0.0"

# 复制构建产物
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static
COPY --from=builder --chown=nextjs:nodejs /app/public ./public

# 创建必要的目录
RUN mkdir -p .next/cache && \
    chown -R nextjs:nodejs .next

# 切换到非root用户
USER nextjs

# 暴露端口
EXPOSE 3000

# 健康检查
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:3000/api/health || exit 1

# 启动应用
ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "server.js"]

# 构建信息
ARG BUILD_DATE
ARG VCS_REF
ARG VERSION

LABEL org.label-schema.build-date=$BUILD_DATE \
      org.label-schema.name="JAB Rental Platform" \
      org.label-schema.description="现代化设备租赁管理系统" \
      org.label-schema.url="https://github.com/dignifnrfb/jab-rental-platform-v2" \
      org.label-schema.vcs-ref=$VCS_REF \
      org.label-schema.vcs-url="https://github.com/dignifnrfb/jab-rental-platform-v2" \
      org.label-schema.vendor="JAB Team" \
      org.label-schema.version=$VERSION \
      org.label-schema.schema-version="1.0"
