#!/bin/bash
# PostgreSQL数据库设置脚本 - Ubuntu 22.04
# 解决 P1000 认证失败问题

set -e

echo "🔧 开始设置PostgreSQL数据库..."

# 检查PostgreSQL是否已安装
if ! command -v psql &> /dev/null; then
    echo "❌ PostgreSQL未安装，正在安装..."
    sudo apt update
    sudo apt install -y postgresql postgresql-contrib
    echo "✅ PostgreSQL安装完成"
else
    echo "✅ PostgreSQL已安装"
fi

# 启动PostgreSQL服务
echo "🚀 启动PostgreSQL服务..."
sudo systemctl start postgresql
sudo systemctl enable postgresql

# 检查服务状态
if sudo systemctl is-active --quiet postgresql; then
    echo "✅ PostgreSQL服务运行正常"
else
    echo "❌ PostgreSQL服务启动失败"
    sudo systemctl status postgresql
    exit 1
fi

# 数据库配置变量
DB_NAME="jab_rental"
DB_USER="jab_user"
DB_PASSWORD="jab_secure_2024"

echo "📝 创建数据库用户和数据库..."

# 切换到postgres用户并执行SQL命令
sudo -u postgres psql << EOF
-- 删除已存在的用户和数据库（如果存在）
DROP DATABASE IF EXISTS ${DB_NAME};
DROP USER IF EXISTS ${DB_USER};

-- 创建新用户
CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASSWORD}';

-- 创建数据库
CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};

-- 授予权限
GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};

-- 授予创建数据库权限（用于测试）
ALTER USER ${DB_USER} CREATEDB;

-- 显示创建结果
\l
\du
EOF

echo "✅ 数据库用户和数据库创建完成"

# 测试数据库连接
echo "🔍 测试数据库连接..."
if PGPASSWORD=${DB_PASSWORD} psql -h localhost -U ${DB_USER} -d ${DB_NAME} -c "SELECT version();" > /dev/null 2>&1; then
    echo "✅ 数据库连接测试成功"
else
    echo "❌ 数据库连接测试失败"
    echo "请检查以下配置："
    echo "  - 用户名: ${DB_USER}"
    echo "  - 密码: ${DB_PASSWORD}"
    echo "  - 数据库: ${DB_NAME}"
    exit 1
fi

# 配置PostgreSQL允许本地连接
echo "🔧 配置PostgreSQL认证..."
PG_VERSION=$(sudo -u postgres psql -t -c "SELECT version();" | grep -oP '\d+\.\d+' | head -1)
PG_CONFIG_DIR="/etc/postgresql/${PG_VERSION}/main"

if [ -d "$PG_CONFIG_DIR" ]; then
    echo "📝 更新pg_hba.conf配置..."
    
    # 备份原配置文件
    sudo cp "${PG_CONFIG_DIR}/pg_hba.conf" "${PG_CONFIG_DIR}/pg_hba.conf.backup.$(date +%Y%m%d_%H%M%S)"
    
    # 确保本地连接使用md5认证
    sudo sed -i '/^local.*all.*all.*peer/c\local   all             all                                     md5' "${PG_CONFIG_DIR}/pg_hba.conf"
    sudo sed -i '/^host.*all.*all.*127.0.0.1\/32.*ident/c\host    all             all             127.0.0.1/32            md5' "${PG_CONFIG_DIR}/pg_hba.conf"
    
    echo "✅ pg_hba.conf配置更新完成"
    
    # 重启PostgreSQL服务
    echo "🔄 重启PostgreSQL服务..."
    sudo systemctl restart postgresql
    
    # 等待服务启动
    sleep 3
    
    if sudo systemctl is-active --quiet postgresql; then
        echo "✅ PostgreSQL服务重启成功"
    else
        echo "❌ PostgreSQL服务重启失败"
        sudo systemctl status postgresql
        exit 1
    fi
else
    echo "⚠️  未找到PostgreSQL配置目录，跳过pg_hba.conf配置"
fi

# 最终连接测试
echo "🔍 最终连接测试..."
if PGPASSWORD=${DB_PASSWORD} psql -h localhost -U ${DB_USER} -d ${DB_NAME} -c "SELECT 'Database setup successful!' as status;" 2>/dev/null; then
    echo "🎉 数据库设置完全成功！"
    echo ""
    echo "📋 数据库信息："
    echo "  - 主机: localhost"
    echo "  - 端口: 5432"
    echo "  - 数据库: ${DB_NAME}"
    echo "  - 用户: ${DB_USER}"
    echo "  - 密码: ${DB_PASSWORD}"
    echo ""
    echo "🔗 连接字符串："
    echo "  postgresql://${DB_USER}:${DB_PASSWORD}@localhost:5432/${DB_NAME}"
    echo ""
    echo "✅ 现在可以运行 'npx prisma migrate deploy' 了"
else
    echo "❌ 最终连接测试失败"
    echo "请手动检查PostgreSQL配置"
    exit 1
fi

echo "🏁 数据库设置脚本执行完成"
