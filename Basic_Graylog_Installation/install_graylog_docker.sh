#!/bin/bash

set -e  # Exit on error

log() {
    echo "[+] $1"
}

err() {
    echo "[!] $1" >&2
    exit 1
}

log "Graylog Installation (Docker) - Ubuntu 24.04.2 LTS"

# Ensure system is up to date
log "Updating system packages..."
sudo apt update --allow-change-held-packages && sudo apt upgrade -y

log "Installing dependencies..."
sudo apt install -y lsb-release ca-certificates curl gnupg wget unzip

# Install Docker and Docker Compose
log "Installing Docker..."
sudo apt install -y docker.io docker-compose
sudo systemctl enable --now docker

# Detect `docker compose` command format
COMPOSE_CMD=$(command -v docker-compose || echo "docker compose")

# Configure Kernel Parameters
log "Configuring Linux kernel parameters..."
echo "vm.max_map_count=262144" | sudo tee /etc/sysctl.conf > /dev/null
sudo sysctl -w vm.max_map_count=262144

# Create Graylog Directory
GRAYLOG_DIR="$HOME/graylog"
log "Creating Graylog directory at $GRAYLOG_DIR..."
mkdir -p "$GRAYLOG_DIR" && cd "$GRAYLOG_DIR"

# Generate Secrets
log "Generating secrets for Graylog..."
GRAYLOG_SECRET=$(openssl rand -base64 96)
GRAYLOG_ADMIN_PASSWORD=$(echo -n "admin" | sha256sum | awk '{print $1}')

# Create Environment File
log "Configuring environment file..."
cat <<EOF > .env
GRAYLOG_PASSWORD_SECRET=$GRAYLOG_SECRET
GRAYLOG_ROOT_PASSWORD_SHA2=$GRAYLOG_ADMIN_PASSWORD
GRAYLOG_ROOT_EMAIL=admin@example.com
EOF

# Create docker-compose.yml
log "Configuring docker-compose.yml..."
cat <<EOF > docker-compose.yml
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

  graylog:
    image: graylog/graylog:6.1
    container_name: graylog-server
    depends_on:
      - mongo
      - opensearch
    env_file:
      - .env
    environment:
      - GRAYLOG_HTTP_BIND_ADDRESS=0.0.0.0:9000
      - GRAYLOG_HTTP_PUBLISH_URI=http://127.0.0.1:9000/
      - GRAYLOG_ELASTICSEARCH_HOSTS=http://opensearch:9200
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
  mongo_data:
  os_data:
  graylog_data:
EOF

# Start Graylog Stack
log "Starting Graylog stack..."
$COMPOSE_CMD up -d

# Wait for Graylog API
log "Waiting for Graylog API to be ready..."
TIMEOUT=300
ELAPSED=0
while ! curl -s -f -o /dev/null "http://127.0.0.1:9000/api/system/inputs"; do
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    if [ $ELAPSED -ge $TIMEOUT ]; then
        err "Timeout waiting for Graylog API!"
    fi
    log "Graylog API not ready yet, retrying..."
done

# Configure Syslog Input
log "Adding Syslog input..."
curl -X POST "http://127.0.0.1:9000/api/system/inputs" \
     -u "admin:admin" \
     -H "Content-Type: application/json" \
     -d '{"title":"Syslog","global":true,"type":"org.graylog2.inputs.syslog.udp.SyslogUDPInput","configuration":{"bind_address":"0.0.0.0","port":5140,"recv_buffer_size":262144,"override_source":""}}' \
     || log "Failed to create Syslog input!"

log "Installation complete! Access Graylog at: http://<your-server-ip>:9000/ (admin/admin)"
