# Service Deployment Guide: Cloud-Exposed VM

This guide provides a comprehensive walkthrough for setting up a Debian 12 Virtual Machine (VM) in Proxmox. It covers the initial VM creation, system configuration, and the deployment of various services using Docker.

The architecture assumes that a central Portainer instance is running elsewhere (e.g., in a control LXC) to manage this VM's Docker environment via the Portainer Agent. Additionally, this guide leverages a TrueNAS server for persistent data storage via NFS shares.

While the services are listed in a suggested order, you can choose to install any component independently.

**Table of Contents:**

1.  [Proxmox VM Creation](#1-proxmox-vm-creation)
2.  [Initial Debian VM Configuration](#2-initial-debian-vm-configuration)
3.  [Docker and Portainer Agent Installation](#3-docker-and-portainer-agent-installation)
4.  [Service Deployment](#4-service-deployment)
    *   [Preparing NFS Shares in TrueNAS](#41-preparing-nfs-shares-in-truenas)
    *   [Mounting NFS Shares in the Debian VM](#42-mounting-nfs-shares-in-the-debian-vm)
    *   [Deploying the Docker Stack](#43-deploying-the-docker-stack)
5.  [Service-Specific Configurations](#5-service-specific-configurations)
    *   [NextCloud](#51-nextcloud)
    *   [Paperless NGX](#52-paperless-ngx)
    *   [Gluetun (VPN Client)](#53-gluetun-vpn-client)
    *   [SearXNG](#54-searxng)
    *   [OpenWebUI](#55-openwebui)
6.  [Post-Deployment Steps](#6-post-deployment-steps)
    *   [Firewall Configuration](#61-firewall-configuration)
    *   [Nginx Proxy Manager Setup](#62-nginx-proxy-manager-setup)

---

## 1. Proxmox VM Creation

Before proceeding, ensure you have the appropriate VM template downloaded onto your Proxmox host. For this setup, **Debian 12 (Bookworm)** is used.

### Steps:

1.  **Initiate VM Creation:** In the Proxmox web UI, click the **"Create VM"** button, typically located in the top right corner.

2.  **General Tab:**
    *   **VM ID:** Assign a unique ID for the VM (e.g., `102`).
    *   **Name:** Define a descriptive name for the VM (e.g., `cloudflared-vm`).

3.  **OS Tab:**
    *   **Storage:** Select the storage location where your ISO images are stored.
    *   **ISO Image:** Choose the downloaded Debian 12 template.
    *   Leave other settings at their defaults.

4.  **System Tab:**
    *   You can leave these settings at their default values.

5.  **Disks Tab:**
    *   **Disk Size:** A minimal Debian installation without a GUI does not require extensive disk space. Since services requiring large amounts of storage (like NextCloud) will use NFS shares from TrueNAS, **32 GB** is sufficient.

6.  **CPU Tab:**
    *   **Cores:** **4 cores** is a reasonable starting point, adjust as needed based on workload.

7.  **Memory Tab:**
    *   **Memory:** **8 GB** of RAM is a good allocation for running multiple services.

8.  **Network Tab:**
    *   **Bridge:** Leave this at the default setting, typically `vmbr0`.

9.  **Confirm Tab:**
    *   Review all settings. If correct, click **"Finish"**. Proxmox will create the VM.

---

## 2. Initial Debian VM Configuration

Once the VM is created, start it and access its console via the Proxmox UI to proceed with the Debian installation.

1.  **Debian Installation:**
    *   Follow the on-screen installer prompts.
    *   It is recommended to perform a GUI-less installation (select only "standard system utilities" and "SSH server" during the software selection step) to conserve resources.
    *   Create a non-root user and set a strong password when prompted. This user will be used for daily operations.

2.  **Initial System Setup:**
    *   After the installation is complete and you have logged in, perform an initial system update:
        ```bash
        sudo apt update && sudo apt upgrade -y
        ```
    *   Install essential tools, including `nfs-common` which is required to connect to TrueNAS shares:
        ```bash
        sudo apt install -y sudo nano curl unattended-upgrades ufw openssh-server nfs-common
        ```

3.  **Security Hardening (SSH & Firewall):**
    *   For enhanced security, it is highly recommended to configure key-based SSH authentication and set up the UFW firewall.
    *   You can follow the detailed steps outlined in the [LXC Configuration Guide](../control_lxc/README.md#2-initial-lxc-configuration) for this process.

---

## 3. Docker and Portainer Agent Installation

With the base system configured, the next step is to install Docker and connect this VM to your main Portainer instance.

### 3.1 Install Docker Engine

Follow the official Docker documentation to [install Docker Engine on Debian](https://docs.docker.com/engine/install/debian/). The typical steps are as follows:

```bash
# Add Docker's official GPG key
sudo apt-get update
sudo apt-get install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update

# Install Docker packages
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

### 3.2 Deploy Portainer Agent

The Portainer Agent allows your primary Portainer instance to manage this VM's Docker environment.

1.  **Access Portainer UI:** Navigate to your central Portainer instance (e.g., `https://<LXC_IP>:9443`).
2.  **Add Environment:** From the left menu, select **Environments** and click the **"Add environment"** button.
3.  **Start Wizard:** Select **"Docker Standalone"** as the environment type and click **"Start Wizard"**.
4.  **Get Command:** Select the **Agent** option. Portainer will display a `docker run` command. Copy this command.
5.  **Run Command in VM:** Paste and run the copied command in your new Debian VM's terminal.
6.  **Connect Environment:** Back in the Portainer UI, fill in the environment details:
    *   **Name:** Give it a descriptive name (e.g., `Cloudflared-VM`).
    *   **Environment address:** Enter the IP address of your Debian VM followed by the agent port (e.g., `<CF_VM_IP>:9001`).
7.  Click **"Connect"**. You can now manage this VM from your central Portainer dashboard.

---

## 4. Service Deployment

This section covers the preparation of storage and the deployment of the services via a Portainer Stack.

### 4.1 Preparing NFS Shares in TrueNAS

For each service that requires significant storage, a corresponding dataset and NFS share should be created in TrueNAS.

**General Workflow:**

1.  **Create Dataset:** In the TrueNAS UI, go to **Datasets**. Create a parent dataset for this VM (e.g., `CloudflaredVM`). Inside it, create a child dataset for each service (e.g., `NextCloud`, `Paperless`).
2.  **Set Permissions:** For each dataset, click **Edit Permissions**. Assign ownership to a specific user. For some services like Paperless, it's best to create a dedicated user in TrueNAS (**Credentials -> Local Users**) and use their UID/GID. For others like NextCloud, use the standard `www-data` user.
3.  **Create NFS Share:** Go to **Sharing -> NFS Shares** and click **Add**.
    *   Select the path to the service's dataset.
    *   In **Authorized Networks**, you can restrict access to the VM's IP address for security (e.g., `<CLOUDFLARED_VM_IP>/32`).
    *   In **Advanced Options**, you may need to map users (e.g., Map Root User/Group to `www-data` or `paperless`).

### 4.2 Mounting NFS Shares in the Debian VM

To make the TrueNAS datasets available to Docker, mount them within the Debian VM.

1.  **Create Mount Points:** Create a local directory for each share. It's good practice to organize them:
    ```bash
    mkdir -p /mnt/truenas/nextcloud
    mkdir -p /mnt/truenas/paperless
    ```
2.  **Configure Automatic Mounts:** Edit the `/etc/fstab` file to ensure the shares are mounted automatically on boot.
    ```bash
    sudo nano /etc/fstab
    ```
    Append a line for each NFS share using the following format:
    ```
    # Format: <TRUENAS_IP>:<PATH_TO_DATASET> <LOCAL_MOUNT_POINT> nfs defaults,rw,hard,auto,nofail 0 0

    # Example:
    192.168.1.100:/mnt/pool1/CloudflaredVM/NextCloud /mnt/truenas/nextcloud nfs defaults,rw,hard,auto,nofail 0 0
    192.168.1.100:/mnt/pool1/CloudflaredVM/Paperless /mnt/truenas/paperless nfs defaults,rw,hard,auto,nofail 0 0
    ```
3.  **Mount the Shares:** Reload the systemd manager and mount all entries in `fstab`.
    ```bash
    sudo systemctl daemon-reload
    sudo mount -a
    ```
4.  **Verify:** Run `df -h` to confirm that the NFS shares have been mounted successfully.

### 4.3 Deploying the Docker Stack

You can now deploy all services using a single Docker Compose file within a Portainer Stack. In Portainer, go to your new environment, select **Stacks**, and click **"Add stack"**. Paste your Docker Compose configuration into the web editor.

---

## 5. Service-Specific Configurations

Below are the key environment variables and configurations to check for each service in your Docker Compose file.

### 5.1 NextCloud

NextCloud is a self-hosted productivity platform, offering functionality similar to Dropbox, Google Drive, and Office 365 for file sharing and collaboration.

*   **Port:** Set your desired external port for accessing the NextCloud web UI.
*   **Storage:** Verify that the volume mapping points to your mounted NFS share (e.g., `/mnt/truenas/nextcloud`).
*   **Database Credentials:** Set the `MYSQL_PASSWORD`, `MYSQL_USER`, `MYSQL_DATABASE`, and `MY_SQL_HOST` environment variables for the NextCloud database. We will be hosting the Dataset in the TrueNAS VM, thus the host corresponds to <TRUENAS_IP>:<MYSQL_PORT>.

### 5.2 Paperless-ngx

Paperless-ngx is a powerful document management system that transforms your physical documents into a searchable digital archive.

*   **Port:** Set the external port for the web UI.
*   **Storage:** Ensure the volume paths for `data` and `media` are correctly mapped to your Paperless NFS share.
*   **UID/GID:** Set the `USERMAP_UID` and `USERMAP_GID` environment variables to match the UID and GID of the `paperless` user you created in TrueNAS. This is crucial for file permissions.
*   **URL:** Set the `PAPERLESS_URL` variable to the domain you will use to access it.
*   **Database Credentials:** Set the `DB_HOST`, `DB_USER`, `DB_PORT`, and `DB_NAME`. environment variables for the Paperless database. The database is also hosted in the TrueNAS VM.

### 5.3 Gluetun (VPN Client)

Gluetun is a versatile VPN client container that ensures other Docker containers route their traffic securely through a VPN.

*   **VPN Configuration:**
    *   Set `VPN_SERVICE_PROVIDER` (e.g., `nordvpn`).
    *   Set `VPN_TYPE` (e.g., `openvpn` or `wireguard`).
    *   Provide your `OPENVPN_USER` and `OPENVPN_PASSWORD`.
    *   Specify a `SERVER_COUNTRIES` or `SERVER_CITIES`.
*   **Ports:** The ports for any services routed through Gluetun (like SearXNG) must be published in Gluetun's `ports` section, not the service's own section.

### 5.4 SearXNG

SearXNG is a metasearch engine that aggregates results from other search services while protecting user privacy.

*   **Networking:** To route its traffic through the VPN, its `network_mode` is set to `service:gluetun`. You do not need to change this.
*   **Port Access:** The access port for SearXNG is defined in the `ports` section of the **Gluetun** service.
*   **Storage:** Verify the volume path for its data is correct.

### 5.5 OpenWebUI

OpenWebUI provides a user-friendly, ChatGPT-style web interface for interacting with various local and cloud-based Large Language Models (LLMs).

*   **Port:** Set the desired external port to access the service. No other special configuration is typically needed to get started.
