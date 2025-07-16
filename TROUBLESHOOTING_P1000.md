# P1000 认证失败故障排除指南

## 问题描述
当执行 `npx prisma migrate deploy` 时出现以下错误：
```
Error: P1000: Authentication failed against database server at `localhost`, the provided database credentials for `jab_user` are not valid.
```

## 解决步骤

### 1. 检查PostgreSQL服务状态
```bash
# 检查PostgreSQL是否运行
sudo systemctl status postgresql

# 如果未运行，启动服务
sudo systemctl start postgresql
sudo systemctl enable postgresql
```

### 2. 验证数据库用户和数据库是否存在
```bash
# 切换到postgres用户
sudo -u postgres psql

# 在PostgreSQL命令行中执行：
\l                          # 列出所有数据库
\du                         # 列出所有用户

# 检查是否存在jab_user和jab_rental数据库
# 如果不存在，退出psql（\q）并运行setup脚本
```

### 3. 运行数据库设置脚本
```bash
# 给脚本执行权限
chmod +x setup-database-ubuntu.sh

# 运行脚本
sudo ./setup-database-ubuntu.sh
```

### 4. 手动创建数据库用户和数据库（如果脚本失败）
```bash
# 切换到postgres用户
sudo -u postgres psql

# 创建用户
CREATE USER jab_user WITH PASSWORD 'jab_secure_2024';

# 创建数据库
CREATE DATABASE jab_rental OWNER jab_user;

# 授予权限
GRANT ALL PRIVILEGES ON DATABASE jab_rental TO jab_user;
ALTER USER jab_user CREATEDB;

# 退出
\q
```

### 5. 配置PostgreSQL认证
```bash
# 找到pg_hba.conf文件位置
sudo -u postgres psql -c "SHOW hba_file;"

# 编辑pg_hba.conf文件（通常在/etc/postgresql/14/main/pg_hba.conf）
sudo nano /etc/postgresql/14/main/pg_hba.conf

# 确保包含以下行（在文件末尾添加）：
local   all             jab_user                                md5
host    all             jab_user        127.0.0.1/32            md5
host    all             jab_user        ::1/128                 md5
```

### 6. 重启PostgreSQL服务
```bash
sudo systemctl restart postgresql
```

### 7. 测试数据库连接
```bash
# 使用psql测试连接
psql -h localhost -U jab_user -d jab_rental
# 输入密码：jab_secure_2024

# 如果连接成功，退出
\q
```

### 8. 验证.env文件配置
```bash
# 检查.env文件中的DATABASE_URL
grep "DATABASE_URL" .env

# 应该显示：
# DATABASE_URL="postgresql://jab_user:jab_secure_2024@localhost:5432/jab_rental"
```

### 9. 重新运行Prisma迁移
```bash
# 清除Prisma缓存
npx prisma generate

# 运行迁移
npx prisma migrate deploy
```

## 常见问题和解决方案

### 问题1：PostgreSQL版本不匹配
```bash
# 检查PostgreSQL版本
psql --version
sudo -u postgres psql -c "SELECT version();"

# 如果版本路径不同，调整pg_hba.conf路径
# PostgreSQL 12: /etc/postgresql/12/main/pg_hba.conf
# PostgreSQL 13: /etc/postgresql/13/main/pg_hba.conf
# PostgreSQL 14: /etc/postgresql/14/main/pg_hba.conf
# PostgreSQL 15: /etc/postgresql/15/main/pg_hba.conf
```

### 问题2：端口被占用
```bash
# 检查5432端口是否被占用
sudo netstat -tlnp | grep 5432

# 如果端口被占用，可以更改PostgreSQL端口
sudo nano /etc/postgresql/14/main/postgresql.conf
# 修改：port = 5433
# 然后更新.env文件中的端口号
```

### 问题3：权限问题
```bash
# 确保当前用户有权限访问项目目录
sudo chown -R $USER:$USER ~/jab-rental-platform-v2
chmod -R 755 ~/jab-rental-platform-v2
```

### 问题4：防火墙阻止连接
```bash
# 检查防火墙状态
sudo ufw status

# 如果防火墙开启，允许PostgreSQL端口
sudo ufw allow 5432
```

## 验证步骤

### 完整验证流程
```bash
# 1. 检查服务状态
sudo systemctl status postgresql

# 2. 测试数据库连接
psql -h localhost -U jab_user -d jab_rental -c "SELECT 1;"

# 3. 验证环境变量
node -e "console.log(process.env.DATABASE_URL)"

# 4. 测试Prisma连接
npx prisma db pull

# 5. 运行迁移
npx prisma migrate deploy
```

## 日志检查

### PostgreSQL日志
```bash
# 查看PostgreSQL日志
sudo tail -f /var/log/postgresql/postgresql-14-main.log

# 或者
sudo journalctl -u postgresql -f
```

### 应用日志
```bash
# 查看应用启动日志
npm run build 2>&1 | tee build.log
npx prisma migrate deploy 2>&1 | tee migrate.log
```

## 联系支持

如果以上步骤都无法解决问题，请提供以下信息：

1. Ubuntu版本：`lsb_release -a`
2. PostgreSQL版本：`psql --version`
3. Node.js版本：`node --version`
4. 错误日志：完整的错误信息
5. 配置文件：.env文件内容（隐藏敏感信息）
6. 数据库状态：`sudo systemctl status postgresql`

---

**注意**：确保在生产环境中使用强密码，并定期更新数据库凭据。
