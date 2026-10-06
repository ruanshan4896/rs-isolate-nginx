# rs-isolate-nginx (Tiếng Việt)

**Hệ thống cô lập website đa người dùng thuần bản địa cho aaPanel Nginx & PHP-FPM 8.4**

`rs-isolate-nginx` mang lại sự an toàn bảo mật tuyệt đối cho các website WordPress chạy trên aaPanel (Nginx + PHP-FPM 8.4) bằng cách phân tách danh tính tiến trình và phân quyền thư mục độc lập.

Được phát triển theo triết lý **Ponytail**: Tối giản, tận dụng tối đa tính năng gốc của Linux & Nginx, không code thừa, và **tương thích 100% với các tính năng gốc của aaPanel** (File Manager, WP Toolkit, nâng cấp WordPress, xóa cache, cấp chứng chỉ Let's Encrypt SSL).

---

## Các Tính Năng Nổi Bật

1. **PHP-FPM 8.4 Dedicated Pool riêng biệt**:
   - Mỗi website chạy một pool riêng (`[<domain>]`) dưới danh tính user hệ thống riêng (`iso_<domain>`).
   - Chế độ `pm = ondemand`: Tự động giải phóng RAM khi site không có truy cập (rất tiết kiệm tài nguyên).
   - Khóa thư mục bằng `open_basedir`: Tiến trình PHP không thể đọc ra ngoài docroot của site.

2. **Phân quyền POSIX ACL hai chiều (Bidirectional ACL)**:
   - Thư mục website thuộc sở hữu của `iso_<domain>:iso_<domain>` (quyền `750`).
   - Thiết lập `setfacl` cấp quyền `rwx` cho cả `www` và `iso_<domain>`.
   - **aaPanel WP Toolkit và File Manager hoạt động mượt mà 100%, nâng cấp WordPress và clear cache không bao giờ bị Permission Denied.**
   - Các site khác trên cùng VPS (`iso_siteB`) bị chặn hoàn toàn, không thể xem hay sửa trộm file của nhau.

3. **Chặn mã độc tải lên (Native Uploads Shield)**:
   - Nginx chặn đứng mọi nỗ lực thực thi file `.php` trong thư mục `wp-content/uploads/` bằng mã phản hồi HTTP `403 Forbidden`.

4. **Sentinel Daemon tự động 100% (Zero-Touch)**:
   - Tự động nhận diện khi bạn vừa bấm tạo site mới trên aaPanel.
   - Cơ chế đếm lùi 15 giây (debounce) chờ aaPanel hoàn tất cài đặt WordPress, tạo database và cấp SSL xong mới tiến hành cách ly.
   - Tự động sửa lỗi phân quyền (Self-Healing) nếu bạn lỡ bấm "Fix permissions" trên aaPanel.

---

## Hướng Dẫn Cài Đặt (trên VPS)

```bash
cd /opt
git clone <repo-url> rs-isolate-nginx
cd rs-isolate-nginx
sudo bash install.sh
```

---

## Các Lệnh Quản Trị (CLI)

```bash
# Xem danh sách website và trạng thái cách ly
rs-isolate list

# Cách ly 1 website cụ thể
rs-isolate isolate mysite.com

# Cách ly toàn bộ website hiện có trên máy chủ
rs-isolate isolate-all

# Kiểm tra chi tiết trạng thái cách ly của website
rs-isolate status mysite.com

# Khôi phục website về trạng thái mặc định của aaPanel
rs-isolate restore mysite.com

# Quản lý tiến trình nền Sentinel
rs-isolate sentinel status
rs-isolate sentinel logs
```
