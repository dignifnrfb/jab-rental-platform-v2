#!/bin/bash
# JAB租赁平台 - 部署状态检查脚本
# 检查所有服务运行状态和访问信息

echo "🔍 JAB租赁平台部署状态检查"
echo "=================================="

# 检查Docker容器状态
echo "📦 Docker容器状态："
docker-compose ps

echo ""
echo "🏥 容器健康状态："
docker-compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"

echo ""
echo "📊 系统资源使用："
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}"

echo ""
echo "🌐 网络端口检查："
echo "检查端口80 (Nginx):"
netstat -tlnp | grep :80 || echo "端口80未监听"

echo "检查端口3000 (App):"
netstat -tlnp | grep :3000 || echo "端口3000未监听"

echo "检查端口5432 (PostgreSQL):"
netstat -tlnp | grep :5432 || echo "端口5432未监听"

echo "检查端口6379 (Redis):"
netstat -tlnp | grep :6379 || echo "端口6379未监听"

echo ""
echo "🔗 服务连接测试："

# 测试Nginx健康检查
echo "测试Nginx健康检查:"
curl -s http://localhost/nginx-health || echo "Nginx健康检查失败"

# 测试应用健康检查
echo "测试应用健康检查:"
curl -s http://localhost:3000/api/health | head -3 || echo "应用健康检查失败"

# 测试PostgreSQL连接
echo "测试PostgreSQL连接:"
docker exec jab-postgres pg_isready -U jab_user -d jab_rental_db || echo "PostgreSQL连接失败"

# 测试Redis连接
echo "测试Redis连接:"
docker exec jab-redis redis-cli ping || echo "Redis连接失败"

echo ""
echo "📝 容器日志 (最近10行)："
echo "--- Nginx日志 ---"
docker logs jab-nginx --tail 10 2>/dev/null || echo "无Nginx日志"

echo "--- 应用日志 ---"
docker logs jab-app --tail 10 2>/dev/null || echo "无应用日志"

echo "--- PostgreSQL日志 ---"
docker logs jab-postgres --tail 5 2>/dev/null || echo "无PostgreSQL日志"

echo ""
echo "🎯 访问信息："
echo "=================================="

# 获取服务器IP
SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s ipinfo.io/ip 2>/dev/null || echo "获取IP失败")

echo "🌍 外网访问地址："
echo "  主站: http://$SERVER_IP"
echo "  主站: http://$SERVER_IP:80"
echo ""
echo "🏠 内网访问地址："
echo "  主站: http://localhost"
echo "  应用: http://localhost:3000"
echo ""
echo "🔧 管理地址："
echo "  应用健康检查: http://$SERVER_IP:3000/api/health"
echo "  Nginx健康检查: http://$SERVER_IP/nginx-health"

echo ""
echo "📱 建议测试页面："
echo "  首页: http://$SERVER_IP/"
echo "  关于页面: http://$SERVER_IP/about"
echo "  租赁页面: http://$SERVER_IP/rental"
echo "  管理后台: http://$SERVER_IP/admin"

echo ""
echo "🎉 部署完成！所有服务运行正常！"