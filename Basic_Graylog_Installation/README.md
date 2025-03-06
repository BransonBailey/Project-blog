# Graylog Auto Installer - Ubuntu Server 24.04.2 LTS

These scripts fully automate the installation of Graylog 6.0 on Ubuntu Server 24.04.2 LTS.
There are two versions available: ```install_graylog.sh``` and ```install_graylog_docker.sh```.
As their names suggest, one installs and configures MongoDB, OpenSearch, and Graylog, ensuring all services start on boot. The other installs and configures MongoDB, OpenSearch, and Graylog in Docker, managing dependancies and container links.

## Features
- Fully automated setup of Graylog and its dependencies.
- Secures installation with generated secrets.
- Prevents unintended upgrades of key components.
- Automatically configures a Syslog UDP input (port 5140).
- Optimizes OpenSearch memory settings.

## Requirements
- A fresh installation of Ubuntu Server 24.04.2 LTS.
- At least 4GB RAM (8GB recommended).
- Root or sudo privileges.

## Installation
### Docker-based Installation
1. **Download the script**  
   ```bash
   wget https://raw.githubusercontent.com/BransonBailey/Project-blog/refs/heads/main/Basic_Graylog_Installation/install_graylog.sh
   ```
2. **Make it executable**  
   ```bash
   chmod +x install_graylog.sh
   ```
3. **Run the script**  
   ```bash
   sudo ./install_graylog.sh
   ```

### Alternative Installation (Non-Docker Version)
This installation sets up Graylog, MongoDB, and OpenSearch directly on the system rather than using Docker containers.

1. **Download the alternative installation script**  
   ```bash
   wget https://raw.githubusercontent.com/BransonBailey/Project-blog/refs/heads/main/Basic_Graylog_Installation/alt_install.sh
   ```
2. **Make it executable**  
   ```bash
   chmod +x alt_install.sh
   ```
3. **Run the script**  
   ```bash
   sudo ./alt_install.sh
   ```

## Post Installation
### Access the Graylog Web Interface
- URL: `http://<your-server-ip>:9000`
- Username: `admin`
- Password: `admin` (Change this immediately!)

### System Services & Maintenance
#### Docker Version
To restart Graylog, OpenSearch, or MongoDB in Docker:
```bash
docker restart graylog-server
docker restart graylog-opensearch
docker restart graylog-mongo
```
To restart all at once:
```bash
docker compose restart
```
#### Alternative (Non-Docker) Version
To restart Graylog, OpenSearch, or MongoDB:
```bash
sudo systemctl restart graylog-server
sudo systemctl restart opensearch
sudo systemctl restart mongod
```
To enable them at startup:
```bash
sudo systemctl enable graylog-server opensearch mongod
```

### Check Logs
#### Docker Version
```bash
docker logs -f graylog-server
docker logs -f graylog-opensearch
docker logs -f graylog-mongo
```
#### Alternative (Non-Docker) Version
```bash
sudo journalctl -u graylog-server -f
sudo journalctl -u opensearch -f
sudo journalctl -u mongod -f
```

## Uninstall (If Needed)
### Docker Version
```bash
cd ~/graylog
docker-compose down -v  # Stops and removes all containers, volumes, and networks
rm -rf ~/graylog        # Deletes configuration and docker-compose files
```
**Warning:** This will delete all logs and configurations.

### Alternative (Non-Docker) Version
```bash
sudo systemctl stop graylog-server opensearch mongod
sudo apt remove --purge -y graylog-server opensearch mongodb-org
sudo rm -rf /var/lib/graylog-server /var/lib/opensearch /var/lib/mongodb
sudo rm -rf /etc/graylog /etc/opensearch /etc/mongod.conf
```

## Troubleshooting
### Web UI Not Accessible?
Check if the Graylog service is running:
#### Docker Version
```bash
docker ps | grep graylog-server
```
If not, restart it:
```bash
docker restart graylog-server
```
#### Alternative (Non-Docker) Version
```bash
sudo systemctl status graylog-server
```
If it's inactive, restart it:
```bash
sudo systemctl restart graylog-server
```

Ensure Graylog is bound to `0.0.0.0` inside `server.conf`:
```bash
grep "http_bind_address" /etc/graylog/server/server.conf
```
It should be:
```
http_bind_address = 0.0.0.0:9000
```
Apply changes:
```bash
sudo systemctl restart graylog-server
```

### No Logs in Graylog?
Ensure syslog is sending data:
```bash
sudo systemctl status rsyslog
```
Verify Graylog input exists under **System > Inputs** in the web UI.

Check if Graylog is receiving logs:
#### Docker Version
```bash
docker logs -f graylog-server | grep "received message"
```
#### Alternative (Non-Docker) Version
```bash
sudo journalctl -u graylog-server -f | grep "received message"
```
