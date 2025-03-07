#!/bin/bash

# Exit on error and set error trap
set -e
trap 'echo "[!] An error occurred. Exiting..."' ERR

echo "----------------------------------"
echo "Graylog + Data Node Installation via Docker - Ubuntu 24.04 LTS"
echo "----------------------------------"

# Ensure system is up to date
echo "[+] Updating system packages..."
sudo apt update && sudo apt upgrade -y

echo "[+] Installing dependencies..."
sudo apt install -y ca-certificates curl gnupg lsb-release

# Install Docker
echo "[+] Installing Docker..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    sudo systemctl enable --now docker
    sudo usermod -aG docker $USER
    echo "[+] Docker installed. Log out and log back in, or run 'newgrp docker' to apply group changes."
else
    echo "[+] Docker is already installed."
fi

# Generate secure passwords
PASSWORD_SECRET=$(openssl rand -base64 96)
ROOT_PASSWORD_SHA2=$(echo -n "admin" | sha256sum | cut -d" " -f1)
DATANODE_PASSWORD_SECRET=$(openssl rand -base64 96)

# Set up Graylog directory
echo "[+] Setting up Graylog Docker environment..."
mkdir -p ~/graylog && cd ~/graylog

# Create Docker Compose file
cat <<EOF > docker-compose.yml
version: '3.8'

services:
  mongo:
    image: mongo:8.0
    container_name: graylog-mongo
    restart: always
    volumes:
      - mongo_data:/data/db
    environment:
      MONGO_INITDB_DATABASE: graylog
    networks:
      - graylog-net

  opensearch:
    image: opensearchproject/opensearch:2.12.0
    container_name: graylog-opensearch
    restart: always
    environment:
      - discovery.type=single-node
      - cluster.name=graylog
      - node.name=opensearch-node1
      - network.host=0.0.0.0
      - plugins.security.disabled=true
      - OPENSEARCH_JAVA_OPTS=-Xms1g -Xmx1g
    volumes:
      - opensearch_data:/usr/share/opensearch/data
    ulimits:
      memlock:
        soft: -1
        hard: -1
    networks:
      - graylog-net

  graylog-server:
    image: graylog/graylog:6.1
    container_name: graylog-server
    restart: always
    environment:
      - GRAYLOG_PASSWORD_SECRET=${PASSWORD_SECRET}
      - GRAYLOG_ROOT_PASSWORD_SHA2=${ROOT_PASSWORD_SHA2}
      - GRAYLOG_HTTP_BIND_ADDRESS=0.0.0.0:9000
      - GRAYLOG_HTTP_EXTERNAL_URI=http://localhost:9000/
      - GRAYLOG_MONGODB_URI=mongodb://mongo:27017/graylog
      - GRAYLOG_ELASTICSEARCH_HOSTS=http://opensearch:9200
    depends_on:
      - mongo
      - opensearch
    ports:
      - "9000:9000"
      - "1514:1514/udp"
      - "1514:1514/tcp"
    networks:
      - graylog-net
    volumes:
      - graylog_data:/var/lib/graylog-server

  graylog-datanode:
    image: graylog/graylog-datanode:6.1
    container_name: graylog-datanode
    restart: always
    environment:
      - GRAYLOG_DATANODE_PASSWORD_SECRET=${DATANODE_PASSWORD_SECRET}
      - GRAYLOG_DATANODE_OPENSEARCH_HEAP=2g
      - GRAYLOG_DATANODE_MONGODB_URI=mongodb://mongo:27017/graylog
    depends_on:
      - mongo
      - opensearch
      - graylog-server
    networks:
      - graylog-net
    volumes:
      - graylog_datanode:/var/lib/graylog-datanode

volumes:
  mongo_data:
  opensearch_data:
  graylog_data:
  graylog_datanode:

networks:
  graylog-net:
    driver: bridge
EOF

# Start the Graylog stack
echo "[+] Starting Graylog with Docker Compose..."
docker compose up -d

# Wait for Graylog to initialize
until curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:9000/api" | grep -q "200"; do
    echo "[+] Waiting for Graylog API to be available..."
    sleep 10
done

# Final output
echo "--------------------------------------------------"
echo "Graylog + Data Node installation via Docker complete!"
echo "Access the web UI at: http://<your-server-ip>:9000/"
echo "Login with username: admin and password: admin"
echo "--------------------------------------------------"
