#!/bin/bash

# Exit on error
set -e

echo "----------------------------------"
echo "Removing Graylog, MongoDB, and OpenSearch"
echo "----------------------------------"

# --- Stop All Services ---
echo "[+] Stopping services..."
sudo systemctl stop graylog-server || true
sudo systemctl stop opensearch || true
sudo systemctl stop mongod || true

echo "[+] Unholding services..."
sudo apt-mark unhold graylog-server mongodb-org opensearch

# --- Remove All Installed Packages ---
echo "[+] Removing installed packages..."
sudo apt remove --purge -y graylog-server mongodb-org opensearch || true
sudo apt autoremove -y || true

# --- Delete Configuration & Data ---
echo "[+] Deleting configuration and data files..."
sudo rm -rf /etc/graylog /var/lib/graylog-server /var/log/graylog-server
sudo rm -rf /etc/mongodb /var/lib/mongodb /var/log/mongodb
sudo rm -rf /etc/opensearch /var/lib/opensearch /var/log/opensearch

# --- Remove Repositories ---
echo "[+] Removing repositories..."
sudo rm -f /etc/apt/sources.list.d/graylog.list
sudo rm -f /etc/apt/sources.list.d/mongodb-org-*.list
sudo rm -f /etc/apt/sources.list.d/opensearch-*.list

# --- Update Package List ---
echo "[+] Updating package lists..."
sudo apt update

# --- Done ---
echo "----------------------------------"
echo "Removal finished. Please reboot system now"
echo "----------------------------------"
