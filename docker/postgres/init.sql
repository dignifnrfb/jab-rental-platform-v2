-- JAB租赁平台数据库初始化脚本
-- 创建必要的扩展和基础配置

-- 创建UUID扩展（用于生成唯一ID）
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 创建pg_trgm扩展（用于文本搜索优化）
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- 设置时区
SET timezone = 'Asia/Shanghai';

-- 创建应用用户（如果不存在）
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'jab_user') THEN
        CREATE ROLE jab_user WITH LOGIN PASSWORD 'jab_secure_2024';
    END IF;
END
$$;

-- 授权
GRANT ALL PRIVILEGES ON DATABASE jab_rental_db TO jab_user;
GRANT ALL ON SCHEMA public TO jab_user;

-- 创建基础表结构（如果使用Prisma，这部分会被覆盖）
-- 这里只是确保数据库可以正常启动

-- 日志记录
\echo 'JAB租赁平台数据库初始化完成'
\echo '数据库: jab_rental_db'
\echo '用户: jab_user'
\echo '时区: Asia/Shanghai'