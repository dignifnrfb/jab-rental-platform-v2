# SSL证书目录

这个目录用于存放SSL证书文件。

## 文件说明

- `cert.pem` - SSL证书文件
- `key.pem` - SSL私钥文件

## 使用说明

1. 如果您有SSL证书，请将证书文件放在此目录下
2. 更新 `docker/nginx/nginx.conf` 中的HTTPS服务器配置
3. 取消注释HTTPS服务器块

## 自签名证书生成（仅用于开发环境）

```bash
# 生成自签名证书（仅用于测试）
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout key.pem \
  -out cert.pem \
  -subj "/C=CN/ST=Beijing/L=Beijing/O=JAB/CN=localhost"
```

**注意**: 生产环境请使用正式的SSL证书（如Let's Encrypt）