# Kitsune release

Bản phát hành của Kitsune: image server và hướng dẫn cài đặt.

## Cài server

Cần một máy có Docker. Máy 1 vCPU, 1 GB RAM là đủ cho một team nhỏ.

```sh
git clone https://github.com/bitbytelabio/kitsune-release
cd kitsune-release
cp .env.example .env
# Sửa KITSUNE_DB_PASSWORD trong .env thành mật khẩu của bạn
docker compose up -d
```

Kiểm tra server đã chạy. Kết quả đúng là `{"error":"unauthenticated"}`:

```sh
curl http://127.0.0.1:8901/v1/me
```

Server chỉ mở cổng trên `127.0.0.1:8901`. Muốn dùng từ máy khác, hãy đặt một reverse proxy có TLS phía trước, ví dụ Caddy hoặc Cloudflare Tunnel.

## Tạo tài khoản đầu tiên

Server chưa có ai nên cần tự tạo lời mời đầu tiên:

```sh
docker compose exec server kitsune-server invite --email you@example.com --org "My team"
```

Lệnh in ra một mã mời. Trong app, chọn có lời mời rồi nhập địa chỉ server và mã này.

## Cập nhật

```sh
docker compose pull
docker compose up -d
```

Muốn giữ một phiên bản cố định, đặt `KITSUNE_VERSION=0.5.1` trong `.env`.

## Sao lưu

Dữ liệu nằm trong hai volume `kitsune-db` và `kitsune-bundles`. Hãy sao lưu cả hai cùng lúc.

## App desktop

Chưa có bản tải về. Khi có, file DMG cho macOS Apple Silicon sẽ nằm ở mục [Releases](https://github.com/bitbytelabio/kitsune-release/releases).
