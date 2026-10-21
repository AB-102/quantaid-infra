#!/bin/sh

sudo apt update
sudo apt install bind9 bind9utils dnsutils -y
sudo tee /etc/netplan/00-installer-config.yaml > /dev/null <<'EOF'
network:
  version: 2
  ethernets:
    ens33:
      dhcp4: false
      dhcp6: false
      addresses:
        - 192.168.111.53/24
      routes:
        - to: default
          via: 192.168.111.2
      nameservers:
        addresses:
          - 192.168.111.53
EOF
sudo netplan apply
sudo tee /etc/bind/db.lab.home.arpa > /dev/null <<'EOF'
$TTL 86400
@   IN  SOA dns.lab.home.arpa. admin.lab.home.arpa. (
        1
        604800
        86400
        2419200
        86400 )

@       IN  NS      dns.lab.home.arpa.

dns     IN  A       192.168.111.53
proxy   IN  A       192.168.111.10
frontend IN A       192.168.111.20
backend IN  A       192.168.111.30
monitoring IN A     192.168.111.40
EOF
sudo tee /etc/bind/named.conf.options > /dev/null <<'EOF'
options {
    directory "/var/cache/bind";

    recursion yes;
    allow-recursion { 192.168.111.0/24; localhost; };

    forwarders {
        8.8.8.8;
        1.1.1.1;
    };

    dnssec-validation auto;

    listen-on { any; };
    listen-on-v6 { any; };
};
EOF
sudo tee /etc/bind/named.conf.local > /dev/null <<'EOF'
zone "lab.home.arpa" {
    type master;
    file "/etc/bind/db.lab.home.arpa";
};
EOF
sudo systemctl restart bind9
sudo ufw allow from 192.168.111.0/24 to any port 53
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
