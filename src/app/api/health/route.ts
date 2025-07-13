import { NextResponse } from 'next/server';

/**
 * 健康检查API端点
 * 用于Docker容器健康检查和服务监控
 */
export async function GET() {
  try {
    // 检查应用基本状态
    const healthStatus = {
      status: 'healthy',
      timestamp: new Date().toISOString(),
      uptime: process.uptime(),
      environment: process.env.NODE_ENV || 'development',
      version: process.env['npm_package_version'] || '1.0.0',
      memory: {
        used: Math.round(process.memoryUsage().heapUsed / 1024 / 1024),
        total: Math.round(process.memoryUsage().heapTotal / 1024 / 1024),
      },
    };

    return NextResponse.json(healthStatus, { status: 200 });
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('健康检查失败:', error);

    return NextResponse.json(
      {
        status: 'unhealthy',
        timestamp: new Date().toISOString(),
        error: error instanceof Error ? error.message : '未知错误',
      },
      { status: 500 },
    );
  }
}

/**
 * 支持HEAD请求用于简单的健康检查
 */
export async function HEAD() {
  try {
    return new NextResponse(null, { status: 200 });
  } catch (error) {
    return new NextResponse(null, { status: 500 });
  }
}
