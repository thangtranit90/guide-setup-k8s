#!/bin/bash

# Script cai dat Master Node cho Kubernetes
# Ho tro CNI: Flannel hoac Calico
# Ho tro lua chon phien ban Kubernetes va Calico

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
if [ $# -lt 2 ]; then
    echo "Thieu tham so. Vui long chay script voi cu phap:"
    echo "Usage: $0 <cni_type> <k8s_version> [calico_version]"
    echo "  <cni_type>: flannel hoac calico"
    echo "  <k8s_version>: Phien ban Kubernetes (vi du: 1.30.0)"
    echo "  [calico_version]: (Tuy chon) Phien ban Calico (vi du: 3.27.0, chi ap dung khi chon CNI la calico)"
    echo ""
    echo "Example: $0 flannel 1.30.0"
    echo "Example: $0 calico 1.30.0 3.26.0"
    exit 1
fi

# Lay tham so tu dong lenh
CNI_TYPE=$(echo "$1" | tr '[:upper:]' '[:lower:]')  # Chuyen ve chu thuong
K8S_VERSION="$2"
CALICO_VERSION="3.29.0"  # Phien ban Calico mac dinh

# Neu co tham so thu 3 va CNI la calico, su dung phien ban Calico duoc chi dinh
if [ $# -ge 3 ] && [ "$CNI_TYPE" == "calico" ]; then
    CALICO_VERSION="$3"
    # Kiem tra dinh dang phien ban Calico
    if ! [[ $CALICO_VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "Phien ban Calico khong hop le. Format dung: X.Y.Z (vi du: 3.27.0)"
        exit 1
    fi
fi

# Kiem tra CNI type
if [ "$CNI_TYPE" != "flannel" ] && [ "$CNI_TYPE" != "calico" ]; then
    echo "CNI khong hop le. Chi ho tro 'flannel' hoac 'calico'."
    exit 1
fi

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
    echo "⚠️  CANH BAO: Kubernetes phien ban $K8S_VERSION chua duoc kiem thu chinh thuc voi Calico."
    echo "⚠️  Calico 3.29 chi duoc kiem thu chinh thuc voi Kubernetes 1.29, 1.30, va 1.31."
    echo "⚠️  Phien ban cao hon co the hoat dong nhung khong duoc dam bao."
    echo ""
    
    # Neu su dung Calico, hien thi canh bao bo sung
    if [ "$CNI_TYPE" == "calico" ]; then
        echo "⚠️  Ban dang su dung Calico phien ban $CALICO_VERSION voi Kubernetes $K8S_VERSION."
        echo "⚠️  Neu gap van de, hay xem xet su dung phien ban Kubernetes duoc ho tro (1.31 hoac thap hon),"
        echo "⚠️  hoac kiem tra trang web chinh thuc cua Calico de biet phien ban moi nhat ho tro Kubernetes $K8S_VERSION:"
        echo "⚠️  https://docs.tigera.io/calico/latest/getting-started/kubernetes/requirements"
        echo ""
    fi
    
    read -p "Ban co muon tiep tuc cai dat? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cai dat bi huy bo."
        exit 1
    fi
fi

# Xac dinh CIDR dua tren CNI
if [ "$CNI_TYPE" == "flannel" ]; then
    POD_CIDR="10.244.0.0/16"  # CIDR mac dinh cua Flannel
    echo "Da chon CNI: Flannel voi CIDR $POD_CIDR"
else
    POD_CIDR="192.168.0.0/16"  # CIDR mac dinh cua Calico
    echo "Da chon CNI: Calico phien ban $CALICO_VERSION voi CIDR $POD_CIDR"
fi

echo "Phien ban Kubernetes: $K8S_VERSION"
echo "===== Bat dau cai dat Master Node cho Kubernetes ====="

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

# Step 5: Khoi tao Cluster
echo "===== Step 5: Khoi tao Cluster ====="

# Xac dinh dia chi IP chinh cua may
# Tu dong phat hien giao dien mang chinh
MAIN_INTERFACE=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
IPADDR=$(ip -4 addr show $MAIN_INTERFACE | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
NODENAME=$(hostname -s)

echo "Su dung dia chi IP: $IPADDR tren giao dien $MAIN_INTERFACE"
echo "Ten node: $NODENAME"
echo "CIDR cho Pod: $POD_CIDR ($CNI_TYPE mac dinh)"

# Khoi tao cluster voi cac tham so phu hop
sudo kubeadm init --apiserver-advertise-address=$IPADDR \
    --apiserver-cert-extra-sans=$IPADDR \
    --pod-network-cidr=$POD_CIDR \
    --node-name $NODENAME \
    --cri-socket unix:///run/containerd/containerd.sock \
    --ignore-preflight-errors=NumCPU,Mem

# Neu gap loi, thu them cac tham so bo qua loi khac
if [ $? -ne 0 ]; then
    echo "Khoi tao cluster that bai, thu lai voi cac tham so bo qua loi bo sung..."
    sudo kubeadm init --apiserver-advertise-address=$IPADDR \
        --apiserver-cert-extra-sans=$IPADDR \
        --pod-network-cidr=$POD_CIDR \
        --node-name $NODENAME \
        --cri-socket unix:///run/containerd/containerd.sock \
        --ignore-preflight-errors=NumCPU,Mem,Swap
fi

# Cau hinh kubectl cho nguoi dung hien tai
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Cai dat CNI plugin
echo "===== Cai dat $CNI_TYPE CNI ====="
if [ "$CNI_TYPE" == "flannel" ]; then
    echo "Dang cai dat Flannel CNI..."
    kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
    echo "Da cai dat Flannel CNI thanh cong"
else
    echo "Dang cai dat Calico CNI phien ban $CALICO_VERSION..."
    # Sử dụng phiên bản Calico được chỉ định
    kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v$CALICO_VERSION/manifests/calico.yaml
    echo "Da cai dat Calico CNI phien ban $CALICO_VERSION thanh cong"
fi

echo "===== Cai dat Master Node hoan tat ====="
echo "Cluster da duoc khoi tao voi CNI: $CNI_TYPE va Kubernetes phien ban: $K8S_VERSION"
if [ "$CNI_TYPE" == "calico" ]; then
    echo "Phien ban Calico: $CALICO_VERSION"
fi
echo ""
echo "De kiem tra trang thai cua cac pod:"
echo "kubectl get pods --all-namespaces"
echo ""
echo "De xem thong tin node:"
echo "kubectl get nodes -o wide"

# Cau hinh kubectl alias va bash completion
echo "===== Cau hinh kubectl alias va bash completion ====="

# Cai dat bash-completion
echo "Cai dat bash-completion..."
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y bash-completion

# Them bash-completion vao .bashrc neu chua co
echo "Cau hinh bash-completion..."
grep -q "source /usr/share/bash-completion/bash_completion" ~/.bashrc || echo 'source /usr/share/bash-completion/bash_completion' >> ~/.bashrc

# Tao tep completion cho kubectl
echo "Tao tep completion cho kubectl..."
kubectl completion bash | sudo tee /etc/bash_completion.d/kubectl > /dev/null

# Them alias va completion cho alias
echo "Cau hinh alias 'k' cho kubectl..."
grep -q "alias k=kubectl" ~/.bashrc || echo 'alias k=kubectl' >> ~/.bashrc
grep -q "complete -o default -F __start_kubectl k" ~/.bashrc || echo 'complete -o default -F __start_kubectl k' >> ~/.bashrc

# Nap lai .bashrc
echo "Nap lai cau hinh bash..."
source ~/.bashrc

echo "Da cau hinh xong kubectl alias (k) va bash completion."
echo "Ban co the su dung lenh 'k' thay cho 'kubectl'."
echo ""
echo "===== Cai dat hoan tat ====="
