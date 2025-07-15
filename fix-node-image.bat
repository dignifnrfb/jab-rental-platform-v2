@echo off
REM fix-node-image.bat - Windows版Node镜像拉取问题修复脚本
REM 适用于JAB租赁平台Docker部署

setlocal enabledelayedexpansion

REM 设置颜色代码
set "RED=[91m"
set "GREEN=[92m"
set "YELLOW=[93m"
set "BLUE=[94m"
set "NC=[0m"

echo %BLUE%[INFO]%NC% JAB租赁平台 - Node镜像拉取问题修复脚本
echo ================================================

REM 检查Docker是否安装
echo %BLUE%[INFO]%NC% 检查Docker安装状态...
docker --version >nul 2>&1
if errorlevel 1 (
    echo %RED%[ERROR]%NC% Docker未安装或未添加到PATH，请先安装Docker Desktop
    pause
    exit /b 1
)
echo %GREEN%[SUCCESS]%NC% Docker已安装

REM 检查Docker服务状态
echo %BLUE%[INFO]%NC% 检查Docker服务状态...
docker info >nul 2>&1
if errorlevel 1 (
    echo %RED%[ERROR]%NC% Docker服务未运行，请启动Docker Desktop
    pause
    exit /b 1
)
echo %GREEN%[SUCCESS]%NC% Docker服务正常运行

REM 清理Docker缓存
echo %BLUE%[INFO]%NC% 清理Docker缓存以释放空间...
docker system prune -f >nul 2>&1
echo %GREEN%[SUCCESS]%NC% Docker缓存清理完成

REM 方法1：尝试拉取标准镜像
echo %BLUE%[INFO]%NC% 尝试拉取Node.js镜像...

REM 尝试不同版本的Node.js镜像
set images=node:18-alpine node:lts-alpine node:18 node:18.19.0-alpine

for %%i in (%images%) do (
    echo %BLUE%[INFO]%NC% 尝试拉取: %%i
    timeout /t 300 /nobreak >nul & docker pull %%i >nul 2>&1
    if not errorlevel 1 (
        echo %GREEN%[SUCCESS]%NC% 成功拉取: %%i
        if not "%%i"=="node:18-alpine" (
            docker tag %%i node:18-alpine >nul 2>&1
            echo %GREEN%[SUCCESS]%NC% 已标记 %%i 为 node:18-alpine
        )
        goto :success
    ) else (
        echo %YELLOW%[WARNING]%NC% 拉取失败: %%i
    )
)

REM 方法2：尝试从国内镜像源拉取
echo %BLUE%[INFO]%NC% 尝试从国内镜像源拉取...

set mirrors=registry.cn-hangzhou.aliyuncs.com/library/node:18-alpine ccr.ccs.tencentyun.com/library/node:18-alpine hub-mirror.c.163.com/library/node:18-alpine

for %%m in (%mirrors%) do (
    echo %BLUE%[INFO]%NC% 尝试拉取: %%m
    timeout /t 300 /nobreak >nul & docker pull %%m >nul 2>&1
    if not errorlevel 1 (
        echo %GREEN%[SUCCESS]%NC% 成功拉取: %%m
        docker tag %%m node:18-alpine >nul 2>&1
        echo %GREEN%[SUCCESS]%NC% 已重新标记为 node:18-alpine
        goto :success
    ) else (
        echo %YELLOW%[WARNING]%NC% 拉取失败: %%m
    )
)

REM 如果所有方法都失败，创建替代Dockerfile
echo %RED%[ERROR]%NC% 所有镜像拉取尝试都失败了
echo %BLUE%[INFO]%NC% 创建替代Dockerfile...

(
echo # JAB租赁平台 - 替代镜像版本
echo # 使用更稳定的Node.js镜像
echo.
echo FROM node:lts-alpine AS deps
echo WORKDIR /app
echo.
echo # 安装系统依赖
echo RUN apk add --no-cache libc6-compat python3 make g++ ^&^& rm -rf /var/cache/apk/*
echo.
echo # 配置npm使用国内镜像源
echo RUN npm config set registry https://registry.npmmirror.com
echo.
echo # 复制package文件
echo COPY package*.json ./
echo.
echo # 安装依赖
echo RUN npm ci --only=production
echo.
echo # 构建阶段
echo FROM node:lts-alpine AS builder
echo WORKDIR /app
echo.
echo RUN apk add --no-cache libc6-compat python3 make g++ ^&^& rm -rf /var/cache/apk/*
echo RUN npm config set registry https://registry.npmmirror.com
echo.
echo COPY package*.json ./
echo RUN npm ci
echo.
echo COPY . .
echo RUN npm run build
echo.
echo # 运行时阶段
echo FROM node:lts-alpine AS runner
echo WORKDIR /app
echo.
echo RUN apk add --no-cache dumb-init curl ^&^& rm -rf /var/cache/apk/*
echo RUN addgroup --system --gid 1001 nodejs ^&^& adduser --system --uid 1001 nextjs
echo.
echo ENV NODE_ENV=production
echo ENV NEXT_TELEMETRY_DISABLED=1
echo ENV PORT=3000
echo ENV HOSTNAME="0.0.0.0"
echo.
echo COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
echo COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static
echo COPY --from=builder --chown=nextjs:nodejs /app/public ./public
echo COPY --from=deps --chown=nextjs:nodejs /app/node_modules ./node_modules
echo COPY --from=builder --chown=nextjs:nodejs /app/package.json ./package.json
echo.
echo USER nextjs
echo EXPOSE 3000
echo.
echo HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 CMD curl -f http://localhost:3000/api/health ^|^| exit 1
echo.
echo ENTRYPOINT ["dumb-init", "--"]
echo CMD ["node", "server.js"]
) > Dockerfile.alternative

echo %GREEN%[SUCCESS]%NC% 替代Dockerfile已创建: Dockerfile.alternative
echo %YELLOW%[WARNING]%NC% 请尝试使用以下命令构建:
echo docker build -f Dockerfile.alternative -t jab-app .
goto :end

:success
REM 验证修复结果
echo %BLUE%[INFO]%NC% 验证修复结果...

REM 检查镜像是否存在
docker images | findstr "node.*18-alpine" >nul 2>&1
if not errorlevel 1 (
    echo %GREEN%[SUCCESS]%NC% node:18-alpine镜像已可用
    
    REM 测试容器运行
    docker run --rm node:18-alpine node --version >nul 2>&1
    if not errorlevel 1 (
        echo %GREEN%[SUCCESS]%NC% 容器运行测试通过
        echo.
        echo %GREEN%[SUCCESS]%NC% 🎉 修复完成！现在可以正常构建Docker容器了
        echo.
        echo 📋 下一步操作:
        echo    docker compose -f docker-compose.china.yml up -d --build
        echo.
    ) else (
        echo %YELLOW%[WARNING]%NC% 容器运行测试失败
    )
) else (
    echo %RED%[ERROR]%NC% node:18-alpine镜像仍不可用
)

:end
echo.
echo 🔧 修复脚本执行完成
echo.
echo 💡 如果问题仍然存在，请尝试以下方法:
echo 1. 重启Docker Desktop
echo 2. 检查网络连接和防火墙设置
echo 3. 在Docker Desktop设置中配置镜像加速器
echo 4. 使用VPN或代理服务
echo.
echo 📖 详细解决方案请查看: DOCKER_NODE_IMAGE_SOLUTIONS.md
echo.
pause