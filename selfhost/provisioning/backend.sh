#!/bin/sh

. ./backend.env

sudo apt update
sudo apt install -y python3 python3-pip python3-venv git curl
curl -LsSf https://astral.sh/uv/install.sh | sh
echo '. "$HOME/.local/bin/env"' >> ~/.bashrc
. "$HOME/.local/bin/env"
sudo tee /etc/netplan/00-installer-config.yaml > /dev/null <<'EOF'
network:
  version: 2
  ethernets:
    ens33:
      dhcp4: false
      dhcp6: false
      addresses:
        - 192.168.111.30/24
      routes:
        - to: default
          via: 192.168.111.2
      nameservers:
        addresses:
          - 192.168.111.53
EOF
sudo netplan apply
git clone https://github.com/AB-102/quantaid-backend.git
cd quantaid-backend
cat > .env <<EOF
ENVIRONMENT=production
CORS_ORIGINS=https://quantaid.org,https://www.quantaid.org
IS_RICE_DEPLOYMENT=false
GOOGLE_CLIENT_ID=$GOOGLE_CLIENT_ID
OPENAI_API_KEY=$OPENAI_API_KEY
MONGODB_URI=$MONGODB_URI
ADMIN_EMAILS=$ADMIN_EMAILS
JWT_SECRET_KEY=$JWT_SECRET_KEY
RESEND_API_KEY=$RESEND_API_KEY
EOF
uv sync
sudo tee /etc/systemd/system/quantaid-backend.service > /dev/null <<'EOF'
[Unit]
Description=Quantaid Backend
After=network.target

[Service]
Type=simple
User=anb
WorkingDirectory=/home/anb/quantaid-backend
ExecStart=/home/anb/.local/bin/uv run uvicorn main:app --host 0.0.0.0 --port 8000 --workers 2
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable quantaid-backend
sudo systemctl start quantaid-backend
sudo ufw allow from 192.168.111.10 to any port 8000
sudo ufw allow from 192.168.111.40 to any port 8000 # monitoring's /health probe
sudo ufw allow from 192.168.111.40 to any port 9100
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from 192.168.111.0/24 to any port 22 proto tcp # allow SSH before enabling UFW
sudo ufw enable
sudo ufw status numbered

# --- node_exporter: system metrics for Prometheus ---
curl -LO https://github.com/prometheus/node_exporter/releases/download/v1.11.1/node_exporter-1.11.1.linux-amd64.tar.gz
tar -xzf node_exporter-1.11.1.linux-amd64.tar.gz
sudo cp node_exporter-1.11.1.linux-amd64/node_exporter /usr/local/bin/
sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<'EOF'
[Unit]
Description=Node Exporter
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/node_exporter
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now node_exporter
