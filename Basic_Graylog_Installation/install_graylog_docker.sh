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

# --- Install Docker and Docker Compose ---
echo "[+] Installing Docker..."
sudo apt install -y docker.io docker-compose
sudo systemctl enable --now docker

# Detect whether to use docker-compose or docker compose
if command -v docker-compose &> /dev/null; then
    COMPOSE_CMD="docker-compose"
else
    COMPOSE_CMD="docker compose"
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
touch "$ENV_FILE"

append_if_missing() {
    local key=$1
    local value=$2
    local file=$3
    grep -q "^$key=" "$file" || echo "$key=$value" | sudo tee -a "$file" > /dev/null
}

append_if_missing "GRAYLOG_PASSWORD_SECRET" "$GRAYLOG_SECRET" "$ENV_FILE"
append_if_missing "GRAYLOG_ROOT_PASSWORD_SHA2" "$GRAYLOG_ADMIN_PASSWORD" "$ENV_FILE"
append_if_missing "GRAYLOG_ROOT_EMAIL" "admin@example.com" "$ENV_FILE"

# --- Create or Update docker-compose.yml ---
echo "[+] Configuring docker-compose.yml..."
COMPOSE_FILE="docker-compose.yml"
touch "$COMPOSE_FILE"

append_yaml_if_missing() {
    local key=$1
    local value=$2
    local file=$3
    grep -q "^[[:space:]]*$key:" "$file" || echo "$key: $value" | sudo tee -a "$file" > /dev/null
}

append_yaml_if_missing "version" "'3.8'" "$COMPOSE_FILE"
append_yaml_if_missing "services" "" "$COMPOSE_FILE"

# Append service definitions safely
if ! grep -q "mongo:" "$COMPOSE_FILE"; then
    sudo tee -a "$COMPOSE_FILE" > /dev/null <<EOF
  mongo:
    image: mongo:6.0
    container_name: graylog-mongo
    restart: unless-stopped
    volumes:
      - mongo_data:/data/db
    networks:
      - graylog-net
EOF
fi

if ! grep -q "opensearch:" "$COMPOSE_FILE"; then
    sudo tee -a "$COMPOSE_FILE" > /dev/null <<EOF
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
EOF
fi

if ! grep -q "graylog:" "$COMPOSE_FILE"; then
    sudo tee -a "$COMPOSE_FILE" > /dev/null <<EOF
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
      - GRAYLOG_ELASTICSEARCH_HOSTS=http://opensearch:9200
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
EOF
fi

# Ensure networks and volumes are properly defined
append_yaml_if_missing "networks" "" "$COMPOSE_FILE"
append_yaml_if_missing "graylog-net" "driver: bridge" "$COMPOSE_FILE"

append_yaml_if_missing "volumes" "" "$COMPOSE_FILE"
append_yaml_if_missing "mongo_data" "{}" "$COMPOSE_FILE"
append_yaml_if_missing "os_data" "{}" "$COMPOSE_FILE"
append_yaml_if_missing "graylog_data" "{}" "$COMPOSE_FILE"
append_yaml_if_missing "datanode_data" "{}" "$COMPOSE_FILE"

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
GRAYLOG_INPUT_PAYLOAD='{"title":"Syslog","global":true,"type":"org.graylog2.inputs.syslog.udp.SyslogUDPInput","configuration":{"bind_address":"0.0.0.0","port":5140,"recv_buffer_size":262144,"override_source":""}}'
GRAYLOG_API="http://127.0.0.1:9000/api/system/inputs"

curl -X POST "$GRAYLOG_API" -u "admin:admin" -H "Content-Type: application/json" -d "$GRAYLOG_INPUT_PAYLOAD" || echo "[!] Failed to create Syslog input!"

echo "[+] Done!"
echo "--------------------------------------------------"
echo "Graylog + Data Node installation complete!"
echo "Access the web UI at: http://<your-server-ip>:9000/"
echo "Login with username: admin and password: admin"
echo "Syslog input added on port 5140"
echo "--------------------------------------------------"
