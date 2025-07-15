// ecosystem.config.js - PM2配置文件
// JAB租赁平台生产环境进程管理配置

module.exports = {
  apps: [
    {
      // 应用基本配置
      name: 'jab-rental',
      script: 'npm',
      args: 'start',
      cwd: '/var/www/jab',
      
      // 进程配置
      instances: 'max', // 使用所有CPU核心
      exec_mode: 'cluster', // 集群模式
      
      // 环境配置
      env: {
        NODE_ENV: 'production',
        PORT: 3000
      },
      
      // 日志配置
      log_file: '/var/log/jab/combined.log',
      out_file: '/var/log/jab/out.log',
      error_file: '/var/log/jab/error.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
      merge_logs: true,
      
      // 自动重启配置
      watch: false, // 生产环境不建议开启文件监听
      ignore_watch: [
        'node_modules',
        'logs',
        '*.log',
        '.git',
        '.next'
      ],
      
      // 重启策略
      max_restarts: 10, // 最大重启次数
      min_uptime: '10s', // 最小运行时间
      max_memory_restart: '1G', // 内存超过1G时重启
      
      // 健康检查
      health_check_grace_period: 3000,
      health_check_fatal_exceptions: true,
      
      // 其他配置
      autorestart: true,
      kill_timeout: 5000,
      listen_timeout: 8000,
      
      // 环境变量文件
      env_file: '/var/www/jab/.env'
    }
  ],
  
  // 部署配置
  deploy: {
    production: {
      user: 'jab',
      host: 'localhost',
      ref: 'origin/main',
      repo: 'https://github.com/dignifnrfb/jab-rental-platform-v2.git',
      path: '/var/www/jab',
      'post-deploy': 'npm ci --production && npm run build && npx prisma generate && npx prisma migrate deploy && pm2 reload ecosystem.config.js --env production',
      'pre-setup': 'apt update && apt install git -y'
    }
  }
};