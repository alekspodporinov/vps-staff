# VPS Setup Script

Automated setup script for configuring new Ubuntu VPS instances with Docker, Homebrew, and essential tools.

## Compatibility

✅ **Ubuntu 20.04 LTS** (Focal Fossa)  
✅ **Ubuntu 22.04 LTS** (Jammy Jellyfish)  
✅ **Ubuntu 24.04 LTS** (Noble Numbat)  
✅ **Newer Ubuntu versions** (automatically detected)

The script automatically detects your Ubuntu version and configures repositories accordingly.

## Features

- **User Management**: Adds user to sudo and docker groups
- **Hostname Configuration**: Option to set custom hostname
- **System Updates**: Updates all packages to latest versions
- **Docker Installation**: Installs Docker CE from official Docker repository
  - Docker Engine
  - Docker CLI
  - Docker Compose plugin
  - Docker Buildx plugin
- **Homebrew Installation**: Installs Homebrew (Linuxbrew) package manager
  - Automatic shell profile configuration
  - Non-interactive installation
- **Essential Packages**:
  - Midnight Commander (mc)
  - QEMU Guest Agent
  - WireGuard Tools
  - UFW Firewall
  - OpenSSH Server
- **SSH Key Configuration**: Multiple options for SSH access
- **Network Configuration**: Static IP configuration with netplan
- **Firewall Setup**: UFW configuration with common ports

## Quick Start

### One-line Installation

```bash
wget "https://github.com/alekspodporinov/vps-staff/raw/main/setup.sh" -O setup.sh && sudo chmod +x setup.sh && sudo ./setup.sh
```

### Manual Installation

```bash
# Download the script
wget "https://github.com/alekspodporinov/vps-staff/raw/main/setup.sh"

# Make it executable
sudo chmod +x setup.sh

# Run the script
sudo ./setup.sh
```

## Ubuntu 24.04 Specific Notes

The script is fully compatible with Ubuntu 24.04 (Noble Numbat):

- **Docker CE**: Official Docker repository supports Ubuntu 24.04
- **Homebrew**: Homebrew (Linuxbrew) officially supports Ubuntu 24.04
- **All packages**: Available in Ubuntu 24.04 repositories
- **Automatic detection**: Script uses `/etc/os-release` to detect version codename

## Requirements

- Fresh Ubuntu installation (20.04, 22.04, 24.04 or newer)
- Root access or sudo privileges
- Internet connection

## What the Script Does

1. **Verifies root privileges** and detects the current user
2. **Detects Ubuntu version** and displays OS information
3. **Configures sudo access** for the detected user
4. **Sets hostname** (optional)
5. **Updates system** packages
6. **Installs essential packages**
7. **Installs Docker CE** from official repository
8. **Installs Homebrew** with dependencies
9. **Configures SSH keys** (3 options available)
10. **Sets up firewall** (optional)
11. **Configures network** with static IP
12. **Reboots system** (optional)

## SSH Key Configuration Options

During script execution, you can choose:

- **Option 0**: No SSH key (password login only)
- **Option 1**: Enter your SSH public key manually
- **Option 2**: Download default SSH key from repository

## Network Configuration

The script configures:
- Static IP address for interface `ens18`
- Custom gateway (default: 192.168.0.1)
- DNS servers: 8.8.8.8, 8.8.4.4
- Netplan configuration

## Post-Installation

After the script completes and the system reboots:

- Docker is running and user is in docker group
- Homebrew is available in the shell (run `brew --version` to verify)
- Firewall is configured (if enabled)
- Network is configured with static IP

To use Docker without sudo, log out and log back in after installation.

## Verification

After installation, verify everything works:

```bash
# Check Docker
docker --version
docker ps

# Check Homebrew
brew --version
brew doctor

# Check system services
systemctl status docker
systemctl status ssh
```

## Troubleshooting

### Docker not working
- Ensure you've logged out and back in after installation
- Check if user is in docker group: `groups $USER`

### Homebrew command not found
- Source your shell profile: `source ~/.bashrc`
- Or log out and log back in

### Network issues after reboot
- Check netplan configuration: `sudo netplan status`
- Review configuration: `cat /etc/netplan/01-netcfg.yaml`

## License

This is a personal VPS setup script. Use at your own risk.

## Author

alekspodporinov
