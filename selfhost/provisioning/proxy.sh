#!/bin/sh

. ./proxy.env

sudo tee /etc/netplan/00-installer-config.yaml > /dev/null <<'EOF'
network:
  version: 2
  ethernets:
    ens33:
      dhcp4: false
      dhcp6: false
      addresses:
        - 192.168.111.10/24
      routes:
        - to: default
          via: 192.168.111.2
      nameservers:
        addresses:
          - 192.168.111.53
EOF
sudo netplan apply
sudo apt update
sudo apt install -y nginx curl
sudo rm -f /etc/nginx/sites-enabled/default
sudo tee /etc/nginx/sites-available/lab > /dev/null <<'EOF'
upstream backend {
    server backend.lab.home.arpa:8000;
}

upstream frontend {
    server frontend.lab.home.arpa:5173;
}

server {
    listen 80;
    server_name proxy.lab.home.arpa;

    location / {
        proxy_pass http://frontend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /api/ {
        proxy_pass http://backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 120s;
        client_max_body_size 10m;  # Image and screenshot uploads; nginx defaults to 1m
    }
}
EOF
sudo ln -sf /etc/nginx/sites-available/lab /etc/nginx/sites-enabled/lab
sudo systemctl reload nginx

curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main" | sudo tee /etc/apt/sources.list.d/cloudflared.list
sudo apt update
sudo apt install -y cloudflared
# Runs the connector for the locally-managed tunnel: ingress from config.yml, auth from the token.
# A root-only token file keeps the token out of the unit file and the process list.
sudo mkdir -p /etc/cloudflared
printf '%s' "$CLOUDFLARE_TUNNEL_TOKEN" | sudo tee /etc/cloudflared/token > /dev/null
sudo chmod 600 /etc/cloudflared/token
sudo tee /etc/cloudflared/config.yml > /dev/null <<'EOF'
ingress:
  - hostname: quantaid.org
    service: http://localhost:80
  - hostname: www.quantaid.org
    service: http://localhost:80
  - service: http_status:404
EOF
sudo tee /etc/systemd/system/cloudflared.service > /dev/null <<'EOF'
[Unit]
Description=Cloudflare Tunnel connector
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
ExecStart=/usr/bin/cloudflared --no-autoupdate tunnel --config /etc/cloudflared/config.yml run --token-file /etc/cloudflared/token
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable cloudflared
sudo systemctl restart cloudflared
sudo ufw allow from 127.0.0.1 to any port 80
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