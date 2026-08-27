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

# 2.1 Update and install system dependencies & Picamera2
echo "[+] Installing system packages and camera libraries..."
apt-get update
apt-get install -y \
    python3-pip \
    python3-picamera2 \
    python3-libcamera \
    libcamera-apps \
    lsof

# 2.2 Optional Tailscale Installation
if ! command -v tailscale &> /dev/null; then
    echo "[+] Tailscale not found. Installing Tailscale for secure remote access..."
    curl -fsSL https://tailscale.com/install.sh | sh
    echo "[!] Tailscale installed. You will need to run 'sudo tailscale up' to authenticate this device."
else
    echo "[*] Tailscale is already installed. Skipping installation."
fi

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

# 7. Fetch Local IP and Tailscale IP (if available)
LOCAL_IP=$(hostname -I | awk '{print $1}')
TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "")

echo ""
echo "=========================================================="
echo "   Installation Completed Successfully!"
echo "=========================================================="
echo " Local Network Access:"
echo "    http://${LOCAL_IP}:8080"

if [ -n "$TAILSCALE_IP" ]; then
  echo ""
  echo " Remote Access (via Tailscale):"
  echo "    http://${TAILSCALE_IP}:8080"
else
  echo ""
  echo " Remote Access (Tailscale installed but not authenticated):"
  echo "    Run 'sudo tailscale up' to link your Tailscale account,"
  echo "    then re-run this script or check your Tailscale IP."
fi

echo ""
echo " Note: Edit /etc/pi_camera.env to update your credentials."
echo "=========================================================="
