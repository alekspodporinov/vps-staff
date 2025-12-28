!/bin/bash

#wget "https://dev.azure.com/alekspodpdev-open/Sandbox/_apis/git/repositories/bash-scripts/items?path=/setup/setup.sh&version=main&download=true" -O setup.sh && sudo chmod +x setup>

if [ "$(id -u)" -ne 0 ]; then
 echo "This script requires root privileges. Please run as root or use sudo."
 exit 1
fi

CURRENT_USER=$(logname)

# Add user to sudo and root groups
if groups "$CURRENT_USER" | grep -qw "sudo"; then
 echo "User $CURRENT_USER already has sudo privileges."
else
 echo "Adding user $CURRENT_USER to the sudo group..."
 usermod -aG sudo "$CURRENT_USER"
 echo "User $CURRENT_USER has been added to the sudo group."
fi

if groups "$CURRENT_USER" | grep -qw "root"; then
 echo "User $CURRENT_USER already has root privileges."
else
 echo "Adding user $CURRENT_USER to the root group..."
 usermod -aG root "$CURRENT_USER"
 echo "User $CURRENT_USER has been added to the root group."
fi

read -p "Enter a new hostname for the server: " NEW_HOSTNAME
if [ -n "$NEW_HOSTNAME" ]; then
 hostnamectl set-hostname "$NEW_HOSTNAME"
 echo "$NEW_HOSTNAME" | tee /etc/hostname > /dev/null
 sed -i "s/127.0.1.1.*/127.0.1.1 $NEW_HOSTNAME/" /etc/hosts
 echo "Hostname has been changed to $NEW_HOSTNAME."
else
 echo "No hostname provided. Skipping hostname update."
fi

# Update and install packages first
apt update && apt upgrade -y
apt install -y mc qemu-guest-agent wireguard-tools ufw

# Docker installation
# Remove old versions if exist
apt remove -y docker docker-engine docker.io containerd runc

# Install prerequisites
apt install -y \
   ca-certificates \
   curl \
   gnupg

# Add Docker's official GPG key
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# Set up Docker repository
echo \
 "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
 "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
 tee /etc/apt/sources.list.d/docker.list > /dev/null

# Update package list with Docker repository
apt update

# Install Docker and related packages
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Enable services
systemctl enable --now docker
systemctl enable --now ssh
systemctl enable --now qemu-guest-agent

usermod -aG docker "$CURRENT_USER"

# SSH Key configuration
echo "Choose SSH configuration:"
echo "0 - Do not import any key (login with password)"
echo "1 - Enter your SSH key manually"
echo "2 - Download the default SSH key (email: aleks.podp.dev@gmail.com)"
read -p "Enter your choice (default: 0): " SSH_OPTION
SSH_OPTION=${SSH_OPTION:-0}

case "$SSH_OPTION" in
 0)
   echo "No SSH key imported. Login will be available via username and password."
   ;;
 1)
   read -p "Enter your SSH public key: " SSH_KEY
   if [ -n "$SSH_KEY" ]; then
     mkdir -p /home/"$CURRENT_USER"/.ssh
     echo "$SSH_KEY" > /home/"$CURRENT_USER"/.ssh/authorized_keys
     chmod 700 /home/"$CURRENT_USER"/.ssh
     chmod 600 /home/"$CURRENT_USER"/.ssh/authorized_keys
     chown -R "$CURRENT_USER":"$CURRENT_USER" /home/"$CURRENT_USER"/.ssh
     echo "SSH key has been added for user $CURRENT_USER."
   else
     echo "No SSH key provided. Login will remain via password."
   fi
   ;;
 2)
   echo "Downloading the default SSH public key..."
   mkdir -p /home/"$CURRENT_USER"/.ssh
   wget "https://dev.azure.com/alekspodpdev-open/Sandbox/_apis/git/repositories/bash-scripts/items?path=/setup/devap_pbk&version=main&download=true" -O /home/"$CURRENT_USER"/.ssh/a>
   if [ $? -eq 0 ]; then
     chmod 700 /home/"$CURRENT_USER"/.ssh
     chmod 600 /home/"$CURRENT_USER"/.ssh/authorized_keys
     chown -R "$CURRENT_USER":"$CURRENT_USER" /home/"$CURRENT_USER"/.ssh
     echo "Default SSH public key downloaded and applied."
   else
     echo "Failed to download the default SSH public key. Please check the URL or your internet connection."
          exit 1
   fi
   ;;
 *)
   echo "Invalid option. No SSH key imported. Login will remain via password."
   ;;
esac

# Firewall configuration
read -p "Do you want to enable the firewall (y/n)? " ENABLE_UFW
if [ "$ENABLE_UFW" == "y" ]; then
 ufw allow OpenSSH
 ufw allow 80
 ufw allow 443
 ufw enable
 echo "Firewall has been enabled. Ports 80, 443, and SSH (22) are open."
else
 echo "Firewall is not enabled."
fi

# Network configuration (moved to end)
read -p "Enter the IP address for ens18 (e.g., 192.168.0.191): " IP_ADDRESS
if [[ ! "$IP_ADDRESS" == */* ]]; then
 IP_ADDRESS="$IP_ADDRESS/24"
fi

read -p "Enter the gateway (default: 192.168.0.1): " GATEWAY
GATEWAY=${GATEWAY:-192.168.0.1}

# Store network configuration but don't apply yet
rm -f /etc/netplan/50-cloud-init.yaml

echo -e "network:
 version: 2
 ethernets:
   ens18:
     dhcp4: false
     addresses:
       - $IP_ADDRESS
    routes:
       - to: default
         via: $GATEWAY
     nameservers:
       addresses:
         - 8.8.8.8
         - 8.8.4.4" | tee /etc/netplan/01-netcfg.yaml

chmod 600 /etc/netplan/01-netcfg.yaml

echo "Network configuration has been saved."
echo "System is ready for final steps."
echo "1. Network configuration will be applied"
echo "2. System will be rebooted"
read -p "Continue with network changes and reboot? (y/n): " FINAL_CONFIRM

if [ "$FINAL_CONFIRM" == "y" ]; then
 echo "Applying network configuration..."
 netplan apply
 echo "Rebooting system in 5 seconds..."
 sleep 5
 reboot
else
 echo "Script finished. Network changes and reboot postponed."
 echo "You can manually apply network changes with 'sudo netplan apply'"
 echo "And reboot with 'sudo reboot' when ready."
fi