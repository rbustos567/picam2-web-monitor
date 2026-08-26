#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

echo "=== Starting Pi Camera Monitor Installation ==="

# 1. Check for root privileges
if [ "$EUID" -ne 0 ]; then
  echo "[-] Please run this script with sudo: sudo ./install.sh"
  exit 1
fi

# Detect the exact absolute directory where install.sh is located
INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CURRENT_USER=${SUDO_USER:-$USER}

echo "[+] Target installation directory: $INSTALL_DIR"

# 2. Update and install system dependencies & Picamera2
echo "[+] Installing system packages and camera libraries..."
apt-get update
apt-get install -y \
    python3-pip \
    python3-picamera2 \
    python3-libcamera \
    libcamera-apps \
    lsof

# 3. Create secure environment configuration file
if [ ! -f /etc/pi_camera.env ]; then
    echo "[+] Creating /etc/pi_camera.env..."
    cp "$INSTALL_DIR/pi_camera.env.example" /etc/pi_camera.env
    chmod 600 /etc/pi_camera.env
    chown root:root /etc/pi_camera.env
else
    echo "[*] /etc/pi_camera.env already exists. Skipping creation."
fi

# 4. Copy and configure systemd service
echo "[+] Configuring systemd service..."
cp "$INSTALL_DIR/camera_monitor.service" /etc/systemd/system/pi_monitor_camera.service

# Adjust user paths in .service if not using the default 'pi' user
sed -i "s|User=pi|User=$CURRENT_USER|g" /etc/systemd/system/pi_monitor_camera.service
sed -i "s|Group=pi|Group=$CURRENT_USER|g" /etc/systemd/system/pi_monitor_camera.service
sed -i "s|/home/pi/pi-camera-monitor|$INSTALL_DIR|g" /etc/systemd/system/pi_monitor_camera.service

# 5. Enable and start the service
echo "[+] Enabling and starting pi_monitor_camera service..."
systemctl daemon-reload
systemctl enable pi_monitor_camera.service
systemctl restart pi_monitor_camera.service

echo "=== Installation Completed Successfully ==="
echo "Check service status with: sudo systemctl status pi_monitor_camera.service"
echo "IMPORTANTE: By default user and pass are: admin/admin. Make sure to edit /etc/pi_camera.env to change them and then restart service: sudo systemctl status pi_monitor_camera.service"
