bash -c '
# ── 1. Azure CLI ────────────────────────────────────────────────
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc && \
sudo dnf install -y https://packages.microsoft.com/config/rhel/9.0/packages-microsoft-prod.rpm && \
sudo dnf install -y azure-cli && \
az version && \

# ── 2. Docker ───────────────────────────────────────────────────
sudo dnf install -y yum-utils && \
sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo && \
sudo dnf install -y docker-ce docker-ce-cli containerd.io && \
sudo systemctl start docker && \
sudo systemctl enable docker && \
sudo usermod -aG docker $USER && \
docker version && \

# ── 3. kubectl ──────────────────────────────────────────────────
sudo tee /etc/yum.repos.d/kubernetes.repo <<EOF
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.30/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.30/rpm/repodata/repomd.xml.key
EOF
sudo dnf install -y kubectl && \
kubectl version --client && \

'
