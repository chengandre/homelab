# Service Deployment Guide: Cloudflare-Exposed VM

This guide provides a comprehensive walkthrough for setting up a Debian 12 Virtual Machine (VM) in Proxmox. It covers the initial VM creation, system configuration, and the deployment of various services using Docker.

The architecture assumes that a central Portainer instance is running elsewhere (e.g., in a control LXC) to manage this VM's Docker environment via the Portainer Agent. Nextcloud and Paperless use TrueNAS NFS storage, with external databases configured separately. Docker named volumes and local configuration directories remain on `cf_vm`.

The services are presented in deployment order because storage and database preparation are shared prerequisites. Follow the relevant sections for the services you intend to deploy.

**Table of Contents:**

1.  [Proxmox VM Creation](#1-proxmox-vm-creation)
2.  [Initial Debian VM Configuration](#2-initial-debian-vm-configuration)
3.  [Docker and Portainer Agent Installation](#3-docker-and-portainer-agent-installation)
4.  [Service Deployment](#4-service-deployment)
    *   [Preparing NFS Shares in TrueNAS](#41-preparing-nfs-shares-in-truenas)
    *   [Mounting NFS Shares in the Debian VM](#42-mounting-nfs-shares-in-the-debian-vm)
    *   [Deploying the Docker Stack](#43-deploying-the-docker-stack)
5.  [Service-Specific Configurations](#5-service-specific-configurations)
    *   [Nextcloud](#51-nextcloud)
    *   [Paperless-ngx](#52-paperless-ngx)
    *   [Gluetun (VPN Client)](#53-gluetun-vpn-client)
    *   [SearXNG](#54-searxng)
    *   [Open WebUI](#55-open-webui)
    *   [Watchtower](#56-watchtower)
6.  [Post-Deployment Steps](#6-post-deployment-steps)
    *   [Firewall Configuration](#61-firewall-configuration)
    *   [Nginx Proxy Manager Setup](#62-nginx-proxy-manager-setup)
    *   [Cloudflare Configuration](#63-cloudflare-configuration)
        *   [Add Public Hostnames to the Tunnel](#631-add-public-hostnames-to-the-tunnel)
        *   [Add Hostnames to Your Access Application](#632-add-hostnames-to-your-access-application)

---

## 1. Proxmox VM Creation

Before proceeding, ensure you have the appropriate VM template downloaded onto your Proxmox host. For this setup, **Debian 12 (Bookworm)** is used.

### Steps:

1.  **Initiate VM Creation:** In the Proxmox web UI, click the **"Create VM"** button, typically located in the top right corner.

2.  **General Tab:**
    *   **VM ID:** Assign a unique ID for the VM (e.g., `102`).
    *   **Name:** Define a descriptive name for the VM (e.g., `cf_vm`).

3.  **OS Tab:**
    *   **Storage:** Select the storage location where your ISO images are stored.
    *   **ISO Image:** Choose the downloaded Debian 12 template.
    *   Leave other settings at their defaults.

4.  **System Tab:**
    *   You can leave these settings at their default values.

5.  **Disks Tab:**
    *   **Disk Size:** A minimal Debian installation without a GUI does not require extensive disk space. Since services requiring large amounts of storage (like Nextcloud) will use NFS shares from TrueNAS, **32 GB** is sufficient.

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

3.  **Configure SSH Key Access:** From your **local machine**, copy your public key to the Debian user created during installation:
    ```bash
    ssh-copy-id -i path/to/your/public_key.pub <username>@<CF_VM_IP>
    ```
    Replace the key path, username, and `<CF_VM_IP>`. Test key-based access before changing the SSH configuration:
    ```bash
    ssh -i path/to/your/private_key <username>@<CF_VM_IP>
    ```
    For the equivalent walkthrough and key-generation details, see the [Control LXC SSH configuration steps](../control_lxc/README.md#24-configure-ssh-access).

4.  **Harden SSH:** In the **CF VM terminal**, edit `/etc/ssh/sshd_config`:
    ```bash
    sudo nano /etc/ssh/sshd_config
    ```
    Set or uncomment these values:
    ```ini
    PermitRootLogin no
    PasswordAuthentication no
    PubkeyAuthentication yes
    ```
    Save the file, restart SSH, and confirm that a new terminal can still connect with your key before closing the current session:
    ```bash
    sudo systemctl restart ssh
    ssh -i path/to/your/private_key <username>@<CF_VM_IP>
    ```
    For background on the settings, see the [Control LXC SSH hardening steps](../control_lxc/README.md#25-harden-ssh).

5.  **Configure the VM Firewall:** In the **CF VM terminal**, set the default policies and allow SSH from your LAN:
    ```bash
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    sudo ufw allow from <LAN_SUBNET> to any port 22 proto tcp comment 'Allow SSH from LAN'
    sudo ufw enable
    sudo ufw status verbose
    ```
    Replace `<LAN_SUBNET>` with your LAN range, such as `192.168.1.0/24`. Confirm that UFW is active and SSH is allowed before disconnecting. The service-specific firewall rules are added later in [Section 6.1](#61-firewall-configuration).
    For the general UFW procedure, see the [Control LXC firewall steps](../control_lxc/README.md#26-configure-firewall).

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

1.  **Access Portainer UI:** Navigate to your central Portainer instance (e.g., `https://<CONTROL_LXC_IP>:9443`).
2.  **Add Environment:** From the left menu, select **Environments** and click the **"Add environment"** button.
3.  **Start Wizard:** Select **"Docker Standalone"** as the environment type and click **"Start Wizard"**.
4.  **Get Command:** Select the **Agent** option. Portainer will display a `docker run` command. Copy this command.
5.  **Run Command in VM:** Paste and run the copied command in your new Debian VM's terminal.
6.  **Firewall:** Add the following rule to allow connection from the Control LXC.
```bash
sudo ufw allow from <CONTROL_LXC_IP> to any port 9001 proto tcp comment 'Portainer Agent from Control LXC'
```
7.  **Connect Environment:** Back in the Portainer UI, fill in the environment details:
    *   **Name:** Give it a descriptive name (e.g., `cf_vm`).
    *   **Environment address:** Enter the IP address of your Debian VM followed by the agent port (e.g., `<CF_VM_IP>:9001`).
8.  Click **"Connect"**. You can now manage this VM from your central Portainer dashboard.

---

## 4. Service Deployment

This section covers the preparation of storage and the deployment of the services via a Portainer Stack.

### 4.1 Preparing NFS Shares in TrueNAS

Nextcloud and Paperless use NFS-backed application storage. Prepare the [Nextcloud dataset](../truenas/README.md#312-mass-storage-dataset) and [Paperless dataset](../truenas/README.md#321-mass-storage-dataset), with their storage accounts and permissions, on **TrueNAS**. Create the [Nextcloud NFS share](../truenas/README.md#313-nfs-share) and [Paperless NFS share](../truenas/README.md#322-nfs-share), each allowing `<CF_VM_IP>/32` with its service-specific Maproot user/group and Mapall unset. Record each export path from **Shares → NFS** and use the CF VM's LAN address, `<CF_VM_IP>`, for client access.

Nextcloud and Paperless share the MariaDB application on TrueNAS, using different database names and database users. Complete the [MariaDB dataset and application deployment](../truenas/README.md#311-mariadb-dataset-and-deployment) before deploying the CF stack, then set each application's connection values. Database files remain on TrueNAS, not on the VM's NFS mounts.

### 4.2 Mounting NFS Shares in the Debian VM

To make the TrueNAS datasets available to Docker, mount them within the Debian VM.

1.  **Create Mount Points:** Create a local directory for each share. It's good practice to organize them:
    ```bash
    sudo mkdir -p /mnt/truenas/nextcloud
    sudo mkdir -p /mnt/truenas/paperless
    ```
2.  **Configure Automatic Mounts:** Edit the `/etc/fstab` file to ensure the shares are mounted automatically on boot.
    ```bash
    sudo nano /etc/fstab
    ```
    Append a line for each NFS share using the following format. Replace `<TRUENAS_IP>` with the TrueNAS LAN address and the example export paths with the full paths recorded in **TrueNAS → Shares → NFS**. The example below uses `192.168.1.10` for TrueNAS and datasets under `tank/cf_vm`; substitute your server address, pool and dataset names:
    ```
    # Format: <TRUENAS_IP>:<PATH_TO_DATASET> <LOCAL_MOUNT_POINT> nfs defaults,rw,hard,auto,nofail 0 0

    # Example:
    192.168.1.10:/mnt/tank/cf_vm/Nextcloud /mnt/truenas/nextcloud nfs defaults,rw,hard,auto,nofail 0 0
    192.168.1.10:/mnt/tank/cf_vm/Paperless /mnt/truenas/paperless nfs defaults,rw,hard,auto,nofail 0 0
    ```
3.  **Mount the Shares:** Reload the systemd manager and mount all entries in `fstab`.
    ```bash
    sudo systemctl daemon-reload
    sudo mount -a
    ```
4.  **Verify:** In the **CF VM terminal**, run:
    ```bash
    findmnt -T /mnt/truenas/nextcloud
    findmnt -T /mnt/truenas/paperless
    ```
    Expect filesystem type `nfs` or `nfs4` and the corresponding TrueNAS export as the source. A local root filesystem means the share is not mounted. Do not start the stack against unmounted directories.
5. **Prepare Paperless Directories:** After confirming the Paperless NFS mount, in the **CF VM terminal**, create ordinary directories within it:

   ```bash
   sudo mkdir -p /mnt/truenas/paperless/data /mnt/truenas/paperless/media
   sudo chown <PAPERLESS_UID>:<PAPERLESS_GID> /mnt/truenas/paperless/data /mnt/truenas/paperless/media
   sudo chmod 750 /mnt/truenas/paperless/data /mnt/truenas/paperless/media
   ```

   Replace the numeric ID placeholders with the separate values obtained in [TrueNAS Paperless setup](../truenas/README.md#321-mass-storage-dataset). These commands prepare new directories; do not recursively change existing files. Verify both paths:

   ```bash
   findmnt -T /mnt/truenas/paperless/data
   findmnt -T /mnt/truenas/paperless/media
   ls -ldn /mnt/truenas/paperless/data /mnt/truenas/paperless/media
   ```

   Both paths should be backed by the same Paperless NFS export, with the recorded UID/GID and mode `drwxr-x---`. Compose maps them to `/usr/src/paperless/data` and `/usr/src/paperless/media`, respectively.


### 4.3 Deploying the Docker Stack

Before deploying Nextcloud and Paperless, complete the [MariaDB dataset and application setup on TrueNAS](../truenas/README.md#311-mariadb-dataset-and-deployment).

1. **Prepare Private Values:** On your workstation, save a copy of the [environment template](./.env.example) as `.env` and replace every `<...>` placeholder using [Section 5](#5-service-specific-configurations). Keep this file private.
2. **Prepare Local Directories:** In the **CF VM terminal**, set the same absolute `VM_CONFIG_ROOT` used in your private environment file, for example `/home/alex` if your Debian username is `alex`. Replace `alex` with your username in the command below and use the same path in the environment file. Create the directories:

   ```bash
   VM_CONFIG_ROOT=/home/alex
   sudo mkdir -p "$VM_CONFIG_ROOT/paperless/export" "$VM_CONFIG_ROOT/paperless/consume"
   sudo mkdir -p "$VM_CONFIG_ROOT/searxng" "$VM_CONFIG_ROOT/gluetun"
   ```

   These are local VM paths. Paperless `data` and `media` instead use `/mnt/truenas/paperless`; Nextcloud uses `/mnt/truenas/nextcloud`. Check each directory's ownership and configure access for its container user before deployment. For Paperless export and consume directories, use the storage account's separate numeric UID and GID:

   ```bash
   sudo chown <PAPERLESS_UID>:<PAPERLESS_GID> "$VM_CONFIG_ROOT/paperless/export" "$VM_CONFIG_ROOT/paperless/consume"
   ```

   Substitute the IDs obtained in [Paperless configuration](#52-paperless-ngx). Do not recursively change existing application data as part of this directory preparation.
3. **Create the Stack:** In the **central Portainer UI**, select the `cf_vm` environment, open **Stacks → Add stack**, enter your desired stack name, and choose **Web editor**. Paste the [Compose file](./docker-compose.yml).
4. **Load Variables:** Under **Environment variables**, choose **Load variables from .env file** and upload your private file, or enter the same names and values individually. Check that every placeholder has been replaced. Portainer substitutes `${VARIABLE}` entries in Compose; explicit service `environment` entries then pass the selected values into containers. This CF stack does not use `env_file: stack.env`. See [Portainer stack creation](https://docs.portainer.io/2.21/user/docker/stacks/add).
5. **Review and Deploy:** Check [Section 5](#5-service-specific-configurations), database credentials, mounted storage, local directories and distinct available host ports. Click **Deploy the stack**.
6. **Check Startup:** Open the stack's containers in Portainer and inspect status and logs. Expect services to remain running, without missing-variable, database-connection or storage-permission errors. Confirm each web interface responds at `http://<CF_VM_IP>:<PUBLISHED_PORT>` from an allowed client, then configure the proxy and domains in [Section 6](#6-post-deployment-steps). Initial accounts and service-specific setup are separate from container startup.

Open Web UI, Paperless Redis, and SearXNG Valkey use Docker named volumes on the VM. Include those volumes and the local `VM_CONFIG_ROOT` directories in the backup plan alongside TrueNAS data and external databases. Preserve the private environment values securely for recovery.

---

## 5. Service-Specific Configurations

Below are the key environment variables and configurations to check for each service in your Docker Compose file.

### 5.1 Nextcloud

Nextcloud is a self-hosted productivity platform, offering functionality similar to Dropbox, Google Drive, and Office 365 for file sharing and collaboration.

*   **Port:** Set your desired external port for accessing the Nextcloud web UI.
*   **Storage:** Verify that the volume mapping points to your mounted NFS share (e.g., `/mnt/truenas/nextcloud`).

Complete the [MariaDB deployment on TrueNAS](../truenas/README.md#311-mariadb-dataset-and-deployment) before starting Nextcloud. In the **CF VM Portainer stack environment**, set:

| Stack variable | Value |
|---|---|
| `MYSQL_HOST` | `<TRUENAS_IP>:<PUBLISHED_MARIADB_PORT>` using the host port chosen in TrueNAS |
| `MYSQL_DATABASE` | Database name entered as `MYSQL_DATABASE` in the MariaDB application |
| `MYSQL_USER` | Application user entered as `MYSQL_USER` in the MariaDB application |
| `MYSQL_PASS` | Password entered as `MYSQL_PASSWORD` in the MariaDB application |

The Compose file passes `MYSQL_PASS` into Nextcloud as `MYSQL_PASSWORD`. The MariaDB root password stays with the database application. After stack deployment, inspect Nextcloud's container logs for database connection errors and confirm its web interface starts.

There are some additional configuration steps that you will need to do:

*   In your CF VM terminal, cd to your mounted Nextcloud Storage, e.g. `/mnt/truenas/nextcloud/`, you might need root permission to do this, thus you can do `su -` first. Under the Nextcloud directory do `nano config/config.php`.
*   Under trusted domains, add the domains that you will be using to access Nextcloud, e.g. `nextcloud.<YOUR_DOMAIN>`. Also add this domain to `overwrite.cli.url`.
*   Append this following line `'overwriteprotocol' => 'https',`, if you don't have it already.
*   You can also add these two lines to remove some warning in Nextcloud, adjust the variables:
```
    'default_phone_region' => '<PHONE_REGION>',
    'default_timezone' => '<TIMEZONE>',
```

### 5.2 Paperless-ngx

Paperless-ngx is a powerful document management system that transforms your physical documents into a searchable digital archive.

*   **Port:** Set the external port for the web UI.
*   **Storage:** Ensure the volume paths for `data` and `media` are correctly mapped to your Paperless NFS share.
*   **UID/GID:** In the **TrueNAS shell**, run `id <PAPERLESS_STORAGE_USER>`, substituting the storage account that owns the Paperless files. Record its UID and primary GID separately as `PAPERLESS_UID` and `PAPERLESS_GID` in the stack environment. Compose passes them as `USERMAP_UID` and `USERMAP_GID`. Use those same numeric IDs for the VM's local export and consume directories.
*   **URL:** Set the `PAPERLESS_URL` variable to the domain you will use to access it.
*   **Database Credentials:** Paperless uses the same TrueNAS MariaDB server as Nextcloud. Follow the [TrueNAS Paperless connection mapping](../truenas/README.md#323-mariadb-connection): set `DB_HOST=<TRUENAS_IP>` and `DB_PORT=<PUBLISHED_MARIADB_PORT>`, then set `DB_USER`, `DB_PASS` and `DB_NAME` from the Paperless database configuration. Compose maps them to the corresponding `PAPERLESS_DB*` container variables. Use the Paperless application account; Nextcloud's MariaDB credentials do not establish the Paperless connection.

### 5.3 Gluetun (VPN Client)

Gluetun is a versatile VPN client container that ensures other Docker containers route their traffic securely through a VPN.

*   **VPN Configuration:**
    *   Set `VPN_SERVICE_PROVIDER` (e.g., `nordvpn`).
    *   This Compose file sets container `VPN_TYPE=openvpn`.
    *   Set stack `OPENVPN_USER` and `OPENVPN_PASSWORD` to your provider's OpenVPN service credentials. Obtain service credentials from your VPN provider, rather than using an assumed account password.
    *   Set stack `VPN_COUNTRY` and `VPN_CITY` to provider-supported locations; Compose passes them as `SERVER_COUNTRIES` and `SERVER_CITIES`.
*   **Ports:** The ports for any services routed through Gluetun (like SearXNG) must be published in Gluetun's `ports` section, not the service's own section.

### 5.4 SearXNG

SearXNG is a metasearch engine that aggregates results from other search services while protecting user privacy.

*   **Networking:** To route its traffic through the VPN, its `network_mode` is set to `service:gluetun`. You do not need to change this.
*   **Port Access:** Set `GLUETUN_PORT` to SearXNG's published CF VM port. Gluetun maps it to container port `8080`; use this same host port in NPM and firewall examples.
*   **Public URL:** Set `SEARXNG_HOSTNAME` to `searxng.<YOUR_DOMAIN>`, without `https://` or a trailing slash. Compose constructs `SEARXNG_BASE_URL`. Worker and thread example values are `4`, matching the Compose defaults.
*   **Storage:** Verify the volume path for its data is correct.

### 5.5 Open WebUI

Open WebUI provides a user-friendly, ChatGPT-style web interface for interacting with various local and cloud-based Large Language Models (LLMs).

*   **Port:** Set `OPENWEBUI_PORT` to its published CF VM port, mapped to container port `8080`.
*   **IDs:** Set `OPENWEBUI_UID` and `OPENWEBUI_GID` to the intended numeric account IDs. In the **CF VM terminal**, use `id <VM_USER>` to obtain separate values for a selected Debian account. Compose passes these as `PUID` and `PGID`; verify the effective container user before changing existing volume ownership.
*   **Persistent Data:** The `open-webui` Docker named volume maps to `/app/backend/data` on this VM.

### 5.6 Watchtower

Watchtower uses `WT_NOTIF_URL` for its Shoutrrr notification URL and `TZ` for the shared timezone. Obtain the URL using the [common Watchtower notification procedure](../control_lxc/watchtower/watchtower.md), using `WT_NOTIF_URL` in this stack. The configured schedule is 09:00 daily in that timezone; verify successful notifications and updates separately.

## 6. Post-Deployment Steps

With the services running, the final stage is to configure the network path to make them securely accessible from the internet. The flow of traffic will be:

**Internet → Cloudflare Tunnel → Nginx Proxy Manager → Service Container**

### 6.1. Firewall Configuration

Use the service host ports from the stack environment when configuring access from the Control LXC NPM instance. Docker published ports bypass UFW filtering, so the UFW rules below do not by themselves restrict container access to NPM. Apply restrictions using the deployed Docker firewall backend or an upstream firewall, following [Docker packet filtering guidance](https://docs.docker.com/engine/network/packet-filtering-firewalls/), and test access from both allowed and disallowed clients.

On the **Debian VM where your services are running**, execute the following commands. Replace `<CONTROL_LXC_IP>` with the IP address of the container running NPM and each port placeholder with its matching stack environment value. `<GLUETUN_PORT>` is the SearXNG host port.

```bash
# Allow traffic from Nginx Proxy Manager to your services
sudo ufw allow from <CONTROL_LXC_IP> to any port <NEXTCLOUD_PORT> proto tcp comment 'Allow NPM to Nextcloud'
sudo ufw allow from <CONTROL_LXC_IP> to any port <PAPERLESS_PORT> proto tcp comment 'Allow NPM to Paperless'
sudo ufw allow from <CONTROL_LXC_IP> to any port <GLUETUN_PORT> proto tcp comment 'Allow NPM to SearXNG'
sudo ufw allow from <CONTROL_LXC_IP> to any port <OPENWEBUI_PORT> proto tcp comment 'Allow NPM to Open Web UI'

# Reload the firewall to apply the new rules
sudo ufw reload
```

### 6.2. Nginx Proxy Manager Setup

Next, for each service you want to expose, create a "Proxy Host" in NPM. This tells NPM where to send incoming requests based on the domain name.

Repeat these steps for every service (Nextcloud, Paperless, etc.):

1.  **Access NPM:** Navigate to your NPM web UI (e.g., `http://<CONTROL_LXC_IP>:81`).
2.  **Add Proxy Host:** Go to **Hosts -> Proxy Hosts** and click **"Add Proxy Host"**.
3.  **Details Tab:**
    *   **Domain Names:** Enter the full public domain for the service (e.g., `nextcloud.<YOUR_DOMAIN>`).
    *   **Scheme:** Leave this as `http`.
    *   **Forward Hostname / IP:** Enter the IP address of your **new Debian VM** (e.g., `<CF_VM_IP>`).
    *   **Forward Port:** Enter the matching stack host port: `NEXTCLOUD_PORT`, `PAPERLESS_PORT`, `GLUETUN_PORT` for SearXNG, or `OPENWEBUI_PORT`.
    *   Enable **Block Common Exploits** and **Websockets Support**.
4.  **SSL Tab:**
    *   **SSL Certificate:** Select your wildcard certificate (e.g., `*.<YOUR_DOMAIN>`).
    *   Enable **Force SSL** and **HTTP/2 Support**.
5.  **Save:** Click **"Save"**.

### 6.3. Cloudflare Configuration

Finally, configure your Cloudflare Zero Trust dashboard to route traffic for your new services through the tunnel and protect them with an access policy. Ensure that you have set up Cloudflared and established the tunnel by following [the Cloudflared guide](../control_lxc/cloudflared/cloudflared.md).

#### 6.3.1. Add Public Hostnames to the Tunnel

First, you need to tell the tunnel which subdomains to listen for and where to send the traffic (to your NPM instance).

1.  Navigate to the **Zero Trust Dashboard -> Networks -> Tunnels**.
2.  Select your tunnel and click **"Configure"**.
3.  Select the **Public Hostnames** tab and click **"Add a public hostname"**.
4.  Create a new entry for **each service**. For Nextcloud, the configuration would be:
    *   **Subdomain:** `nextcloud`
    *   **Domain:** Select `<YOUR_DOMAIN>`.
    *   **Service Type:** `HTTPS`
    *   **URL:** `https://<CONTROL_LXC_IP>:443`. This must point to your NPM instance, as it is the entry point for all tunnel traffic.
5.  **Save** the hostname. Repeat this process for `paperless`, `searxng`, and any other services.

#### 6.3.2. Add Hostnames to Your Access Application

Defining the hostname makes it routable, but adding it to an "Application" is what secures it with your access policies (e.g., requiring a login).

1.  In the **Zero Trust Dashboard**, go to **Access -> Applications**.
2.  Find the application that protects your self-hosted services and click **"Edit"**.
3.  Navigate to the **"Self-hosted"** tab (or wherever your domain is configured).
4.  In the **"Application Domain"** section, add the new subdomains you just configured in the tunnel (e.g., `nextcloud.<YOUR_DOMAIN>`, `paperless.<YOUR_DOMAIN>`).
5.  **Save** the application.

Now, when you try to access `https://nextcloud.<YOUR_DOMAIN>`, you will be prompted with the Cloudflare Access login screen before your request is passed to NPM and then to your service. The corresponding DNS records will be created automatically in your main Cloudflare dashboard.
