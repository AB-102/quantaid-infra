#!/bin/sh

. ./frontend.env

sudo apt update
sudo apt install npm git -y
sudo npm install -g serve@14  # not a frontend dependency
sudo tee /etc/netplan/00-installer-config.yaml > /dev/null <<'EOF'
network:
  version: 2
  ethernets:
    ens33:
      dhcp4: false
      dhcp6: false
      addresses:
        - 192.168.111.20/24
      routes:
        - to: default
          via: 192.168.111.2
      nameservers:
        addresses:
          - 192.168.111.53
EOF
sudo netplan apply
git clone https://github.com/AB-102/quantaid-frontend.git
cd quantaid-frontend/frontend
cat > .env <<EOF
VITE_BACKEND_URL=$VITE_BACKEND_URL
EOF
npm install
npm run build
sudo tee /etc/systemd/system/quantaid-frontend.service > /dev/null <<'EOF'
[Unit]
Description=Quantaid Frontend
After=network.target

[Service]
Type=simple
User=anb
WorkingDirectory=/home/anb/quantaid-frontend/frontend
ExecStart=/usr/local/bin/serve -s dist -l 5173
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable quantaid-frontend
sudo systemctl start quantaid-frontend
sudo ufw allow from 192.168.111.10 to any port 5173
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
