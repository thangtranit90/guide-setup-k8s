# Hướng Dẫn Thiết Lập Kubernetes Cluster với Containerd trên ubuntu 24.04 

Hướng dẫn này mô tả cách thiết lập Kubernetes cluster sử dụng kubeadm và containerd làm container runtime.(verion k8s 1.30 trên wsl ubuntu 24.0). Để lab test k8s master thì bạn có thể cài wsl ubuntu 24.0. Xem chi tiết file `setup enviroment ubuntu k8s on wsl.md`.

---

## Step 1: Chuẩn Bị Hệ Thống (Tất Cả Các Node)

Đầu tiên, cập nhật hệ thống và cài đặt các gói cần thiết:

```bash
sudo apt-get update -y
sudo apt-get upgrade -y
sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
```

---

## Step 2: Cấu Hình Kernel và Tắt Swap (Tất Cả Các Node)

Nạp các module kernel cần thiết và cấu hình tham số:

```bash
# Nạp module kernel
sudo modprobe overlay
sudo modprobe br_netfilter

# Cấu hình tham số kernel
sudo tee /etc/sysctl.d/kubernetes.conf << EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

# Áp dụng tham số
sudo sysctl --system

# Đảm bảo các module được nạp khi khởi động
sudo tee /etc/modules-load.d/k8s.conf << EOF
overlay
br_netfilter
EOF
```

Tắt swap (yêu cầu cho Kubernetes):

```bash
# Tắt swap ngay lập tức
sudo swapoff -a

# Vô hiệu hóa swap khi khởi động
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Đảm bảo swap bị tắt khi khởi động lại
(crontab -l 2>/dev/null; echo "@reboot /sbin/swapoff -a") | crontab - || true
```

### ⚠️ Lưu ý 
Nếu cần, bạn có thể bỏ qua lỗi swap bằng tham số `--ignore-preflight-errors Swap` khi khởi tạo cluster.

---

## Step 3: Cài Đặt Containerd (Tất Cả Các Node)

Cài đặt containerd từ repository chính thức:

```bash

# Thêm khóa GPG Docker
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Thêm repository Docker
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Cài đặt containerd
sudo apt-get update -y
sudo apt-get install -y containerd.io
```

Cấu hình containerd để sử dụng systemd cgroup driver(cực kì quan trong với ubuntu24):

```bash
# Tạo thư mục cấu hình nếu chưa tồn tại
sudo mkdir -p /etc/containerd

# Tạo cấu hình mặc định
sudo containerd config default | sudo tee /etc/containerd/config.toml > /dev/null

# Sửa cấu hình để sử dụng SystemdCgroup
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

# Khởi động lại containerd
sudo systemctl restart containerd
sudo systemctl enable containerd
```

Cài đặt **crictl** để tương tác với containerd(Cái này dùng cho troubleshoot container runtime):

```bash
VERSION="v1.30.0"
wget https://github.com/kubernetes-sigs/cri-tools/releases/download/$VERSION/crictl-$VERSION-linux-amd64.tar.gz
sudo tar zxvf crictl-$VERSION-linux-amd64.tar.gz -C /usr/local/bin
rm -f crictl-$VERSION-linux-amd64.tar.gz

# Cấu hình crictl sử dụng containerd
sudo tee /etc/crictl.yaml << EOF
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
EOF
```

---

## Step 4: Cài Đặt Kubeadm, Kubelet & Kubectl (Tất Cả Các Node)

Cài đặt các công cụ Kubernetes:

```bash
KUBERNETES_VERSION=1.30

# Thêm khóa GPG Kubernetes
sudo mkdir -p /etc/apt/keyrings
curl -fsSL [https://pkgs.k8s.io/core:/stable:/v$KUBERNETES_VERSION/deb/Release.key](https://pkgs.k8s.io/core:/stable:/v$KUBERNETES_VERSION/deb/Release.key) | \
    sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Thêm repository Kubernetes
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] [https://pkgs.k8s.io/core:/stable:/v$KUBERNETES_VERSION/deb/](https://pkgs.k8s.io/core:/stable:/v$KUBERNETES_VERSION/deb/) /" | \
    sudo tee /etc/apt/sources.list.d/kubernetes.list

# Cài đặt các gói Kubernetes
sudo apt-get update -y
sudo apt-get install -y kubelet=1.30.0-1.1 kubeadm=1.30.0-1.1 kubectl=1.30.0-1.1
sudo apt-mark hold kubelet kubeadm kubectl
```

Kiểm tra phiên bản cụ thể: Nếu cần cài đặt một phiên bản cụ thể, bạn có thể sử dụng lệnh sau để liệt kê các phiên bản có sẵn:

```bash
apt-cache madison kubeadm | tac
```

(Option)cài đặt phiên bản mong muốn (ví dụ: 1.30.0-1.1):

```bash
sudo apt-get install -y kubelet=1.30.0-1.1 kubectl=1.30.0-1.1 kubeadm=1.30.0-1.1
sudo apt-mark hold kubelet kubeadm kubectl
```

Cấu hình IP cho Kubelet:

```bash

# Lấy giao diện mạng chính dựa trên route mặc định
main_interface=$(ip -4 route show default | awk '{print $5}' | head -1)
local_ip=$(ip -4 addr show $main_interface | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
cat > /etc/default/kubelet << EOF
KUBELET_EXTRA_ARGS=--node-ip=$local_ip
EOF
```

---

## Step 5: Khởi Tạo Cluster (Chỉ Trên Master Node)

> ### ⚠️ Tự động hóa với script
> Bạn có thể sử dụng script `master_setup_version1_xx.sh` để tự động hóa toàn bộ quá trình cài đặt master node, từ bước 1 đến bước 6, bao gồm cả việc cài đặt CNI:
> 
> ```bash
> # Cấp quyền thực thi cho script
> chmod +x master_setup_version1_xx.sh
> 
> # Cài đặt với Flannel CNI và Kubernetes 1.30.0
> ./master_setup_version1_30.sh flannel 1.30.0
> 
> # Hoặc cài đặt với Calico CNI và Kubernetes 1.30.0
> ./master_setup_version1_30.sh calico 1.30.0
> 
> # Hoặc cài đặt với phiên bản Kubernetes khác (ví dụ: 1.29.2)
> ./master_setup_version1_30.sh flannel 1.29.2
> ```
> 
> Script yêu cầu 2 tham số:
> 1. **CNI Type**: `flannel` hoặc `calico`
> 2. **K8s Version**: Phiên bản Kubernetes (ví dụ: `1.30.0`)
>
> Script sẽ tự động:
> - Cập nhật hệ thống
> - Cấu hình kernel và tắt swap
> - Cài đặt containerd với SystemdCgroup=true
> - Cài đặt Kubernetes với phiên bản chỉ định
> - Khởi tạo cluster với CIDR phù hợp cho CNI đã chọn
> - Cài đặt CNI (Flannel hoặc Calico)
> - Cấu hình kubectl cho người dùng hiện tại

Khởi tạo cluster trên master node:
Nếu là **Private IP**:
```bash
IPADDR=$local_ip
NODENAME=$(hostname -s)
POD_CIDR="192.168.0.0/16"

sudo kubeadm init --apiserver-advertise-address=$IPADDR \
    --apiserver-cert-extra-sans=$IPADDR \
    --pod-network-cidr=$POD_CIDR \
    --node-name $NODENAME \
    --cri-socket unix:///run/containerd/containerd.sock \
    --ignore-preflight-errors Swap
```
**Lưu ý:** có thể bỏ qua`--ignore-preflight-errors Swap` nếu đã config bỏ qua swap

Nếu là **Public IP**:

```bash
IPADDR=$(curl ifconfig.me && echo "")
NODENAME=$(hostname -s)
POD_CIDR="192.168.0.0/16"

sudo kubeadm init --control-plane-endpoint=$IPADDR \
    --apiserver-cert-extra-sans=$IPADDR \
    --pod-network-cidr=$POD_CIDR \
    --node-name $NODENAME \
    --cri-socket unix:///run/containerd/containerd.sock \
    --ignore-preflight-errors Swap
```

Sau khi hoàn tất, cấu hình `kubectl` trên master node:

```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

Tạo alias cho kubectl để sử dụng thuận tiện hơn:



```bash
# 1. Đảm bảo bash-completion đã được cài đặt
sudo apt-get install -y bash-completion

# 2. Thêm bash-completion vào .bashrc nếu chưa có
echo 'source /usr/share/bash-completion/bash_completion' >> ~/.bashrc

# 3. Tạo tệp completion cho kubectl
kubectl completion bash | sudo tee /etc/bash_completion.d/kubectl > /dev/null

# 4. Thêm alias và completion cho alias
echo 'alias k=kubectl' >> ~/.bashrc
echo 'complete -o default -F __start_kubectl k' >> ~/.bashrc

# 5. Nạp lại .bashrc
source ~/.bashrc
```

Kiểm tra trạng thái cluster:

```bash
kubectl get po -n kube-system
```

### ⚠️ Lưu ý 
Sau khi cài xong thì trạng thái của pod `coredns` sẽ là `Pending` do chưa có CNI (Container Network Interface) được cài đặt.

Kiểm tra trạng thái sức khỏe của các thành phần trong cluster:

```bash
kubectl get --raw='/readyz?verbose'
```

Xem thông tin về cluster:

```bash
kubectl cluster-info
```

### ⚠️ Lưu ý 
Theo mặc định, các ứng dụng sẽ không được lập lịch trên node master. Nếu bạn muốn sử dụng node master để chạy các ứng dụng, hãy loại bỏ taint trên node master:

```bash
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
```

---

## Step 6: Cài Đặt CNI Plugin (Chỉ Trên Master Node)

Cài đặt Calico CNI:

```bash
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml
```

Hoặc cài đặt Flannel CNI:

```bash

# Tải xuống file cấu hình Flannel
wget https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml

# Chỉnh sửa file để thay đổi CIDR
# Tìm phần "net-conf.json" và thay đổi "Network": "10.244.0.0/16" thành "Network": "x.x.x.0/16" vì mặc định flannel là 10.244.0.0/16
# Thay x.x.x.0/16 bằng CIDR bạn đã sử dụng khi khởi tạo cluster
sed -i 's|"Network": "10.244.0.0/16"|"Network": "192.168.0.0/16"|g' kube-flannel.yml

# Áp dụng cấu hình đã sửa
kubectl apply -f kube-flannel.yml
```

Kiểm tra trạng thái pod sau khi cài đặt CNI:

```bash
kubectl get pods -n kube-system
```

---

## Step 7: Thêm Worker Node Vào Cluster
> ### ⚠️ Lưu ý
> Ở bước 7 này bạn có thể tự động hóa quá trình cài đặt bằng cách chạy script `worker_setup.sh`:
> ```bash
> chmod +x worker_setup.sh
> sudo ./worker_setup.sh
> ```
> Script này sẽ tự động thực hiện tất cả các bước từ 7.1 đến 7.4, giúp tiết kiệm thời gian và tránh lỗi cấu hình thủ công.

### Chuẩn Bị Worker Node


Trên các **worker nodes**, bạn cần thực hiện các bước cài đặt tương tự như master node từ Step 1 đến Step 4:

1. **Cập nhật hệ thống và cài đặt các gói cần thiết**:
```bash
sudo apt-get update -y
sudo apt-get upgrade -y
sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
```

2. **Cấu hình kernel và tắt swap**:
```bash
# Nạp module kernel
sudo modprobe overlay
sudo modprobe br_netfilter

# Cấu hình tham số kernel
sudo tee /etc/sysctl.d/kubernetes.conf << EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

# Áp dụng tham số
sudo sysctl --system

# Đảm bảo các module được nạp khi khởi động
sudo tee /etc/modules-load.d/k8s.conf << EOF
overlay
br_netfilter
EOF

# Tắt swap
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
```

3. **Cài đặt containerd**:
```bash
# Cài đặt các gói cần thiết
sudo apt-get update -y
sudo apt-get install -y ca-certificates curl gnupg

# Thêm khóa GPG Docker
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Thêm repository Docker
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Cài đặt containerd
sudo apt-get update -y
sudo apt-get install -y containerd.io

# Cấu hình containerd
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd
```

4. **Cài đặt kubeadm, kubelet và kubectl**:
```bash
KUBERNETES_VERSION=1.29

# Thêm khóa GPG Kubernetes
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v$KUBERNETES_VERSION/deb/Release.key | \
    sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Thêm repository Kubernetes
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v$KUBERNETES_VERSION/deb/ /" | \
    sudo tee /etc/apt/sources.list.d/kubernetes.list

# Cài đặt các gói Kubernetes
sudo apt-get update -y
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# Cấu hình IP cho Kubelet
sudo apt-get install -y jq
main_interface=$(ip -4 route show default | awk '{print $5}' | head -1)
local_ip=$(ip -4 addr show $main_interface | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
cat > /etc/default/kubelet << EOF
KUBELET_EXTRA_ARGS=--node-ip=$local_ip
EOF
```

### Join Worker Node vào Cluster

Trên **master node**, tạo token để worker node có thể join vào cluster:

```bash
kubeadm token create --print-join-command
```

Lệnh này sẽ tạo ra một lệnh `kubeadm join` đầy đủ, ví dụ:

```
kubeadm join 172.31.36.94:6443 --token vqlntf.rmkesem7yn0z4sn6 --discovery-token-ca-cert-hash sha256:77fc7aac56c97df5a7b805bbec54e4268e249a4b9c4bf59ebcef1ba4ff77e737
```

Sao chép lệnh này và chạy trên **worker node** với quyền root, nhớ thêm tham số `--cri-socket`:

```bash
sudo kubeadm join 192.168.1.100:6443 --token abcdef.0123456789abcdef \
    --discovery-token-ca-cert-hash sha256:1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef \
    --cri-socket unix:///run/containerd/containerd.sock
```

### Kiểm Tra Trạng Thái Cluster

Sau khi worker node đã join vào cluster, kiểm tra trạng thái từ master node:

```bash
kubectl get nodes
kubectl get nodes -o wide
```

Nếu node hiển thị trạng thái `NotReady`, hãy kiểm tra xem CNI đã được cài đặt đúng cách chưa:

```bash
kubectl get pods --all-namespaces
```


### Gỡ và Join Lại Worker Node

Trong một số trường hợp, bạn có thể cần gỡ worker node khỏi cluster và join lại, ví dụ như khi:
- Cần thay đổi hostname của node
- Node gặp sự cố và cần cài đặt lại
- Cần cập nhật cấu hình cơ bản của node

#### Gỡ Worker Node Khỏi Cluster

1. **Drain node** để di chuyển tất cả workload ra khỏi node (thực hiện trên master node):
```bash
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
```

2. **Xóa node khỏi cluster** (thực hiện trên master node):
```bash
kubectl delete node <node-name>
```

3. **Reset Kubernetes** trên worker node:
```bash
sudo kubeadm reset -f
sudo rm -rf /etc/kubernetes/
sudo rm -rf $HOME/.kube/
```

#### Thay Đổi Hostname (Nếu Cần)

Nếu bạn cần thay đổi hostname của worker node:

```bash
# Đặt hostname mới
sudo hostnamectl set-hostname <new-hostname>

# Cập nhật file hosts
sudo sed -i "s/127.0.0.1 localhost/127.0.0.1 localhost <new-hostname>/" /etc/hosts

# Khởi động lại để áp dụng thay đổi
sudo reboot
```

#### Join Lại Worker Node Vào Cluster

1. **Tạo token mới** trên master node:
```bash
kubeadm token create --print-join-command
```

2. **Join lại cluster** với token mới trên worker node:
```bash
# Sử dụng lệnh từ output của bước trên, ví dụ:
sudo kubeadm join 192.168.1.100:6443 \
    --token abcdef.0123456789abcdef \
    --discovery-token-ca-cert-hash sha256:1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef \
    --cri-socket unix:///run/containerd/containerd.sock
```

3. **Kiểm tra trạng thái** từ master node:
```bash
kubectl get nodes
```

> ### ⚠️ Lưu ý
> - Khi gỡ node, các pod đang chạy trên node đó sẽ bị xóa và được lập lịch lại trên các node khác (nếu có)
> - Dữ liệu cục bộ trên node (không sử dụng persistent volume) sẽ bị mất
> - Các taint và label được áp dụng cho node cũ sẽ không tự động chuyển sang khi node join lại

---

## Step 8: Kiểm Tra Cluster

Kiểm tra tất cả các pods đang chạy:

```bash
kubectl get pods --all-namespaces
```

Kiểm tra trạng thái của các nodes:

```bash
kubectl get nodes
kubectl describe node <node-name>
```

Triển khai ứng dụng thử nghiệm:

```bash
kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --port=80 --type=NodePort
kubectl get svc nginx
```

---

## Step 9: Cài Đặt Metrics Server

Metrics Server là thành phần thu thập thông tin về tài nguyên sử dụng (CPU, memory) của các pod và node trong Kubernetes cluster. Đây là thành phần cần thiết cho các tính năng như Horizontal Pod Autoscaler (HPA) và lệnh `kubectl top`.

### Bước 1: Tải file cấu hình Metrics Server

```bash
wget https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml -O metrics-server.yaml
```

### Bước 2: Chỉnh sửa file cấu hình để bỏ qua xác thực TLS

Mở file metrics-server.yaml và thêm tham số `--kubelet-insecure-tls` vào container args:

```bash
vi metrics-server.yaml
```

Tìm phần `args` trong container `metrics-server` và thêm dòng sau:

```yaml
        args:
          - --cert-dir=/tmp
          - --secure-port=4443
          - --kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname
          - --kubelet-use-node-status-port
          - --metric-resolution=15s
          - --kubelet-insecure-tls  # Thêm dòng này
```

### Bước 3: Áp dụng cấu hình

```bash
kubectl apply -f metrics-server.yaml
```

### Bước 4: Kiểm tra trạng thái của Metrics Server

```bash
kubectl get deployment metrics-server -n kube-system
```

### Bước 5: Kiểm tra xem Metrics Server đã hoạt động chưa

Sau khi cài đặt thành công, đợi khoảng 1-2 phút để Metrics Server thu thập dữ liệu, sau đó kiểm tra:

```bash
# Kiểm tra tài nguyên sử dụng của các node
kubectl top nodes

# Kiểm tra tài nguyên sử dụng của các pod
kubectl top pods -A
```

> ### ⚠️ Lưu ý
> - Nếu gặp lỗi "Metrics not available", hãy đợi thêm vài phút để Metrics Server thu thập dữ liệu
> - Trong môi trường production, bạn nên cấu hình xác thực TLS đúng cách thay vì sử dụng `--kubelet-insecure-tls`
> - Metrics Server tiêu tốn tài nguyên, vì vậy hãy cân nhắc cấu hình requests và limits phù hợp

---

## Tham Khảo

- [How To Setup Kubernetes Cluster Using Kubeadm](https://devopscube.com/setup-kubernetes-cluster-kubeadm/)
- [Containerd Documentation](https://containerd.io/docs/)
- [Kubernetes Documentation](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/)

---
