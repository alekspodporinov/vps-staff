#!/bin/bash
set -euo pipefail

# wget "https://github.com/alekspodporinov/vps-staff/raw/main/setup.sh" -O setup.sh && sudo chmod +x setup.sh && sudo ./setup.sh

if [ "$(id -u)" -ne 0 ]; then
  echo "This script requires root privileges. Please run as root or use sudo."
  exit 1
fi

# Robust current user detection
CURRENT_USER="${SUDO_USER:-}"
if [ -z "${CURRENT_USER}" ]; then
  CURRENT_USER="$(logname 2>/dev/null || true)"
fi
if [ -z "${CURRENT_USER}" ]; then
  CURRENT_USER="$(whoami)"
fi

echo "Detected user: ${CURRENT_USER}"

# Helper: enable if possible, otherwise start (for static units without [Install])
enable_or_start() {
  local unit="$1"

  if ! systemctl list-unit-files --all | awk '{print $1}' | grep -qx "${unit}"; then
    echo "Unit ${unit} not found (skipping)."
    return 0
  fi

  # "systemctl is-enabled" returns non-zero for disabled/static/etc.
  # So we check UnitFileState for a reliable decision.
  local state
  state="$(systemctl show -p UnitFileState --value "${unit}" 2>/dev/null || true)"

  case "${state}" in
    enabled)
      echo "${unit}: already enabled. Starting/restarting..."
      systemctl start "${unit}" || true
      ;;
    disabled|indirect|generated|masked)
      echo "${unit}: enabling and starting..."
      systemctl enable --now "${unit}"
      ;;
    static)
      echo "${unit}: static (no [Install]). Starting only..."
      systemctl start "${unit}"
      ;;
    *)
      echo "${unit}: state='${state}'. Trying start..."
      systemctl start "${unit}" || true
      ;;
  esac
}

# Add user to sudo group
if id -nG "$CURRENT_USER" | grep -qw "sudo"; then
  echo "User $CURRENT_USER already has sudo privileges."
else
  echo "Adding user $CURRENT_USER to the sudo group..."
  usermod -aG sudo "$CURRENT_USER"
  echo "User $CURRENT_USER has been added to the sudo group."
fi

# Hostname
read -r -p "Enter a new hostname for the server (leave empty to skip): " NEW_HOSTNAME
if [ -n "${NEW_HOSTNAME}" ]; then
  hostnamectl set-hostname "${NEW_HOSTNAME}"
  echo "${NEW_HOSTNAME}" > /etc/hostname

  # safer hosts edit: replace existing 127.0.1.1 line or add it
  if grep -qE '^127\.0\.1\.1' /etc/hosts; then
    sed -i "s/^127\.0\.1\.1.*/127.0.1.1 ${NEW_HOSTNAME}/" /etc/hosts
  else
    echo "127.0.1.1 ${NEW_HOSTNAME}" >> /etc/hosts
  fi

  echo "Hostname has been changed to ${NEW_HOSTNAME}."
else
  echo "No hostname provided. Skipping hostname update."
fi

# Update and install packages first
apt update
apt upgrade -y

apt install -y mc qemu-guest-agent wireguard-tools ufw ca-certificates curl gnupg openssh-server

# Docker installation
apt remove -y docker docker-engine docker.io containerd runc || true

install -m 0755 -d /etc/apt/keyrings
if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
fi

# Set up Docker repository
CODENAME="$(. /etc/os-release && echo "$VERSION_CODENAME")"
ARCH="$(dpkg --print-architecture)"

cat > /etc/apt/sources.list.d/docker.list <<EOF
deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${CODENAME} stable
EOF

apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Enable/start services safely
enable_or_start docker.service
enable_or_start ssh.service
enable_or_start qemu-guest-agent.service

# Add user to docker group
usermod -aG docker "$CURRENT_USER" || true

# SSH Key configuration
echo "Choose SSH configuration:"
echo "0 - Do not import any key (login with password)"
echo "1 - Enter your SSH key manually"
echo "2 - Download the default SSH key (email: aleks.podp.dev@gmail.com)"
read -r -p "Enter your choice (default: 0): " SSH_OPTION
SSH_OPTION=${SSH_OPTION:-0}

SSH_DIR="/home/${CURRENT_USER}/.ssh"
AUTH_KEYS="${SSH_DIR}/authorized_keys"

case "$SSH_OPTION" in
  0)
    echo "No SSH key imported. Login will be available via username and password."
    ;;
  1)
    read -r -p "Enter your SSH public key: " SSH_KEY
    if [ -n "${SSH_KEY}" ]; then
      mkdir -p "${SSH_DIR}"
      # backup existing
      if [ -f "${AUTH_KEYS}" ]; then
        cp -a "${AUTH_KEYS}" "${AUTH_KEYS}.bak.$(date +%s)" || true
      fi
      echo "${SSH_KEY}" > "${AUTH_KEYS}"
      chmod 700 "${SSH_DIR}"
      chmod 600 "${AUTH_KEYS}"
      chown -R "${CURRENT_USER}:${CURRENT_USER}" "${SSH_DIR}"
      echo "SSH key has been added for user ${CURRENT_USER}."
    else
      echo "No SSH key provided. Login will remain via password."
    fi
    ;;
  2)
    echo "Downloading the default SSH public key..."
    mkdir -p "${SSH_DIR}"
    if [ -f "${AUTH_KEYS}" ]; then
      cp -a "${AUTH_KEYS}" "${AUTH_KEYS}.bak.$(date +%s)" || true
    fi
    curl -fsSL "https://github.com/alekspodporinov/vps-staff/raw/main/devap_pbk" -o "${AUTH_KEYS}"
    chmod 700 "${SSH_DIR}"
    chmod 600 "${AUTH_KEYS}"
    chown -R "${CURRENT_USER}:${CURRENT_USER}" "${SSH_DIR}"
    echo "Default SSH public key downloaded and applied."
    ;;
  *)
    echo "Invalid option. No SSH key imported. Login will remain via password."
    ;;
esac

# Firewall configuration
read -r -p "Do you want to enable the firewall (y/n)? " ENABLE_UFW
if [ "${ENABLE_UFW}" = "y" ]; then
  ufw allow OpenSSH
  ufw allow 80/tcp
  ufw allow 443/tcp
  ufw --force enable
  echo "Firewall has been enabled. Ports 80, 443, and SSH are open."
else
  echo "Firewall is not enabled."
fi

# Network configuration (end)
read -r -p "Enter the IP address for ens18 (e.g., 192.168.0.191 or 192.168.0.191/24): " IP_ADDRESS
if ! echo "$IP_ADDRESS" | grep -q "/"; then
  IP_ADDRESS="$IP_ADDRESS/24"
fi

read -r -p "Enter the gateway (default: 192.168.0.1): " GATEWAY
GATEWAY=${GATEWAY:-192.168.0.1}

# Backup existing netplan files (instead of deleting blindly)
mkdir -p /root/netplan-backup
cp -a /etc/netplan/*.yaml /root/netplan-backup/ 2>/dev/null || true

# Write new netplan config
cat > /etc/netplan/01-netcfg.yaml <<EOF
network:
  version: 2
  ethernets:
    ens18:
      dhcp4: false
      addresses:
        - ${IP_ADDRESS}
      routes:
        - to: default
          via: ${GATEWAY}
      nameservers:
        addresses:
          - 8.8.8.8
          - 8.8.4.4
EOF

chmod 600 /etc/netplan/01-netcfg.yaml

echo "Network configuration has been saved to /etc/netplan/01-netcfg.yaml"
echo "Backups saved in /root/netplan-backup/"

echo "System is ready for final steps."
echo "1) Network configuration will be applied"
echo "2) System will be rebooted"
read -r -p "Continue with network changes and reboot? (y/n): " FINAL_CONFIRM

if [ "${FINAL_CONFIRM}" = "y" ]; then
  echo "Applying network configuration..."
  netplan generate
  netplan apply

  echo "Rebooting..."
  reboot
else
  echo "Script finished. Network changes and reboot postponed."
  echo "Apply network changes with: sudo netplan apply"
  echo "Reboot with: sudo reboot"
fi
