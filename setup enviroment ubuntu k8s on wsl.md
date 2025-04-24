# Thiết lập Kubernetes trên Windows Subsystem for Linux (WSL)

Tài liệu này hướng dẫn cách thiết lập môi trường Kubernetes sử dụng Windows Subsystem for Linux (WSL) trên Windows.

<style>
.copy-button {
  position: absolute;
  right: 0;
  top: 0;
  padding: 5px 10px;
  background-color: #007bff;
  color: white;
  border: none;
  border-radius: 3px;
  cursor: pointer;
  font-size: 12px;
}
.copy-button:hover {
  background-color: #0056b3;
}
.code-container {
  position: relative;
  margin-bottom: 1em;
}
</style>

<script>
function copyToClipboard(id) {
  var codeBlock = document.getElementById(id);
  var text = codeBlock.textContent;
  navigator.clipboard.writeText(text)
    .then(() => {
      var button = document.querySelector(`button[data-target="${id}"]`);
      button.textContent = 'Đã copy!';
      setTimeout(() => {
        button.textContent = 'Copy';
      }, 2000);
    })
    .catch(err => {
      console.error('Không thể copy: ', err);
    });
}
</script>

## Yêu cầu

- Windows 10 hoặc Windows 11 với WSL 2 đã được cài đặt
- File image Ubuntu 24.04 server cloud (ubuntu-24.04-server-cloudimg-amd64-root.tar.xz)
- Đủ không gian đĩa (khuyến nghị ít nhất 50GB)

## 1. Tạo các máy ảo WSL cho Kubernetes

### 1.1. Tạo thư mục cho các máy ảo WSL

<div class="code-container">
<button class="copy-button" data-target="code1" onclick="copyToClipboard('code1')">Copy</button>

```powershell
# Tạo thư mục để lưu trữ các máy ảo WSL
mkdir D:\WSL\k8s-master1
mkdir D:\WSL\k8s-worker1
mkdir D:\WSL\k8s-worker2
```
<pre id="code1" style="display: none">
mkdir D:\WSL\k8s-master1
mkdir D:\WSL\k8s-worker1
mkdir D:\WSL\k8s-worker2
</pre>
</div>

### 1.2. Import các máy ảo Ubuntu 24.04 vào WSL

<div class="code-container">
<button class="copy-button" data-target="code2" onclick="copyToClipboard('code2')">Copy</button>

```powershell
# Import máy ảo master node
wsl --import k8s-master1 D:\WSL\k8s-master1 D:\WSL\ubuntu-24.04-server-cloudimg-amd64-root.tar.xz --version 2

# Import máy ảo worker node 1
wsl --import k8s-worker1 D:\WSL\k8s-worker1 D:\WSL\ubuntu-24.04-server-cloudimg-amd64-root.tar.xz --version 2

# Import máy ảo worker node 2
wsl --import k8s-worker2 D:\WSL\k8s-worker2 D:\WSL\ubuntu-24.04-server-cloudimg-amd64-root.tar.xz --version 2
```
<pre id="code2" style="display: none">
wsl --import k8s-master1 D:\WSL\k8s-master1 D:\WSL\ubuntu-24.04-server-cloudimg-amd64-root.tar.xz --version 2
wsl --import k8s-worker1 D:\WSL\k8s-worker1 D:\WSL\ubuntu-24.04-server-cloudimg-amd64-root.tar.xz --version 2
wsl --import k8s-worker2 D:\WSL\k8s-worker2 D:\WSL\ubuntu-24.04-server-cloudimg-amd64-root.tar.xz --version 2
</pre>
</div>

## 2. Cấu hình các máy ảo WSL

### 2.1. Tạo script cấu hình systemd và hostname

Đầu tiên, tạo một script cấu hình hostname có thể tái sử dụng cho tất cả các node. Script này sẽ:
- Cấu hình systemd trong WSL
- Đặt hostname cho node
- Cấu hình file hosts để các node có thể giao tiếp với nhau

<div class="code-container">
<button class="copy-button" data-target="code3" onclick="copyToClipboard('code3')">Copy</button>

```powershell
# Khởi động máy master để tạo script
wsl -d k8s-master1
```
<pre id="code3" style="display: none">
wsl -d k8s-master1
</pre>
</div>

Tạo file `setup_hostname.sh` với nội dung sau:

<div class="code-container">
<button class="copy-button" data-target="code4" onclick="copyToClipboard('code4')">Copy</button>

```bash
#!/bin/bash

# Check if hostname parameter is provided
if [ -z "$1" ]; then
    echo "Error: Hostname parameter is required"
    echo "Usage: $0 <hostname>"
    echo "Example: $0 k8s-master1"
    exit 1
fi

HOSTNAME=$1

# Tạo file wsl.conf để cấu hình systemd và hostname
cat > /etc/wsl.conf << EOF
[boot]
systemd=true
[network]
hostname=$HOSTNAME
generateHosts=false
EOF

# Cập nhật hostname ngay lập tức
hostname $HOSTNAME
echo "$HOSTNAME" > /etc/hostname

# Cập nhật file hosts
cat > /etc/hosts << EOF
127.0.0.1 localhost
127.0.1.1 $HOSTNAME

# Các node trong cluster Kubernetes
192.168.0.10 k8s-master1
192.168.0.11 k8s-worker1
192.168.0.12 k8s-worker2
EOF

echo "Cấu hình hostname '$HOSTNAME' đã hoàn tất. Vui lòng khởi động lại WSL để áp dụng thay đổi."
echo "Sử dụng lệnh sau trong PowerShell để khởi động lại WSL:"
echo "wsl --terminate $HOSTNAME"
```
<pre id="code4" style="display: none">
#!/bin/bash

# Check if hostname parameter is provided
if [ -z "$1" ]; then
    echo "Error: Hostname parameter is required"
    echo "Usage: $0 <hostname>"
    echo "Example: $0 k8s-master1"
    exit 1
fi

HOSTNAME=$1

# Tạo file wsl.conf để cấu hình systemd và hostname
cat > /etc/wsl.conf << EOF
[boot]
systemd=true
[network]
hostname=$HOSTNAME
generateHosts=false
EOF

# Cập nhật hostname ngay lập tức
hostname $HOSTNAME
echo "$HOSTNAME" > /etc/hostname

# Cập nhật file hosts
cat > /etc/hosts << EOF
127.0.0.1 localhost
127.0.1.1 $HOSTNAME

# Các node trong cluster Kubernetes
192.168.0.10 k8s-master1
192.168.0.11 k8s-worker1
192.168.0.12 k8s-worker2
EOF

echo "Cấu hình hostname '$HOSTNAME' đã hoàn tất. Vui lòng khởi động lại WSL để áp dụng thay đổi."
echo "Sử dụng lệnh sau trong PowerShell để khởi động lại WSL:"
echo "wsl --terminate $HOSTNAME"
</pre>
</div>

Cấp quyền thực thi cho script:

<div class="code-container">
<button class="copy-button" data-target="code5" onclick="copyToClipboard('code5')">Copy</button>

```bash
chmod +x setup_hostname.sh
```
<pre id="code5" style="display: none">
chmod +x setup_hostname.sh
</pre>
</div>

### 2.2. Chạy script cấu hình hostname trên từng node

#### Cấu hình cho máy master

<div class="code-container">
<button class="copy-button" data-target="code6" onclick="copyToClipboard('code6')">Copy</button>

```bash
# Trên máy master
sudo ./setup_hostname.sh k8s-master1
```
<pre id="code6" style="display: none">
sudo ./setup_hostname.sh k8s-master1
</pre>
</div>

#### Cấu hình cho worker node 1

<div class="code-container">
<button class="copy-button" data-target="code7" onclick="copyToClipboard('code7')">Copy</button>

```powershell
# Khởi động worker node 1
wsl -d k8s-worker1
```
<pre id="code7" style="display: none">
wsl -d k8s-worker1
</pre>
</div>

Sao chép script từ master node (hoặc tạo lại script với nội dung tương tự):

<div class="code-container">
<button class="copy-button" data-target="code8" onclick="copyToClipboard('code8')">Copy</button>

```bash
# Tạo script setup_hostname.sh với nội dung tương tự như trên master
# Sau đó cấp quyền thực thi
chmod +x setup_hostname.sh

# Chạy script với tham số là hostname của worker1
sudo ./setup_hostname.sh k8s-worker1
```
<pre id="code8" style="display: none">
chmod +x setup_hostname.sh
sudo ./setup_hostname.sh k8s-worker1
</pre>
</div>

#### Cấu hình cho worker node 2

<div class="code-container">
<button class="copy-button" data-target="code9" onclick="copyToClipboard('code9')">Copy</button>

```powershell
# Khởi động worker node 2
wsl -d k8s-worker2
```
<pre id="code9" style="display: none">
wsl -d k8s-worker2
</pre>
</div>

Sao chép script từ master node (hoặc tạo lại script với nội dung tương tự):

<div class="code-container">
<button class="copy-button" data-target="code10" onclick="copyToClipboard('code10')">Copy</button>

```bash
# Tạo script setup_hostname.sh với nội dung tương tự như trên master
# Sau đó cấp quyền thực thi
chmod +x setup_hostname.sh

# Chạy script với tham số là hostname của worker2
sudo ./setup_hostname.sh k8s-worker2
```
<pre id="code10" style="display: none">
chmod +x setup_hostname.sh
sudo ./setup_hostname.sh k8s-worker2
</pre>
</div>

### 2.3. Khởi động lại WSL để áp dụng thay đổi

<div class="code-container">
<button class="copy-button" data-target="code11" onclick="copyToClipboard('code11')">Copy</button>

```powershell
# Tắt tất cả các máy ảo WSL
wsl --shutdown

# Khởi động lại các máy ảo
wsl -d k8s-master1
wsl -d k8s-worker1
wsl -d k8s-worker2
```
<pre id="code11" style="display: none">
wsl --shutdown
wsl -d k8s-master1
wsl -d k8s-worker1
wsl -d k8s-worker2
</pre>
</div>

## 3. Xác nhận cấu hình

Sau khi khởi động lại, kiểm tra hostname trên mỗi máy ảo:

<div class="code-container">
<button class="copy-button" data-target="code12" onclick="copyToClipboard('code12')">Copy</button>

```bash
# Kiểm tra hostname
hostname

# Kiểm tra file cấu hình wsl.conf
cat /etc/wsl.conf

# Kiểm tra file hosts
cat /etc/hosts
```
<pre id="code12" style="display: none">
hostname
cat /etc/wsl.conf
cat /etc/hosts
</pre>
</div>

## 4. Tiếp tục với cài đặt Kubernetes

Sau khi đã thiết lập xong môi trường WSL, bạn có thể tiếp tục với việc cài đặt Kubernetes theo hướng dẫn trong tài liệu [README.md](./README.md) hoặc [Kubernetes Cluster Setup Guide](./Kubernetes%20Cluster%20Setup%20Guide.crio.md).

## Lưu ý quan trọng

- Đảm bảo systemd đã được kích hoạt trong WSL để Kubernetes hoạt động chính xác
- Các máy ảo WSL cần có ít nhất 2 CPU và 2GB RAM cho mỗi node
- Nếu gặp vấn đề về kết nối mạng giữa các node, kiểm tra lại cấu hình IP trong file hosts
- Nếu gặp lỗi khi khởi tạo cluster, có thể cần thêm tham số `--ignore-preflight-errors=NumCPU` vào lệnh `kubeadm init`
