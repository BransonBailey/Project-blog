#!/bin/bash

# Exit on error
set -e
echo "----------------------------------"
echo "Graylog Installation - Ubuntu 24.04.2 LTS"
echo "----------------------------------"

# Ensure system is up to date
echo "[+] Updating system packages..."
sudo apt update --allow-change-held-packages && sudo apt upgrade -y

echo "[+] Installing dependencies..."
sudo apt install -y lsb-release ca-certificates curl gnupg gnupg2 wget openjdk-17-jdk uuid-runtime pwgen

# Set timezone to UTC
echo "[+] Setting timezone to UTC..."
sudo timedatectl set-timezone UTC


echo "[+] Detecting CPU & Installing Compatible MongoDB Version"

# --- Detect CPU Features ---
CPU_FLAGS=$(grep -o -m1 -E 'avx|sse4_2' /proc/cpuinfo || echo "none")

if echo "$CPU_FLAGS" | grep -q "avx"; then
    MONGO_VERSION="7.0"
    GRAYLOG_VERSION="6.0"
elif echo "$CPU_FLAGS" | grep -q "sse4_2"; then
    MONGO_VERSION="5.0"
    GRAYLOG_VERSION="6.0"
else
    MONGO_VERSION="4.4"
    GRAYLOG_VERSION="5.1"
fi

echo "[+] Detected CPU supports MongoDB $MONGO_VERSION and Graylog $GRAYLOG_VERSION"

# --- Remove Old MongoDB Versions ---
echo "[+] Removing any previous MongoDB versions..."
sudo systemctl stop mongod || true
sudo apt remove --purge -y mongodb-org || true
sudo rm -rf /var/lib/mongodb /etc/mongod.conf /var/log/mongodb || true

# --- Add MongoDB Repository ---
echo "[+] Adding MongoDB $MONGO_VERSION repository..."
if [ "$MONGO_VERSION" == "7.0" ]; then
    curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | sudo gpg -o /etc/apt/keyrings/mongodb-server-7.0.gpg --dearmor
    echo "deb [ signed-by=/etc/apt/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/debian bookworm/mongodb-org/7.0 main" | sudo tee /etc/apt/sources.list.d/mongodb-org-7.0.list
elif [ "$MONGO_VERSION" == "5.0" ]; then
    curl -fsSL https://www.mongodb.org/static/pgp/server-5.0.asc | sudo gpg -o /etc/apt/keyrings/mongodb-server-5.0.gpg --dearmor
    echo "deb [ signed-by=/etc/apt/keyrings/mongodb-server-5.0.gpg ] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/5.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-5.0.list
else
    curl -fsSL https://www.mongodb.org/static/pgp/server-4.4.asc | sudo gpg -o /etc/apt/keyrings/mongodb-server-4.4.gpg --dearmor
    echo "deb [ signed-by=/etc/apt/keyrings/mongodb-server-4.4.gpg ] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/4.4 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-4.4.list
fi

# --- Install MongoDB ---
echo "[+] Updating package lists..."
sudo apt update

echo "[+] Installing MongoDB $MONGO_VERSION..."
sudo apt install -y mongodb-org

# --- Fix MongoDB Permissions ---
echo "[+] Fixing MongoDB permissions..."
sudo mkdir -p /var/lib/mongodb
sudo chown -R mongodb:mongodb /var/lib/mongodb
sudo chmod -R 755 /var/lib/mongodb

# --- Start MongoDB ---
echo "[+] Starting and enabling MongoDB service..."
sudo systemctl enable --now mongod

# --- Wait for MongoDB to Start ---
echo "[+] Waiting for MongoDB to be fully initialized..."
until sudo systemctl is-active --quiet mongod; do
    sleep 5
    echo "[!] Waiting for MongoDB to start..."
done

echo "[+] MongoDB $MONGO_VERSION installed and running!"

# --- Install OpenSearch 2.15 ---
echo "[+] Adding OpenSearch repository..."
curl -o- https://artifacts.opensearch.org/publickeys/opensearch.pgp | sudo gpg --dearmor --batch --yes -o /etc/apt/keyrings/opensearch-keyring
echo "deb [signed-by=/etc/apt/keyrings/opensearch-keyring] https://artifacts.opensearch.org/releases/bundle/opensearch/2.x/apt stable main" | sudo tee /etc/apt/sources.list.d/opensearch-2.x.list

echo "[+] Installing OpenSearch 2.15..."
sudo OPENSEARCH_INITIAL_ADMIN_PASSWORD=$(openssl rand -base64 32) apt install -y opensearch=2.15.0

echo "[+] Preventing OpenSearch upgrades..."
sudo apt-mark hold opensearch

echo "[+] Configuring OpenSearch..."
sudo bash -c 'cat <<EOF > /etc/opensearch/opensearch.yml
cluster.name: graylog
node.name: $(hostname)
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
echo "[+] Determining correct version of Graylog..."
if [ "$MONGO_VERSION" == "4.4" ]; then
    GRAYLOG_VERSION="5.1"
else
    GRAYLOG_VERSION="6.0"
fi
echo "[+] Will install Graylog $GRAYLOG_VERSION..."

if [ "$GRAYLOG_VERSION" == "6.0" ]; then
    wget https://packages.graylog2.org/repo/packages/graylog-6.0-repository_latest.deb
    sudo dpkg -i graylog-6.0-repository_latest.deb
else
    wget https://packages.graylog2.org/repo/packages/graylog-5.1-repository_latest.deb
    sudo dpkg -i graylog-5.1-repository_latest.deb
fi

echo "[+] Installing Graylog $GRAYLOG_VERSION..."
sudo apt update --allow-change-held-packages && sudo apt install -y graylog-server

echo "[+] Generating secrets..."
GRAYLOG_SECRET=$(openssl rand -base64 96)
GRAYLOG_ADMIN_PASSWORD=$(echo -n "admin" | sha256sum | cut -d" " -f1)

echo "[+] Configuring Graylog..."
sudo bash -c "cat <<EOF > /etc/graylog/server/server.conf
password_secret = $GRAYLOG_SECRET
root_password_sha2 = $GRAYLOG_ADMIN_PASSWORD
root_email = admin@example.com
http_bind_address = 0.0.0.0:9000
elasticsearch_hosts = http://127.0.0.1:9200
transport_email_enabled = false
EOF"

echo "[+] Starting and enabling Graylog service..."
sudo systemctl enable --now graylog-server

echo "[+] Preventing package upgrades..."
sudo apt-mark hold mongodb-org graylog-server

# --- Configure Syslog Input ---
echo "[+] Configuring Syslog UDP input..."
GRAYLOG_INPUT_PAYLOAD='{"title":"Syslog","global":true,"type":"org.graylog2.inputs.syslog.udp.SyslogUDPInput","configuration":{"bind_address":"0.0.0.0","port":5140,"recv_buffer_size":262144,"override_source":""}}'
GRAYLOG_API="http://127.0.0.1:9000/api/system/inputs"

# Wait for Graylog to be fully initialized before creating inputs
echo "[+] Waiting for Graylog to start..."
sudo systemctl start graylog-server.service && sudo systemctl enable graylog-server.service
sleep 120

echo "[+] Adding Syslog input..."
curl -X POST "$GRAYLOG_API" -u "admin:admin" -H "Content-Type: application/json" -d "$GRAYLOG_INPUT_PAYLOAD"

# --- Final Output ---
echo "--------------------------------------------------"
echo "Graylog installation complete!"
echo "Access the web UI at: http://<your-server-ip>:9000/"
echo "Login with username: admin and password: admin"
echo "Syslog input added on port 5140"
echo "--------------------------------------------------"
