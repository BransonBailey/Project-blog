# Graylog Auto Installer - Ubuntu Server 24.04.2 LTS

This script fully automates the installation of **Graylog 6.0** on **Ubuntu Server 24.04.2 LTS**.  
It installs and configures **Docker**, **MongoDB**, **OpenSearch**, and **Graylog**, ensuring all services start on boot.

## Features
- **Fully automated setup** of Graylog and its dependencies.
- **Secures installation** with generated secrets.
- **Prevents unintended upgrades** of key components.
- **Automatically configures a Syslog UDP input** (port `5140`).
- **Optimizes OpenSearch memory settings**.

---

## Requirements
- A fresh installation of **Ubuntu Server 24.04.2 LTS**.
- At least **4GB RAM** (8GB recommended).
- Root or sudo privileges.

---

## Installation

### 1. **Download the script**
```bash
wget https://raw.githubusercontent.com/BransonBailey/Project-blog/refs/heads/main/Basic_Graylog_Installation/install_graylog.sh
```
### 2. Make it executable
```bash
chmod +x install_graylog.sh
```
### 3. Run the script
```bash
sudo ./install_graylog.sh
```

---

## Post Installation

### Access the Graylog Web Interface
http://<your-server-ip>:9000

- Username: admin
- Password: admin (Change this!!!)

---

## System Services & Maintenance (Docker)

### Restart Services
To restart Graylog, OpenSearch, or MongoDB in Docker:
```bash
docker restart graylog-server
docker restart graylog-opensearch
docker restart graylog-mongo
```

To restart all at once:
```bash
docker-compose restart
```
or if using the new Docker CLI:
```bash
docker compose restart
```

### Check Logs
View logs for each service:
```bash
docker logs -f graylog-server
docker logs -f graylog-opensearch
docker logs -f graylog-mongo
```

## Uninstall (If Needed)
If you want to completely remove Graylog, OpenSearch, and MongoDB, along with all stored data:
```bash
cd ~/graylog
docker-compose down -v  # Stops and removes all containers, volumes, and networks
rm -rf ~/graylog        # Deletes configuration and docker-compose files
```
**Warning: This will delete all logs and configurations.**

---

## Troubleshooting

### Web UI Not Accessible?
Check if the Graylog container is running:
```bash
docker ps | grep graylog-server
```
If not, restart it:
```bash
docker restart graylog-server
```

Ensure Graylog is bound to 0.0.0.0 inside docker-compose.yml:
```yaml
environment:
  - GRAYLOG_HTTP_BIND_ADDRESS=0.0.0.0:9000
```
Apply changes:
```bash
docker-compose up -d --force-recreate
```

### No Logs in Graylog?
Ensure syslog is sending data:
```bash
sudo systemctl status rsyslog
```

Verify Graylog input exists under System > Inputs in the web UI.

Check if Graylog is receiving logs:
```bash
docker logs -f graylog-server | grep "received message"
```
