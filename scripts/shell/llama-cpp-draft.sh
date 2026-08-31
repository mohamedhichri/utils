#!/usr/bin/env bash
# Test-only: install llama.cpp prebuilt CPU binary and expose HTTP API on port 8080.
set -euo pipefail

# ---------- Configuration ----------
MODEL_HF="ggml-org/gemma-4-e4b-it-GGUF:Q4_0"
MODEL_ALIAS="local-4b"
PORT="8080"
CONTEXT_SIZE="4096"
THREADS="$(nproc)"
PARALLEL_REQUESTS="2"
# -----------------------------------

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo bash $0"
  exit 1
fi

echo "[1/6] Installing required utilities..."
dnf install -y curl openssl

echo "[2/6] Downloading the official CPU-only llama prebuilt binary..."
# SKIP_INSTALL keeps the download under /root/.llama-app temporarily.
# The binary is then installed system-wide for the service.
curl -LsSf https://llama.app/install.sh | \
  SKIP_CUDA=1 \
  SKIP_ROCM=1 \
  SKIP_VULKAN=1 \
  SKIP_INSTALL=1 \
  sh

if [[ ! -x /root/.llama-app/llama ]]; then
  echo "Prebuilt binary download failed."
  exit 1
fi

install -m 0755 /root/.llama-app/llama /usr/local/bin/llama

echo "Installed version:"
/usr/local/bin/llama version

echo "[3/6] Creating service account..."
if ! id llama >/dev/null 2>&1; then
  useradd --system \
    --home-dir /var/lib/llama \
    --create-home \
    --shell /sbin/nologin \
    llama
fi

install -d -o llama -g llama -m 0750 /var/lib/llama

echo "[4/6] Creating API configuration..."
API_KEY="$(openssl rand -hex 32)"

cat >/etc/llama-server.env <<EOF
LLAMA_API_KEY=${API_KEY}
MODEL_HF=${MODEL_HF}
MODEL_ALIAS=${MODEL_ALIAS}
PORT=${PORT}
CONTEXT_SIZE=${CONTEXT_SIZE}
THREADS=${THREADS}
PARALLEL_REQUESTS=${PARALLEL_REQUESTS}
EOF

chown root:llama /etc/llama-server.env
chmod 0640 /etc/llama-server.env

echo "[5/6] Creating systemd service..."
cat >/etc/systemd/system/llama-server.service <<'EOF'
[Unit]
Description=llama.cpp OpenAI-compatible HTTP API
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=llama
Group=llama
WorkingDirectory=/var/lib/llama
Environment=HOME=/var/lib/llama
EnvironmentFile=/etc/llama-server.env

# Test only: 0.0.0.0 exposes this service to the network.
ExecStart=/usr/local/bin/llama serve \
  -hf ${MODEL_HF} \
  --alias ${MODEL_ALIAS} \
  --host 0.0.0.0 \
  --port ${PORT} \
  -c ${CONTEXT_SIZE} \
  --threads ${THREADS} \
  --parallel ${PARALLEL_REQUESTS} \
  --api-key ${LLAMA_API_KEY}

Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now llama-server

echo "[6/6] Opening firewall port ${PORT}..."
if systemctl is-active --quiet firewalld; then
  firewall-cmd --permanent --add-port="${PORT}/tcp"
  firewall-cmd --reload
fi

SERVER_IP="$(hostname -I | awk '{print $1}')"

echo
echo "Done. The first service start downloads the model."
echo "Watch progress: sudo journalctl -u llama-server -f"
echo
echo "Endpoint: http://${SERVER_IP}:${PORT}/v1"
echo "API key:  ${API_KEY}"
echo
echo "Test:"
echo "curl http://${SERVER_IP}:${PORT}/v1/chat/completions \\"
echo "  -H 'Authorization: Bearer ${API_KEY}' \\"
echo "  -H 'Content-Type: application/json' \\"
echo "  -d '{\"model\":\"${MODEL_ALIAS}\",\"messages\":[{\"role\":\"user\",\"content\":\"Hello\"}]}'"


sudo systemctl stop llama-server

sudo -u llama curl --fail --location --retry 3 \
  --output /var/lib/llama/models/Ministral-8B-Instruct-2410.Q4_K_M.gguf \
  https://huggingface.co/QuantFactory/Ministral-8B-Instruct-2410-GGUF/resolve/main/Ministral-8B-Instruct-2410.Q4_K_M.gguf
