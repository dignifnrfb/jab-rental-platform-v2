'use client';

import { useSpring, animated } from '@react-spring/web';
import { motion } from 'framer-motion';
import {
  Keyboard, Mouse, ShoppingCart, User, Shield, Clock, Star,
} from 'lucide-react';
import Link from 'next/link';
import { useState } from 'react';

const Home = () => {
  const [isHovered, setIsHovered] = useState(false);

  const springProps = useSpring({
    transform: isHovered ? 'scale(1.02)' : 'scale(1)',
    config: { tension: 300, friction: 10 },
  });

  return (
    <main className="min-h-screen bg-gray-50">
      {/* Hero Section */}
      <section className="relative overflow-hidden pt-20">
        <div className="container mx-auto px-4 py-24">
          <motion.div
            initial={{ opacity: 0, y: 30 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.8, ease: [0.25, 0.1, 0.25, 1] }}
            className="text-center max-w-4xl mx-auto"
          >
            <h1 className="text-5xl md:text-6xl font-bold text-gray-900 mb-6">
              专业设备租赁平台
            </h1>
            <p className="text-xl text-gray-600 mb-12 max-w-2xl mx-auto leading-relaxed">
              租赁顶级键盘鼠标设备，体验专业级操作感受，无需购买即可享受高端配置
            </p>
            <div className="flex flex-col sm:flex-row gap-4 justify-center items-center">
              <Link href="/rental">
                <animated.button
                  style={springProps}
                  onMouseEnter={() => setIsHovered(true)}
                  onMouseLeave={() => setIsHovered(false)}
                  className="modern-button text-base px-8 py-4"
                >
                  开始租赁
                </animated.button>
              </Link>
              <Link href="/about">
                <button type="button" className="modern-button-secondary text-base px-8 py-4">
                  了解更多
                </button>
              </Link>
            </div>
          </motion.div>
        </div>
      </section>

      {/* Product Showcase */}
      <section className="py-20 bg-white">
        <div className="container mx-auto px-4">
          <motion.div
            initial={{ opacity: 0, y: 30 }}
            whileInView={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6 }}
            viewport={{ once: true }}
            className="text-center mb-16"
          >
            <h2 className="text-3xl md:text-4xl font-bold text-gray-900 mb-4">
              热门租赁设备
            </h2>
            <p className="text-lg text-gray-600 max-w-2xl mx-auto">
              精选高品质键盘鼠标设备，满足不同使用需求
            </p>
          </motion.div>

          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8">
            {[
              {
                name: 'Wireless Keyboard Pro',
                category: '无线键盘',
                price: '¥280/月',
                icon: <Keyboard className="w-12 h-12 text-blue-600" />,
                features: ['背光键盘', '无线连接', 'Touch ID'],
              },
              {
                name: 'Logitech MX Master 3S',
                category: '无线鼠标',
                price: '¥220/月',
                icon: <Mouse className="w-12 h-12 text-blue-600" />,
                features: ['8000 DPI', '无线充电', '多设备连接'],
              },
              {
                name: 'Razer BlackWidow V4',
                category: '机械键盘',
                price: '¥320/月',
                icon: <Keyboard className="w-12 h-12 text-blue-600" />,
                features: ['机械轴体', 'RGB背光', '宏编程'],
              },
            ].map((product, index) => (
              <motion.div
                key={product.name}
                initial={{ opacity: 0, y: 30 }}
                whileInView={{ opacity: 1, y: 0 }}
                transition={{ duration: 0.6, delay: index * 0.1 }}
                viewport={{ once: true }}
                whileHover={{ y: -8 }}
                className="modern-card group cursor-pointer"
              >
                <div className="aspect-square bg-gray-50 rounded-xl mb-6 flex items-center justify-center">
                  {product.icon}
                </div>
                <h3 className="text-xl font-semibold text-gray-900 mb-2">
                  {product.name}
                </h3>
                <p className="text-gray-600 mb-4">
                  {product.category}
                </p>
                <div className="space-y-2 mb-4">
                  {product.features.map((feature) => (
                    <div key={feature} className="flex items-center text-sm text-gray-600">
                      <div className="w-1.5 h-1.5 bg-blue-500 rounded-full mr-2" />
                      {feature}
                    </div>
                  ))}
                </div>
                <div className="flex items-center justify-between">
                  <span className="text-lg font-medium text-gray-900">{product.price}</span>
                  <Link href="/rental" className="text-blue-500 group-hover:text-blue-600 transition-colors">
                    立即租赁 →
                  </Link>
                </div>
              </motion.div>
            ))}
          </div>
        </div>
      </section>

      {/* Feature Section */}
      <section className="py-20 bg-gray-900 text-white">
        <div className="container mx-auto px-4">
          <div className="text-center mb-16">
            <motion.h2
              initial={{ opacity: 0, y: 30 }}
              whileInView={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.6 }}
              viewport={{ once: true }}
              className="text-3xl md:text-4xl font-bold mb-4"
            >
              为什么选择我们
            </motion.h2>
            <motion.p
              initial={{ opacity: 0, y: 30 }}
              whileInView={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.6, delay: 0.1 }}
              viewport={{ once: true }}
              className="text-lg text-gray-300 max-w-2xl mx-auto"
            >
              专业的设备租赁服务，让您以最优的成本体验顶级设备
            </motion.p>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-8">
            {[
              {
                icon: <Shield className="w-8 h-8" />,
                title: '品质保障',
                description: '所有设备经过严格检测，确保最佳使用体验',
              },
              {
                icon: <Clock className="w-8 h-8" />,
                title: '灵活租期',
                description: '支持按月租赁，灵活调整租期，满足不同需求',
              },
              {
                icon: <Star className="w-8 h-8" />,
                title: '专业服务',
                description: '7x24小时客服支持，专业技术团队保障',
              },
              {
                icon: <ShoppingCart className="w-8 h-8" />,
                title: '便捷租赁',
                description: '在线下单，快速配送，简单便捷的租赁流程',
              },
            ].map((feature, index) => (
              <motion.div
                key={feature.title}
                initial={{ opacity: 0, y: 30 }}
                whileInView={{ opacity: 1, y: 0 }}
                transition={{ duration: 0.6, delay: index * 0.1 }}
                viewport={{ once: true }}
                className="text-center"
              >
                <div className="w-16 h-16 bg-blue-600 rounded-2xl flex items-center justify-center mx-auto mb-4">
                  {feature.icon}
                </div>
                <h3 className="text-xl font-semibold mb-2">{feature.title}</h3>
                <p className="text-gray-300">{feature.description}</p>
              </motion.div>
            ))}
          </div>
        </div>
      </section>

      {/* Quick Access Section */}
      <section className="py-20 bg-white">
        <div className="container mx-auto px-4">
          <motion.div
            initial={{ opacity: 0, y: 30 }}
            whileInView={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6 }}
            viewport={{ once: true }}
            className="text-center mb-16"
          >
            <h2 className="text-3xl md:text-4xl font-bold text-gray-900 mb-4">
              快速访问
            </h2>
            <p className="text-lg text-gray-600 max-w-2xl mx-auto">
              探索我们的各项功能和服务
            </p>
          </motion.div>

          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            {[
              {
                title: '设备租赁',
                description: '浏览和租赁各种键盘鼠标设备',
                href: '/rental',
                icon: <Keyboard className="w-6 h-6" />,
                color: 'bg-blue-500',
              },
              {
                title: '购物车',
                description: '查看已选择的设备和订单',
                href: '/cart',
                icon: <ShoppingCart className="w-6 h-6" />,
                color: 'bg-green-500',
              },
              {
                title: '用户中心',
                description: '管理个人信息和租赁记录',
                href: '/dashboard',
                icon: <User className="w-6 h-6" />,
                color: 'bg-purple-500',
              },
              {
                title: '登录注册',
                description: '登录账户或创建新账户',
                href: '/auth',
                icon: <User className="w-6 h-6" />,
                color: 'bg-orange-500',
              },
              {
                title: '关于我们',
                description: '了解我们的服务和理念',
                href: '/about',
                icon: <Shield className="w-6 h-6" />,
                color: 'bg-indigo-500',
              },
            ].map((item, index) => (
              <motion.div
                key={item.title}
                initial={{ opacity: 0, y: 20 }}
                whileInView={{ opacity: 1, y: 0 }}
                transition={{ duration: 0.5, delay: index * 0.1 }}
                viewport={{ once: true }}
                whileHover={{ y: -4 }}
              >
                <Link href={item.href} className="block">
                  <div className="bg-white rounded-xl shadow-sm border border-gray-100 p-6 hover:shadow-md transition-all duration-300 group">
                    <div className={`w-12 h-12 ${item.color} rounded-lg flex items-center justify-center text-white mb-4 group-hover:scale-110 transition-transform`}>
                      {item.icon}
                    </div>
                    <h3 className="text-lg font-semibold text-gray-900 mb-2">{item.title}</h3>
                    <p className="text-gray-600 text-sm">{item.description}</p>
                  </div>
                </Link>
              </motion.div>
            ))}
          </div>
        </div>
      </section>
    </main>
  );
};

export default Home;