# LXC Container Deployment Guide

This guide outlines the steps to deploy services within this LXC container. The sections follow a suggested order; follow the prerequisites for each service before deploying it.

**Table of Contents:**

1.  [LXC Container Creation in Proxmox](#1-lxc-container-creation-in-proxmox)
2.  [Initial LXC configuration](#2-initial-lxc-configuration)
3.  [Portainer Installation](#3-portainer-installation)
4.  [Nginx Proxy Manager Installation](./npm/npm.md)
5.  [Cloudflared Installation](./cloudflared/cloudflared.md)
6.  [Tailscale Installation](./tailscale/tailscale.md)
7.  [Other Services Installation](#7-other-services-installation)



## 1. LXC Container Creation in Proxmox

Before proceeding, ensure you have the appropriate LXC template downloaded onto your Proxmox host. For this setup, **Debian 11 (Bullseye)** was used. If you are running Proxmox VE 8.x or newer, **Debian 12 (Bookworm)** is also a suitable choice.

### Steps:

1.  **Initiate CT Creation:** In the Proxmox VE web UI, click the **"Create CT"** button, typically located in the top right corner.

2.  **General Tab:**
    *   **CT ID:** Assign a unique ID for the container (e.g., `101`).
    *   **Hostname:** Define a hostname for the LXC (e.g., `control-lxc`).
    *   **Password:** Set a strong password for the `root` user of the container. This will be used for initial console access.
    *   **SSH Public Key:** You can optionally add your SSH public key here for immediate key-based root login. Alternatively, this guide will cover adding it for a non-root user later using `ssh-copy-id`.
    *   **Unprivileged container:** Ensure this option remains **checked** for enhanced security.

3.  **Template Tab:**
    *   **Storage:** Select the storage location where your LXC templates are stored.
    *   **Template:** Choose the downloaded Debian 11 (or Debian 12) template from the list.

4.  **Disks Tab:**
    *   **Root Disk Size:** A minimal Debian installation without a GUI does not require extensive disk space for the OS itself. **8 GB** is generally sufficient for the root filesystem.

5.  **CPU Tab:**
    *   **Cores:** **2 cores** is a reasonable starting point.

6.  **Memory Tab:**
    *   **Memory:** Assign RAM to the container. **4 GB** is a generous amount for this LXC.
    *   **Swap:** I assigned **1 GB**.

7.  **Network Tab:**
    *   **Name:** Typically `eth0`.
    *   **Bridge:** Usually `vmbr0`.
    *   **VLAN Tag:** Leave blank unless you are using VLANs.
    *   **Firewall:** Can be left unchecked if you manage the firewall within the LXC (as covered later with UFW).
    *   **IPv4:** Select **Static**.
        *   **IPv4 Address:** Assign a static IP address from your LAN (e.g., `192.168.1.100/24`).
        *   **Gateway:** Enter your network's gateway IP address (e.g., `192.168.1.1`).
    *   **IPv6:** Select **Static** or **DHCP** if used, or leave blank/select **SLAAC** if not actively managing static IPv6. For this guide, it was kept blank.

8.  **DNS Tab:**
    *   **DNS domain:** You can leave this blank.
    *   **DNS servers:** You can leave this blank to inherit DNS settings from the Proxmox host. Alternatively, explicitly set public DNS servers like Cloudflare's `1.1.1.1` or Google's `8.8.8.8`.

9.  **Confirm Tab:**
    *   Review all settings. If correct, click **"Finish"**. Proxmox will create and start the container.

---

## 2. Initial LXC Configuration

Once the container is created and started, access its console via the Proxmox UI.

### 2.1 System Updates

First, update the package list and upgrade all installed packages to their latest versions:

```bash
apt update && apt upgrade -y
```

### 2.2 Install Essential Tools

Install a few useful command-line utilities:

```bash
apt install -y sudo nano curl unattended-upgrades ufw openssh-server
```

*   **`sudo`**: Allows permitted users to execute commands as root.
*   **`nano`**: A simple and user-friendly command-line text editor.
*   **`curl`**: A tool for transferring data with URLs, often used for downloading files or testing network connectivity.
*   **`unattended-upgrades`**: Configures the system to automatically install security updates.
*   **`ufw`**: "Uncomplicated Firewall," an easy-to-use interface for managing `iptables`.
*   **`openssh-server`**: Enables SSH access to the container.

### 2.3 Create a Non-Root User with Sudo Privileges

It's best practice to avoid using the `root` user for daily operations.

1.  Create a new user (replace `<username>` with your desired username):
    ```bash
    adduser <username>
    ```
    You will be prompted to set a password and fill in user information (optional).

2.  Add the new user to the `sudo` group to grant administrative privileges:
    ```bash
    usermod -aG sudo <username>
    ```

### 2.4 Configure SSH Access

1.  **Generate SSH Key Pair (if you don't have one):**
    On your **local machine/laptop** (not inside the LXC), if you need a new SSH key pair:
    ```bash
    ssh-keygen -t ed25519 -C "your_email@example.com"
    ```
    Follow the prompts. It's recommended to use a strong passphrase for your private key.

2.  **Copy SSH Public Key to the LXC:**
    From your **local machine**, use `ssh-copy-id` to securely add your public key to the new user's `authorized_keys` file on the LXC. Replace `path/to/your/public_key.pub` (often `~/.ssh/id_ed25519.pub` or `~/.ssh/id_rsa.pub`), `<username>`, and `<LXC_IP>`:
    ```bash
    ssh-copy-id -i path/to/your/public_key.pub <username>@<LXC_IP>
    ```

3.  **Test SSH Login:**
    From your **local machine**, attempt to log in to the LXC as the new user using your SSH key:
    ```bash
    ssh -i path/to/your/private_key <username>@<LXC_IP>
    ```
    If successful, you should be logged in without needing a password.

### 2.5 Harden SSH Configuration

Once key-based authentication is working, disable password-based authentication and root login via SSH for better security.

1.  Edit the SSH server configuration file **inside the LXC**:
    ```bash
    sudo nano /etc/ssh/sshd_config
    ```

2.  Find and modify the following lines (uncomment them if they are commented out):
    *   Change `PermitRootLogin` from `yes` (or its default) to `prohibit-password` (allows root login with key, but not password) or `no` (disables root login entirely via SSH). `prohibit-password` is a good balance if you might occasionally need root SSH access with a key.
        ```
        PermitRootLogin prohibit-password
        ```
    *   Change `PasswordAuthentication` from `yes` to `no`:
        ```
        PasswordAuthentication no
        ```
    *   Ensure `PubkeyAuthentication` is set to `yes` (it usually is by default):
        ```
        PubkeyAuthentication yes
        ```

3.  Save the file (Ctrl+O, Enter, and Ctrl+X).

4.  Restart the SSH service to apply the changes:
    ```bash
    sudo systemctl restart ssh
    ```
    **Important:** Ensure you can still log in with your SSH key *before* disconnecting your current session.

### 2.6 Configure Firewall (UFW)

Set up basic firewall rules using UFW.

1.  **Set Default Policies:**
    *   Deny all incoming traffic by default:
        ```bash
        sudo ufw default deny incoming
        ```
    *   Allow all outgoing traffic by default:
        ```bash
        sudo ufw default allow outgoing
        ```

2.  **Allow SSH Access:**
    Allow SSH connections from your local network (or a specific IP if preferred). Replace `<LAN_SUBNET>` with your actual local network range:
    ```bash
    sudo ufw allow from <LAN_SUBNET> to any port 22 proto tcp comment 'Allow SSH from LAN'
    ```
    *(Additional ports for other services will be opened as those services are installed.)*

3.  **Enable UFW:**
    You can choose to enable the firewall now or wait until all necessary application ports have been allowed. To enable it:
    ```bash
    sudo ufw enable
    ```

### 2.7 Configure Automatic Security Updates

The `unattended-upgrades` package, installed earlier, can automatically download and install security updates, helping to keep your system secure without manual intervention. To configure it, run the following command:

```bash
sudo dpkg-reconfigure --priority=low unattended-upgrades
```

This completes the initial creation and hardening of the LXC container. You are now ready to proceed with installing services like Portainer.

---
## 3. Portainer Installation

For managing Docker containers, Portainer provides a convenient web UI.

### 3.1. Install Docker Engine

Follow the official Docker documentation to [install Docker Engine on Debian](https://docs.docker.com/engine/install/debian/).

```bash
# Add Docker's official GPG key:
sudo apt-get update
sudo apt-get install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update

sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

### 3.2. Configure Docker User Group (Optional, Recommended)

To run Docker commands without `sudo`:
```bash
sudo groupadd docker
sudo gpasswd -a $(whoami) docker
```
**Log out and log back in** for group changes to take effect.

### 3.3. Deploy Portainer

Refer to the official [Portainer CE installation guide for Docker on Linux](https://docs.portainer.io/start/install-ce/server/docker/linux). 

```bash
docker volume create portainer_data

docker run -d -p 8000:8000 -p 9443:9443 --name portainer --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce:lts
```

### 3.4. Access Portainer & Firewall Rule

*   Access Portainer via: `https://<LXC_IP>:9443`
*   Complete the initial admin user setup.
*   Add a UFW rule to allow access:
    ```bash
    sudo ufw allow from <LAN_SUBNET> to any port 9443 proto tcp comment 'Portainer Web UI'
    ```

All subsequent services in this guide will be deployed as Docker stacks using Portainer.

---
## [4. Nginx Proxy Manager](./npm/npm.md)
## [5. Cloudflared](./cloudflared/cloudflared.md)
## [6. Tailscale](./tailscale/tailscale.md)

## 7. Other Services Installation

At this point, you can choose to set up the other two VMs and deploy their services directly. The rest of this guide installs:

1. [Watchtower](./watchtower/watchtower.md): a service that updates all containers
2. Glances: Hardware monitor
3. Uptime Kuma: Services monitor
4. Homepage: Dashboard for your homelab
