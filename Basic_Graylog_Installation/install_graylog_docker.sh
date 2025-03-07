#!/bin/bash

# Exit on error
set -e

echo "----------------------------------"
echo "Graylog Installation (Docker) - Ubuntu 24.04.2 LTS"
echo "----------------------------------"

# Ensure system is up to date
echo "[+] Updating system packages..."
sudo apt update --allow-change-held-packages && sudo apt upgrade -y

echo "[+] Installing dependencies..."
sudo apt install -y lsb-release ca-certificates curl gnupg gnupg2 wget unzip

# --- Install Docker ---
echo "[+] Installing Docker..."
sudo apt install -y docker.io
sudo systemctl enable --now docker

# --- Install Docker Compose Manually (If Missing) ---
if ! docker compose version &> /dev/null; then
    echo "[+] Installing Docker Compose..."
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose || true
fi

# Detect whether to use `docker compose`
if docker compose version &> /dev/null; then
    COMPOSE_CMD="docker compose"
elif docker-compose version &> /dev/null; then
    COMPOSE_CMD="docker-compose"
else
    echo "[!] Docker Compose installation failed!"
    exit 1
fi

# --- Configure Kernel Parameters ---
echo "[+] Configuring Linux kernel parameters..."
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
sudo sysctl -w vm.max_map_count=262144

# --- Create Graylog Docker Directory ---
echo "[+] Creating Graylog directory..."
mkdir -p ~/graylog && cd ~/graylog

# --- Generate Secrets ---
echo "[+] Generating secrets for Graylog..."
GRAYLOG_SECRET=$(openssl rand -base64 96)
GRAYLOG_ADMIN_PASSWORD=$(echo -n "admin" | sha256sum | cut -d " " -f1)

# --- Create or Update Environment File ---
echo "[+] Configuring environment file..."
ENV_FILE=".env"
sudo touch "$ENV_FILE"

append_if_missing() {
    local key=$1
    local value=$2
    local file=$3
    sudo grep -q "^$key=" "$file" || echo "$key=$value" | sudo tee -a "$file" > /dev/null
}

append_if_missing "GRAYLOG_PASSWORD_SECRET" "$GRAYLOG_SECRET" "$ENV_FILE"
append_if_missing "GRAYLOG_ROOT_PASSWORD_SHA2" "$GRAYLOG_ADMIN_PASSWORD" "$ENV_FILE"
append_if_missing "GRAYLOG_ROOT_EMAIL" "admin@example.com" "$ENV_FILE"

# --- Create or Update docker-compose.yml ---
echo "[+] Configuring docker-compose.yml..."
COMPOSE_FILE="docker-compose.yml"
sudo tee "$COMPOSE_FILE" > /dev/null <<EOF
version: '3.8'
services:
  mongo:
    image: mongo:6.0
    container_name: graylog-mongo
    restart: unless-stopped
    volumes:
      - mongo_data:/data/db
    networks:
      - graylog-net

  opensearch:
    image: opensearchproject/opensearch:2
    container_name: graylog-opensearch
    environment:
      - discovery.type=single-node
      - plugins.security.disabled=true
      - bootstrap.memory_lock=true
      - cluster.name=graylog
      - action.auto_create_index=false
    volumes:
      - os_data:/usr/share/opensearch/data
    ulimits:
      memlock:
        soft: -1
        hard: -1
    networks:
      - graylog-net
    ports:
      - "9200:9200"

  datanode:
    image: graylog/graylog-datanode:6.1
    container_name: graylog-datanode
    environment:
      - GRAYLOG_DATANODE_NODE_ID=default
      - GRAYLOG_DATANODE_OPENSEARCH_URI=http://opensearch:9200
      - GRAYLOG_DATANODE_MONGODB_URI=mongodb://mongo:27017/graylog
      - GRAYLOG_DATANODE_HTTP_BIND_ADDRESS=0.0.0.0:8999
      - GRAYLOG_DATANODE_HTTP_PUBLISH_URI=http://127.0.0.1:8999/
    ports:
      - "8999:8999"
    restart: unless-stopped
    networks:
      - graylog-net
    volumes:
      - datanode_data:/var/lib/graylog-datanode

  graylog:
    image: graylog/graylog:6.1
    container_name: graylog-server
    depends_on:
      - mongo
      - opensearch
      - datanode
    env_file:
      - .env
    environment:
      - GRAYLOG_HTTP_BIND_ADDRESS=0.0.0.0:9000
      - GRAYLOG_HTTP_PUBLISH_URI=http://127.0.0.1:9000/
      - GRAYLOG_ELASTICSEARCH_HOSTS=http://datanode:8999
      - GRAYLOG_TRANSPORT_EMAIL_ENABLED=false
      - GRAYLOG_MONGODB_URI=mongodb://mongo:27017/graylog
      - GRAYLOG_DATA_DIR=/var/lib/graylog-server
    ports:
      - "9000:9000"
      - "5140:5140/udp"
      - "1514:1514"
    restart: unless-stopped
    networks:
      - graylog-net
    volumes:
      - graylog_data:/var/lib/graylog-server

networks:
  graylog-net:
    driver: bridge

volumes:
  mongo_data: {}
  os_data: {}
  graylog_data: {}
  datanode_data: {}
EOF

# --- Start Graylog Stack ---
echo "[+] Starting Graylog stack..."
$COMPOSE_CMD up -d

# --- Wait for Graylog API ---
echo "[+] Waiting for Graylog API..."
TIMEOUT=300  # Max wait time: 5 minutes
ELAPSED=0
while ! curl -s -f -o /dev/null "http://127.0.0.1:9000/api/system/inputs"; do
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    if [ $ELAPSED -ge $TIMEOUT ]; then
        echo "[!] Timeout waiting for Graylog API!"
        exit 1
    fi
    echo "[!] Graylog API not ready yet, retrying..."
done

# --- Configure Syslog Input ---
echo "[+] Adding Syslog input..."
GRAYLOG_INPUT_PAYLOAD='{
  "title": "Syslog",
  "global": true,
  "type": "org.graylog2.inputs.syslog.udp.SyslogUDPInput",
  "configuration": {
    "bind_address": "0.0.0.0",
    "port": 5140,
    "recv_buffer_size": 262144,
    "override_source": ""
  }
}'

GRAYLOG_API="http://127.0.0.1:9000/api/system/inputs"
curl -X POST "$GRAYLOG_API" -u "admin:admin" -H "Content-Type: application/json" -d "$GRAYLOG_INPUT_PAYLOAD" || echo "[!] Failed to create Syslog input!"

echo "[+] Done!"
echo "--------------------------------------------------"
echo "Graylog installation complete!"
echo "Access the web UI at: http://<your-server-ip>:9000/"
echo "Login with username: admin and password: admin"
echo "Syslog input added on port 5140"
echo "--------------------------------------------------"
