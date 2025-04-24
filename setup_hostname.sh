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
echo "wsl --shutdown"
