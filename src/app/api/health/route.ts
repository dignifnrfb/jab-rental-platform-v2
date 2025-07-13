/**
 * 健康检查API端点
 * 用于Docker容器健康检查和负载均衡器监控
 */

import { NextResponse } from 'next/server';

export async function GET() {
  try {
    // 基础健康检查
    const healthStatus = {
      status: 'healthy',
      timestamp: new Date().toISOString(),
      uptime: process.uptime(),
      environment: process.env.NODE_ENV || 'development',
      version: process.env.npm_package_version || '1.0.0',
    };

    // 可以添加更多检查项
    // - 数据库连接检查
    // - Redis连接检查
    // - 外部服务检查等

    return NextResponse.json(healthStatus, { 
      status: 200,
      headers: {
        'Cache-Control': 'no-cache, no-store, must-revalidate',
        'Pragma': 'no-cache',
        'Expires': '0',
      },
    });
  } catch (error) {
    console.error('Health check failed:', error);
    
    return NextResponse.json(
      { 
        status: 'unhealthy', 
        error: 'Health check failed',
        timestamp: new Date().toISOString(),
      },
      { status: 503 }
    );
  }
}

// 支持HEAD请求（某些负载均衡器使用）
export async function HEAD() {
  try {
    return new NextResponse(null, { 
      status: 200,
      headers: {
        'Cache-Control': 'no-cache, no-store, must-revalidate',
      },
    });
  } catch (error) {
    return new NextResponse(null, { status: 503 });
  }
}