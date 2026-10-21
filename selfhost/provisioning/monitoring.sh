#!/bin/sh

. ./monitoring.env

sudo apt update
sudo apt install -y curl wget gnupg tar

sudo tee /etc/netplan/00-installer-config.yaml > /dev/null <<'EOF'
network:
  version: 2
  ethernets:
    ens33:
      dhcp4: false
      dhcp6: false
      addresses:
        - 192.168.111.40/24
      routes:
        - to: default
          via: 192.168.111.2
      nameservers:
        addresses:
          - 192.168.111.53
EOF
sudo netplan apply

curl -LO https://fastdl.mongodb.org/tools/db/mongodb-database-tools-ubuntu2404-x86_64-100.17.0.tgz
tar -xzf mongodb-database-tools-ubuntu2404-x86_64-100.17.0.tgz
sudo cp mongodb-database-tools-ubuntu2404-x86_64-100.17.0/bin/mongodump /usr/local/bin/

# --- MongoDB backup: scheduled mongodump against Atlas ---
sudo mkdir -p /opt/quantaid-backup
sudo mkdir -p /var/backups/quantaid-mongo
sudo chmod 700 /var/backups/quantaid-mongo # the dumps hold every user's data
sudo mkdir -p /var/lib/node_exporter/textfile

sudo tee /opt/quantaid-backup/mongodump-config.yaml > /dev/null <<EOF
uri: $MONGODB_BACKUP_URI
EOF
sudo chmod 600 /opt/quantaid-backup/mongodump-config.yaml

sudo tee /opt/quantaid-backup/backup.sh > /dev/null <<'EOF'
#!/bin/sh
set -e

BACKUP_DIR=/var/backups/quantaid-mongo
RETENTION_DAYS=14
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
DEST="$BACKUP_DIR/$TIMESTAMP"

mkdir -p "$DEST"
mongodump --config=/opt/quantaid-backup/mongodump-config.yaml --gzip --out="$DEST"

find "$BACKUP_DIR" -maxdepth 1 -type d -mtime +$RETENTION_DAYS -exec rm -rf {} \;

echo "quantaid_backup_last_success_timestamp $(date +%s)" > /var/lib/node_exporter/textfile/quantaid_backup.prom.tmp
mv /var/lib/node_exporter/textfile/quantaid_backup.prom.tmp /var/lib/node_exporter/textfile/quantaid_backup.prom
EOF
sudo chmod +x /opt/quantaid-backup/backup.sh

sudo tee /etc/systemd/system/quantaid-backup.service > /dev/null <<'EOF'
[Unit]
Description=Quantaid MongoDB Backup

[Service]
Type=oneshot
ExecStart=/opt/quantaid-backup/backup.sh
EOF
sudo tee /etc/systemd/system/quantaid-backup.timer > /dev/null <<'EOF'
[Unit]
Description=Run Quantaid MongoDB Backup daily

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now quantaid-backup.timer

# --- node_exporter: system metrics for this VM ---
curl -LO https://github.com/prometheus/node_exporter/releases/download/v1.11.1/node_exporter-1.11.1.linux-amd64.tar.gz
tar -xzf node_exporter-1.11.1.linux-amd64.tar.gz
sudo cp node_exporter-1.11.1.linux-amd64/node_exporter /usr/local/bin/
sudo mkdir -p /var/lib/node_exporter/textfile
sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<'EOF'
[Unit]
Description=Node Exporter
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/node_exporter --collector.textfile.directory=/var/lib/node_exporter/textfile
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now node_exporter

# --- mongodb_exporter (Atlas M0 exposes few metrics) ---
curl -LO https://github.com/percona/mongodb_exporter/releases/download/v0.51.0/mongodb_exporter-0.51.0.linux-amd64.tar.gz
tar -xzf mongodb_exporter-0.51.0.linux-amd64.tar.gz
sudo cp mongodb_exporter-0.51.0.linux-amd64/mongodb_exporter /usr/local/bin/

sudo tee /opt/quantaid-backup/monitoring-mongo.env > /dev/null <<EOF
MONGODB_URI=$MONGODB_MONITOR_URI
EOF
sudo chmod 600 /opt/quantaid-backup/monitoring-mongo.env

sudo tee /etc/systemd/system/mongodb_exporter.service > /dev/null <<'EOF'
[Unit]
Description=MongoDB Exporter
After=network.target

[Service]
Type=simple
EnvironmentFile=/opt/quantaid-backup/monitoring-mongo.env
ExecStart=/usr/local/bin/mongodb_exporter --collector.diagnosticdata --compatible-mode
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now mongodb_exporter

# --- blackbox_exporter: probes the backend's /health ---
curl -LO https://github.com/prometheus/blackbox_exporter/releases/download/v0.28.0/blackbox_exporter-0.28.0.linux-amd64.tar.gz
tar -xzf blackbox_exporter-0.28.0.linux-amd64.tar.gz
sudo cp blackbox_exporter-0.28.0.linux-amd64/blackbox_exporter /usr/local/bin/
sudo mkdir -p /etc/blackbox_exporter
sudo tee /etc/blackbox_exporter/blackbox.yml > /dev/null <<'EOF'
modules:
  http_2xx:
    prober: http
    timeout: 5s
    http:
      valid_status_codes: [200]
      method: GET
EOF
sudo tee /etc/systemd/system/blackbox_exporter.service > /dev/null <<'EOF'
[Unit]
Description=Blackbox Exporter
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/blackbox_exporter --config.file=/etc/blackbox_exporter/blackbox.yml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now blackbox_exporter

# --- Prometheus ---
curl -LO https://github.com/prometheus/prometheus/releases/download/v3.13.0/prometheus-3.13.0.linux-amd64.tar.gz
tar -xzf prometheus-3.13.0.linux-amd64.tar.gz
sudo cp prometheus-3.13.0.linux-amd64/prometheus /usr/local/bin/
sudo cp prometheus-3.13.0.linux-amd64/promtool /usr/local/bin/
sudo mkdir -p /etc/prometheus /var/lib/prometheus

sudo tee /etc/prometheus/prometheus.yml > /dev/null <<'EOF'
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: node_exporter
    static_configs:
      - targets:
          - proxy.lab.home.arpa:9100
          - frontend.lab.home.arpa:9100
          - backend.lab.home.arpa:9100
          - dns.lab.home.arpa:9100
          - localhost:9100

  - job_name: mongodb_exporter
    static_configs:
      - targets:
          - localhost:9216

  - job_name: blackbox_backend_health
    metrics_path: /probe
    params:
      module: [http_2xx]
    static_configs:
      - targets:
          - http://backend.lab.home.arpa:8000/health
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: localhost:9115
EOF

sudo tee /etc/systemd/system/prometheus.service > /dev/null <<'EOF'
[Unit]
Description=Prometheus
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/prometheus --config.file=/etc/prometheus/prometheus.yml --storage.tsdb.path=/var/lib/prometheus
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now prometheus

# --- Grafana ---
sudo mkdir -p /etc/apt/keyrings
sudo wget -q -O /etc/apt/keyrings/grafana.asc https://apt.grafana.com/gpg-full.key
sudo chmod 644 /etc/apt/keyrings/grafana.asc
echo "deb [signed-by=/etc/apt/keyrings/grafana.asc] https://apt.grafana.com stable main" | sudo tee /etc/apt/sources.list.d/grafana.list
sudo apt update
sudo apt install -y grafana

sudo mkdir -p /etc/grafana/provisioning/datasources
sudo tee /etc/grafana/provisioning/datasources/prometheus.yml > /dev/null <<'EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://localhost:9090
    isDefault: true
    uid: prometheus
EOF

sudo mkdir -p /etc/grafana/provisioning/alerting
sudo tee /etc/grafana/provisioning/alerting/rules.yml > /dev/null <<'EOF'
apiVersion: 1
groups:
  - orgId: 1
    name: quantaid-alerts
    folder: Quantaid
    interval: 1m
    rules:
      - uid: backup-stale
        title: MongoDB backup hasn't succeeded recently
        condition: C
        data:
          - refId: A
            datasourceUid: prometheus
            model:
              expr: time() - quantaid_backup_last_success_timestamp
          - refId: C
            datasourceUid: __expr__
            model:
              type: threshold
              expr: A
              conditions:
                - evaluator:
                    type: gt
                    params: [93600]
        for: 5m

      - uid: backend-health-unreachable
        title: Backend /health check failing
        condition: C
        data:
          - refId: A
            datasourceUid: prometheus
            model:
              expr: probe_success{job="blackbox_backend_health"}
          - refId: C
            datasourceUid: __expr__
            model:
              type: threshold
              expr: A
              conditions:
                - evaluator:
                    type: lt
                    params: [1]
        for: 2m

      - uid: vm-disk-high
        title: VM disk usage above 85%
        condition: C
        data:
          - refId: A
            datasourceUid: prometheus
            model:
              expr: 100 - ((node_filesystem_avail_bytes{mountpoint="/"} * 100) / node_filesystem_size_bytes{mountpoint="/"})
          - refId: C
            datasourceUid: __expr__
            model:
              type: threshold
              expr: A
              conditions:
                - evaluator:
                    type: gt
                    params: [85]
        for: 10m

      - uid: vm-cpu-high
        title: VM CPU usage above 90%
        condition: C
        data:
          - refId: A
            datasourceUid: prometheus
            model:
              expr: 100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
          - refId: C
            datasourceUid: __expr__
            model:
              type: threshold
              expr: A
              conditions:
                - evaluator:
                    type: gt
                    params: [90]
        for: 10m

      - uid: vm-mem-high
        title: VM memory usage above 90%
        condition: C
        data:
          - refId: A
            datasourceUid: prometheus
            model:
              expr: 100 - ((node_memory_MemAvailable_bytes * 100) / node_memory_MemTotal_bytes)
          - refId: C
            datasourceUid: __expr__
            model:
              type: threshold
              expr: A
              conditions:
                - evaluator:
                    type: gt
                    params: [90]
        for: 10m
EOF

sudo tee /etc/grafana/provisioning/alerting/contactpoints.yml > /dev/null <<EOF
apiVersion: 1
contactPoints:
  - orgId: 1
    name: quantaid-alerts
    receivers:
      - uid: quantaid-email
        type: email
        settings:
          addresses: $ALERT_EMAIL_TO
      - uid: quantaid-ntfy
        type: webhook
        settings:
          url: https://ntfy.sh/$NTFY_TOPIC
EOF

sudo tee /etc/grafana/provisioning/alerting/policies.yml > /dev/null <<'EOF'
apiVersion: 1
policies:
  - orgId: 1
    receiver: quantaid-alerts
EOF

sudo tee -a /etc/grafana/grafana.ini > /dev/null <<EOF

[smtp]
enabled = true
host = $SMTP_HOST
user = $SMTP_USER
password = $SMTP_PASSWORD
from_address = $SMTP_FROM_ADDRESS
from_name = Quantaid Alerts
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now grafana-server

# --- firewall ---
sudo ufw allow from 192.168.111.0/24 to any port 3000
sudo ufw allow from 192.168.111.0/24 to any port 9090
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from 192.168.111.0/24 to any port 22 proto tcp # allow SSH before enabling UFW
sudo ufw enable
sudo ufw status numbered
