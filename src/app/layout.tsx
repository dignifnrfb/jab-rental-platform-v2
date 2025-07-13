import type { Metadata } from 'next';
import { Inter } from 'next/font/google';

import './globals.css';
import { Header } from '@/components/layout/Header';

const inter = Inter({ subsets: ['latin'] });

export const metadata: Metadata = {
  title: '设备租赁平台 - JAB',
  description: '专业键鼠设备租赁平台，提供高品质设备租赁服务',
};

// eslint-disable-next-line react/function-component-definition
export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="zh-CN">
      <body className={inter.className}>
        <Header />
        {children}
      </body>
    </html>
  );
}