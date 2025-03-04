# Graylog Auto Installer - Ubuntu Server 24.04.2 LTS

This script fully automates the installation of **Graylog 6.0** on **Ubuntu Server 24.04.2 LTS**.  
It installs and configures **MongoDB 7.0**, **OpenSearch 2.15**, and **Graylog**, ensuring all services start on boot.

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

## System Services & Maintenance

###Restart Services
```bash
sudo systemctl restart graylog-server
sudo systemctl restart opensearch
sudo systemctl restart mongod
```

### Check Logs
```bash
sudo journalctl -u graylog-server -f
```

### Uninstall (If Needed)
If you want to completely remove Graylog and its dependencies:
```bash
sudo systemctl stop graylog-server opensearch mongod
sudo apt remove --purge -y graylog-server mongodb-org opensearch
sudo rm -rf /var/lib/mongodb /var/lib/opensearch /var/lib/graylog-server
sudo rm -rf /etc/graylog /etc/opensearch /etc/mongod.conf
```

### Troubleshooting
Check logs:

```bash
sudo journalctl -u graylog-server -f
```

Web UI Not Accessible?
Ensure Graylog is bound to 0.0.0.0 in /etc/graylog/server/server.conf:

```ini
http_bind_address = 0.0.0.0:9000
```

Restart:
```bash
sudo systemctl restart graylog-server
```

No Logs in Graylog?
- Ensure syslog is sending data:
```bash
sudo systemctl status rsyslog
```
- Verify Graylog input exists under System > Inputs.
