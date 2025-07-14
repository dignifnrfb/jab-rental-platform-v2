// import withPWA from 'next-pwa'

/** @type {import('next').NextConfig} */
const nextConfig = {
  // Docker部署配置
  output: 'standalone',
  
  // 确保正确的路由处理
  trailingSlash: false,
  skipTrailingSlashRedirect: true,
  
  // 性能优化配置
  poweredByHeader: false,
  compress: true,
  
  // 图片优化
  images: {
    domains: ['images.unsplash.com', 'via.placeholder.com'],
    formats: ['image/webp', 'image/avif'],
    minimumCacheTTL: 60,
    dangerouslyAllowSVG: true,
    contentSecurityPolicy: "default-src 'self'; script-src 'none'; sandbox;",
  },
  
  // 编译优化
  compiler: {
    removeConsole: process.env.NODE_ENV === 'production',
    styledComponents: true,
  },
  
  // 实验性功能
  experimental: {
    // 暂时禁用optimizeCss以避免critters依赖问题
    // optimizeCss: true,
    optimizePackageImports: ['framer-motion', 'lucide-react'],
  },
  
  // Webpack优化
  webpack: (config, { dev, isServer }) => {
    // SVG支持
    config.module.rules.push({
      test: /\.svg$/,
      use: ['@svgr/webpack'],
    })
    
    // 修复ESM模块解析问题
    config.resolve.extensionAlias = {
      '.js': ['.js', '.ts', '.tsx'],
      '.mjs': ['.mjs', '.js', '.ts', '.tsx'],
    }
    
    // 确保正确处理node_modules中的ESM模块
    config.resolve.fallback = {
      ...config.resolve.fallback,
    }
    
    // 生产环境优化
    if (!dev && !isServer) {
      config.optimization.splitChunks = {
        chunks: 'all',
        cacheGroups: {
          vendor: {
            test: /[\\/]node_modules[\\/]/,
            name: 'vendors',
            chunks: 'all',
          },
          common: {
            name: 'common',
            minChunks: 2,
            chunks: 'all',
            enforce: true,
          },
        },
      }
    }
    
    return config
  },
  
  // 响应头优化
  async headers() {
    return [
      {
        source: '/(.*)',
        headers: [
          {
            key: 'X-Content-Type-Options',
            value: 'nosniff',
          },
          {
            key: 'X-Frame-Options',
            value: 'DENY',
          },
          {
            key: 'X-XSS-Protection',
            value: '1; mode=block',
          },
        ],
      },
      {
        source: '/static/(.*)',
        headers: [
          {
            key: 'Cache-Control',
            value: 'public, max-age=31536000, immutable',
          },
        ],
      },
    ]
  },
  
  // 确保API路由正确处理
  async rewrites() {
    return [
      {
        source: '/api/:path*',
        destination: '/api/:path*',
      },
    ]
  },
}

// const withPWAConfig = withPWA({
//   dest: 'public',
//   register: true,
//   skipWaiting: true,
//   disable: process.env.NODE_ENV === 'development',
//   buildExcludes: [/middleware-manifest\.json$/],
// })

// export default withPWAConfig(nextConfig)
export default nextConfig
