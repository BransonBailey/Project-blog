#!/bin/bash

# Exit on error
set -e

echo "----------------------------------"
echo "Graylog Installation - Ubuntu 24.04.2 LTS (Docker)"
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

# Detect whether to use `docker-compose` or `docker compose`
if command -v docker-compose &> /dev/null; then
    COMPOSE_CMD="docker-compose"
else
    COMPOSE_CMD="docker compose"
fi

# --- Create Graylog Docker Directory ---
echo "[+] Creating Graylog directory..."
mkdir -p ~/graylog && cd ~/graylog

# --- Generate Secrets ---
echo "[+] Generating secrets for Graylog..."
GRAYLOG_SECRET=$(openssl rand -base64 96)
GRAYLOG_ADMIN_PASSWORD=$(echo -n "admin" | sha256sum | cut -d " " -f1)

# --- Create Environment File ---
echo "[+] Configuring environment file..."
ENV_FILE=".env"
if [ ! -f "$ENV_FILE" ]; then
    touch "$ENV_FILE"
fi
sudo sed -i '/^GRAYLOG_PASSWORD_SECRET/d' "$ENV_FILE"
sudo sed -i '/^GRAYLOG_ROOT_PASSWORD_SHA2/d' "$ENV_FILE"

sudo bash -c "cat <<EOF >> $ENV_FILE
GRAYLOG_PASSWORD_SECRET=${GRAYLOG_SECRET}
GRAYLOG_ROOT_PASSWORD_SHA2=${GRAYLOG_ADMIN_PASSWORD}
EOF"

# --- Create docker-compose.yml ---
echo "[+] Configuring docker-compose.yml..."
COMPOSE_FILE="docker-compose.yml"
if [ ! -f "$COMPOSE_FILE" ]; then
    touch "$COMPOSE_FILE"
fi

sudo bash -c "cat <<EOF > $COMPOSE_FILE
version: '3.8'
services:
  mongo:
    image: mongo:6.0
    container_name: graylog-mongo
    restart: unless-stopped
    volumes:
      - mongo_data:/data/db

  opensearch:
    image: opensearchproject/opensearch:2
    container_name: graylog-opensearch
    environment:
      - discovery.type=single-node
      - plugins.security.disabled=true
      - bootstrap.memory_lock=true
    volumes:
      - os_data:/usr/share/opensearch/data
    ulimits:
      memlock:
        soft: -1
        hard: -1
    ports:
      - "9200:9200"

  graylog:
    image: graylog/graylog:6.0
    container_name: graylog-server
    depends_on:
      - mongo
      - opensearch
    env_file:
      - .env
    environment:
      - GRAYLOG_HTTP_BIND_ADDRESS=0.0.0.0:9000
      - GRAYLOG_ELASTICSEARCH_HOSTS=http://opensearch:9200
    ports:
      - "9000:9000"
      - "5140:5140/udp"
      - "1514:1514"
    restart: unless-stopped

volumes:
  mongo_data:
  os_data:
EOF"

# --- Start Graylog Stack ---
echo "[+] Starting Graylog stack..."
$COMPOSE_CMD up -d

# --- Wait for Graylog API ---
echo "[+] Waiting for Graylog API..."
until curl -s -f -o /dev/null "http://127.0.0.1:9000/api/system/inputs"; do
    sleep 5
    echo "[!] Graylog API not ready yet, retrying..."
done

echo "[+] Done!"
echo "--------------------------------------------------"
echo "Graylog installation complete!"
echo "Access the web UI at: http://<your-server-ip>:9000/"
echo "Login with username: admin and password: admin"
echo "Syslog input added on port 5140"
echo "--------------------------------------------------"
