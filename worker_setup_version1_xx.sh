#!/bin/bash

# Script cai dat Worker Node cho Kubernetes
# Ho tro lua chon phien ban Kubernetes

# Cau hinh khong hien thi hop thoai tuong tac
export DEBIAN_FRONTEND=noninteractive

# Cau hinh tu dong chap nhan khoi dong lai dich vu
sudo bash -c "cat > /etc/apt/apt.conf.d/local << EOF
Dpkg::Options {
   \"--force-confdef\";
   \"--force-confold\";
}
EOF"

# Kiem tra tham so dau vao
if [ $# -lt 1 ]; then
    echo "Thieu tham so. Vui long chay script voi cu phap:"
    echo "Usage: $0 <k8s_version>"
    echo "  <k8s_version>: Phien ban Kubernetes (vi du: 1.30.0)"
    echo ""
    echo "Example: $0 1.30.0"
    exit 1
fi

# Lay tham so tu dong lenh
K8S_VERSION="$1"

# Kiem tra phien ban Kubernetes
if ! [[ $K8S_VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Phien ban Kubernetes khong hop le. Format dung: X.Y.Z (vi du: 1.30.0)"
    exit 1
fi

# Kiem tra tinh tuong thich cua phien ban Kubernetes
K8S_MAJOR=$(echo $K8S_VERSION | cut -d. -f1)
K8S_MINOR=$(echo $K8S_VERSION | cut -d. -f2)

# Kiem tra phien ban Kubernetes >= 1.32
if [ "$K8S_MAJOR" -eq 1 ] && [ "$K8S_MINOR" -ge 32 ]; then
    echo "⚠️  CANH BAO: Kubernetes phien ban $K8S_VERSION chua duoc kiem thu chinh thuc voi cac thanh phan moi nhat."
    echo "⚠️  Phien ban cao hon 1.31 co the hoat dong nhung khong duoc dam bao."
    echo ""
    
    read -p "Ban co muon tiep tuc cai dat? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cai dat bi huy bo."
        exit 1
    fi
fi

echo "Phien ban Kubernetes: $K8S_VERSION"
echo "===== Bat dau cai dat Worker Node cho Kubernetes ====="

# Step 1: Cap nhat he thong
echo "===== Step 1: Cap nhat he thong ====="
sudo DEBIAN_FRONTEND=noninteractive apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

# Step 2: Cau hinh kernel
echo "===== Step 2: Cau hinh kernel ====="
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system

# Kiem tra xem br_netfilter da duoc tai chua
if lsmod | grep -q br_netfilter; then
    echo "Module br_netfilter da duoc tai thanh cong"
else
    echo "CANH BAO: Module br_netfilter chua duoc tai"
    echo "Dang thu tai lai..."
    sudo modprobe br_netfilter
fi

# Step 3: Vo hieu hoa swap
echo "===== Step 3: Vo hieu hoa swap ====="
sudo swapoff -a
sudo sed -i '/swap/s/^/#/' /etc/fstab

# Tao systemd service de vo hieu hoa swap sau khi reboot
echo "Tao systemd service de vo hieu hoa swap sau khi reboot..."
cat <<EOF | sudo tee /etc/systemd/system/disable-swap.service
[Unit]
Description=Disable swap
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c "swapoff -a"
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF

# Kich hoat service
sudo systemctl daemon-reload
sudo systemctl enable disable-swap.service
sudo systemctl start disable-swap.service

# Step 4.1: Cai dat containerd
echo "===== Step 4.1: Cai dat containerd ====="
# Xoa phien ban containerd cu neu co
sudo DEBIAN_FRONTEND=noninteractive apt-get remove containerd containerd.io -y

# Cai dat cac goi phu thuoc
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release

# Them khoa GPG Docker
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Them repository Docker
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Cap nhat lai apt
sudo DEBIAN_FRONTEND=noninteractive apt-get update

# Cai dat containerd
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y containerd.io

# Cau hinh containerd su dung systemd cgroup driver
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

# Khoi dong lai containerd
sudo systemctl restart containerd
sudo systemctl enable containerd

# Step 4.2: Cai dat kubeadm, kubelet, kubectl
echo "===== Step 4.2: Cai dat kubeadm, kubelet, kubectl ====="
# Lay major va minor version
MAJOR_MINOR=$(echo $K8S_VERSION | cut -d. -f1,2)

# Them khoa GPG Kubernetes
curl -fsSL https://pkgs.k8s.io/core:/stable:/v$MAJOR_MINOR/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Them repository Kubernetes
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v$MAJOR_MINOR/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list > /dev/null

# Cap nhat lai apt
sudo DEBIAN_FRONTEND=noninteractive apt-get update

# Cai dat kubelet, kubeadm, kubectl voi phien ban cu the
K8S_PKG_VERSION="${K8S_VERSION}-1.1"
echo "Cai dat cac goi Kubernetes phien ban $K8S_PKG_VERSION"
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y kubelet=$K8S_PKG_VERSION kubeadm=$K8S_PKG_VERSION kubectl=$K8S_PKG_VERSION --allow-change-held-packages

# Giu cac goi khong cho cap nhat tu dong
sudo apt-mark hold kubelet kubeadm kubectl

# Step 5: Cau hinh kubelet node IP
echo "===== Step 5: Cau hinh kubelet node IP ====="

# Xac dinh dia chi IP chinh cua may
# Tu dong phat hien giao dien mang chinh
MAIN_INTERFACE=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
IPADDR=$(ip -4 addr show $MAIN_INTERFACE | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
NODENAME=$(hostname -s)

echo "Su dung dia chi IP: $IPADDR tren giao dien $MAIN_INTERFACE"
echo "Ten node: $NODENAME"

# Cau hinh kubelet su dung IP chinh
cat <<EOF | sudo tee /etc/default/kubelet
KUBELET_EXTRA_ARGS=--node-ip=$IPADDR
EOF

sudo systemctl daemon-reload
sudo systemctl restart kubelet

echo "===== Cai dat Worker Node hoan tat ====="
echo "Worker node da san sang de gia nhap cluster!"
echo ""
echo "De gia nhap cluster, chay lenh kubeadm join tu master node:"
echo "kubeadm token create --print-join-command"
echo ""
echo "Sau do chay lenh join tren worker node nay."
