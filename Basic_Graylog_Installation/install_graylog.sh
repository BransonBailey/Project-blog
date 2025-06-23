#!/bin/bash

# --- Exit on error ---
set -e
echo "----------------------------------"
echo "Graylog Installation - Ubuntu 24.04.2 LTS"
echo "----------------------------------"

# --- Update System ---
echo "[+] Updating system packages..."
sudo apt update --allow-change-held-packages && sudo apt upgrade -y

echo "[+] Installing dependencies..."
sudo apt install -y lsb-release ca-certificates curl gnupg gnupg2 wget unzip openjdk-17-jre

# --- Set Timezone to UTC ---
echo "[+] Setting timezone to UTC..."
sudo timedatectl set-timezone UTC

# --- Remove Old MongoDB Versions ---
echo "[+] Removing any previous MongoDB versions..."
sudo systemctl stop mongod || true
sudo apt remove --purge -y mongodb-org || true
sudo rm -rf /var/lib/mongodb /etc/mongod.conf /var/log/mongodb || true

# --- Add MongoDB Repository ---
echo "[+] Adding MongoDB repository..."
curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | \
   sudo gpg -o /usr/share/keyrings/mongodb-server-7.0.gpg --dearmor

echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-7.0.list

# --- Install MongoDB ---
echo "[+] Updating package lists..."
sudo apt-get update

echo "[+] Installing MongoDB..."
sudo apt-get install -y mongodb-org

# --- Fix MongoDB Permissions ---
echo "[+] Fixing MongoDB permissions..."
sudo mkdir -p /var/lib/mongodb
sudo chown -R mongodb:mongodb /var/lib/mongodb
sudo chmod -R 755 /var/lib/mongodb

# --- Start MongoDB ---
echo "[+] Starting and enabling MongoDB service..."
sudo systemctl daemon-reload
sudo systemctl start mongod
sudo systemctl enable mongod

# --- Wait for MongoDB to Start ---
echo "[+] Waiting for MongoDB to be fully initialized..."
until sudo systemctl is-active --quiet mongod; do
    sleep 5
    echo "[!] Waiting for MongoDB to start..."
done

echo "[+] MongoDB installed and running!"

# --- Install OpenSearch ---
echo "[+] Adding OpenSearch repository..."
curl -o- https://artifacts.opensearch.org/publickeys/opensearch.pgp | sudo gpg --dearmor --batch --yes -o /etc/apt/keyrings/opensearch-keyring
echo "deb [signed-by=/etc/apt/keyrings/opensearch-keyring] https://artifacts.opensearch.org/releases/bundle/opensearch/2.x/apt stable main" | sudo tee /etc/apt/sources.list.d/opensearch-2.x.list

echo "[+] Installing OpenSearch..."
sudo apt update
sudo OPENSEARCH_INITIAL_ADMIN_PASSWORD=$(openssl rand -base64 32) apt install -y opensearch

echo "[+] Preventing OpenSearch upgrades..."
sudo apt-mark hold opensearch

echo "[+] Configuring OpenSearch..."
sudo touch /etc/opensearch/opensearch.yml

sudo sed -i '/^cluster.name:/d' /etc/opensearch/opensearch.yml
sudo sed -i '/^node.name:/d' /etc/opensearch/opensearch.yml
sudo sed -i '/^network.host:/d' /etc/opensearch/opensearch.yml
sudo sed -i '/^discovery.type:/d' /etc/opensearch/opensearch.yml
sudo sed -i '/^action.auto_create_index:/d' /etc/opensearch/opensearch.yml
sudo sed -i '/^plugins.security.disabled:/d' /etc/opensearch/opensearch.yml
sudo sed -i '/^plugins.security.ssl.http.enabled:/d' /etc/opensearch/opensearch.yml

sudo bash -c 'cat <<EOF >> /etc/opensearch/opensearch.yml
cluster.name: graylog
node.name: '"$(hostname)"'
network.host: 127.0.0.1
discovery.type: single-node
action.auto_create_index: false
plugins.security.disabled: true
plugins.security.ssl.http.enabled: false
EOF'

echo "[+] Setting OpenSearch memory limits..."
sudo sed -i 's/^-Xms.*/-Xms2g/' /etc/opensearch/jvm.options
sudo sed -i 's/^-Xmx.*/-Xmx2g/' /etc/opensearch/jvm.options

echo "[+] Configuring kernel parameters for OpenSearch..."
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
sudo sysctl -w vm.max_map_count=262144

echo "[+] Starting and enabling OpenSearch service..."
sudo systemctl enable --now opensearch

# --- Install Graylog ---
wget https://packages.graylog2.org/repo/packages/graylog-6.2-repository_latest.deb
sudo dpkg -i graylog-6.2-repository_latest.deb

# --- Install Graylog Data Node ---
echo "[+] Installing Graylog Data Node..."
wget https://packages.graylog2.org/repo/packages/graylog-6.1-repository_latest.deb
sudo dpkg -i graylog-6.1-repository_latest.deb
sudo apt-get update
sudo apt-get install -y graylog-datanode

# --- Configure Linux Kernel Parameters ---
echo "[+] Configuring Linux kernel parameters for Data Node..."
if ! grep -q "^vm.max_map_count=262144" /etc/sysctl.d/99-graylog-datanode.conf; then
    echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.d/99-graylog-datanode.conf
fi

sudo sysctl --system

# --- Generate and Set Password Secret ---
echo "[+] Generating password secret..."
GRAYLOG_SECRET=$(openssl rand -base64 96)

echo "[+] Configuring Data Node..."

CONFIG_FILE="/etc/graylog/datanode/datanode.conf"

if [ ! -f "$CONFIG_FILE" ]; then
    sudo touch "$CONFIG_FILE"
fi

sudo sed -i '/^password_secret/d' "$CONFIG_FILE"
sudo sed -i '/^opensearch_heap/d' "$CONFIG_FILE"
sudo sed -i '/^mongodb_uri/d' "$CONFIG_FILE"

sudo bash -c "cat <<EOF >> $CONFIG_FILE
password_secret = $GRAYLOG_SECRET
opensearch_heap = 2g
mongodb_uri = mongodb://graylog:27017/graylog
EOF"

# --- Set Heap Memory for Data Node ---
echo "[+] Configuring Data Node heap settings..."

JVM_OPTIONS="/etc/graylog/datanode/jvm.options"

if [ ! -f "$JVM_OPTIONS" ]; then
    sudo touch "$JVM_OPTIONS"
fi

sudo sed -i '/^-Xms/d' "$JVM_OPTIONS"
sudo sed -i '/^-Xmx/d' "$JVM_OPTIONS"

sudo bash -c "cat <<EOF >> $JVM_OPTIONS
-Xms2g
-Xmx2g
EOF"

# --- Enable and Start Data Node ---
echo "[+] Starting and enabling Graylog Data Node service..."
sudo systemctl daemon-reload
sudo systemctl enable graylog-datanode.service
sudo systemctl start graylog-datanode

echo "[+] Graylog Data Node installation complete!"

echo "[+] Installing Graylog..."
sudo apt update --allow-change-held-packages && sudo apt install -y graylog-server

echo "[+] Generating secrets..."
GRAYLOG_ADMIN_PASSWORD=$(echo -n "admin" | sha256sum | cut -d" " -f1)

echo "[+] Configuring Graylog..."

CONFIG_FILE="/etc/graylog/server/server.conf"

if [ ! -f "$CONFIG_FILE" ]; then
    sudo touch "$CONFIG_FILE"
fi

sudo sed -i '/^password_secret/d' "$CONFIG_FILE"
sudo sed -i '/^root_password_sha2/d' "$CONFIG_FILE"
sudo sed -i '/^root_email/d' "$CONFIG_FILE"
sudo sed -i '/^http_bind_address/d' "$CONFIG_FILE"
sudo sed -i '/^http_publish_uri/d' "$CONFIG_FILE"
sudo sed -i '/^elasticsearch_hosts/d' "$CONFIG_FILE"
sudo sed -i '/^transport_email_enabled/d' "$CONFIG_FILE"
sudo sed -i '/^data_dir/d' "$CONFIG_FILE"

sudo bash -c "cat <<EOF >> $CONFIG_FILE
password_secret = $GRAYLOG_SECRET
root_password_sha2 = $GRAYLOG_ADMIN_PASSWORD
root_email = admin@example.com
http_bind_address = 0.0.0.0:9000
http_publish_uri = http://127.0.0.1:9000/
elasticsearch_hosts = http://127.0.0.1:9200
transport_email_enabled = false
data_dir = /var/lib/graylog-server
EOF"

sudo mkdir -p /var/lib/graylog-server
sudo mkdir -p /var/lib/graylog-server/journal
sudo chown -R graylog:graylog /var/lib/graylog-server
sudo chmod -R 755 /var/lib/graylog-server

sudo iptables -A INPUT -p tcp --dport 9000 -j ACCEPT

echo "[+] Starting and enabling Graylog service..."
sudo systemctl enable --now graylog-server

echo "[+] Preventing package upgrades..."
sudo apt-mark hold mongodb-org graylog-server

# --- Configure Syslog Input ---
echo "[+] Configuring Syslog UDP input..."
GRAYLOG_INPUT_PAYLOAD='{"title":"Syslog","global":true,"type":"org.graylog2.inputs.syslog.udp.SyslogUDPInput","configuration":{"bind_address":"0.0.0.0","port":5140,"recv_buffer_size":262144,"override_source":""}}'
GRAYLOG_API="http://127.0.0.1:9000/api/system/inputs"

# --- Wait for Graylog ---
echo "[+] Waiting for Graylog to start..."
sudo systemctl start graylog-server.service && sudo systemctl enable graylog-server.service
sleep 120

# --- Final Output ---
echo "--------------------------------------------------"
echo "Graylog installation complete!"
echo "Access the web UI at: http://<your-server-ip>:9000/"
echo "Login with username: admin and password: admin"
echo "Syslog input added on port 5140"
echo "--------------------------------------------------"
