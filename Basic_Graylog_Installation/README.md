# Graylog Auto Installer - Ubuntu Server 24.04.2 LTS

This script fully automates the installation of Graylog 6.0 on Ubuntu Server 24.04.2 LTS, installing and configuring MongoDB, OpenSearch, and Graylog.

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

1. **Download the alternative installation script**  
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

## Post Installation
### Access the Graylog Web Interface
- URL: `http://<your-server-ip>:9000`
- Username: `admin`
- Password: `admin` (Change this immediately!)

### System Services & Maintenance

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
```bash
sudo journalctl -u graylog-server -f
sudo journalctl -u opensearch -f
sudo journalctl -u mongod -f
```

## Uninstall (If Needed)

**Warning:** This will delete all logs and configurations.
```bash
sudo systemctl stop graylog-server opensearch mongod
sudo apt remove --purge -y graylog-server opensearch mongodb-org
sudo rm -rf /var/lib/graylog-server /var/lib/opensearch /var/lib/mongodb
sudo rm -rf /etc/graylog /etc/opensearch /etc/mongod.conf
```

## Troubleshooting
### Web UI Not Accessible?
Check if the Graylog service is running:
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
```bash
sudo journalctl -u graylog-server -f | grep "received message"
```
