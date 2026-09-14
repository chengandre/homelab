# Service Deployment Guide: Tailscale VM

This Debian 12 VM runs Docker directly and is managed by the Control LXC's Portainer CE instance through the Portainer Agent. Tailscale is installed locally on `ts_vm`. Optional DNS-only CNAME records in Cloudflare give the services convenient domain names pointing to this VM's Tailscale hostname. Clients connect over Tailscale to a separate Nginx Proxy Manager (NPM) instance on this VM, which forwards requests to the hosted services.

For VM creation, Debian configuration, Docker installation, Portainer Agent setup, and the general NFS mounting workflow, follow the [CF VM guide](../cf_vm/README.md#1-proxmox-vm-creation). Use TS VM-specific names, shares, and ports. For TS service domains, use this VM's Tailscale IP and its own NPM instance rather than the CF VM route through NPM on `control_lxc`.

**Table of Contents:**

1. [Proxmox VM Creation](#1-proxmox-vm-creation)
2. [Initial Debian VM Configuration](#2-initial-debian-vm-configuration)
3. [Docker and Portainer Agent Installation](#3-docker-and-portainer-agent-installation)
4. [Service Deployment](#4-service-deployment)
   * [TrueNAS Storage](#41-preparing-and-mounting-truenas-storage)
   * [Immich Database Connection](#42-configuring-the-immich-database-connection)
   * [Docker Stack](#43-deploying-the-docker-stack)
5. [Service-Specific Configurations](#5-service-specific-configurations)
6. [Post-Deployment Steps](#6-post-deployment-steps)
   * [Optional Cloudflare DNS Names](#61-optional-cloudflare-dns-names)

---

## 1. Proxmox VM Creation

Follow the [Proxmox VM creation steps](../cf_vm/README.md#1-proxmox-vm-creation). Use `ts_vm` for the VM name and a unique VM ID. Adjust the example CPU, memory, and disk allocations to suit the services on this VM.

## 2. Initial Debian VM Configuration

Follow the [Debian configuration steps](../cf_vm/README.md#2-initial-debian-vm-configuration), including NFS client tools and SSH setup. Use this VM's address wherever the guide asks for the CF VM address.

## 3. Docker and Portainer Agent Installation

Follow the [Docker and Portainer Agent installation steps](../cf_vm/README.md#3-docker-and-portainer-agent-installation). Register the environment as `ts_vm` and connect the central Portainer instance to `<TS_VM_IP>:9001`.

## 4. Service Deployment

### 4.1 Preparing and Mounting TrueNAS Storage

1. **Prepare Shares:** Complete the TrueNAS [Immich dataset and NFS setup](../truenas/README.md#211-mass-storage-dataset) and [Vaultwarden dataset and NFS setup](../truenas/README.md#221-persistent-dataset). The Immich library and model cache are within one dataset, with the example export path `/mnt/<MASS_STORAGE_POOL>/ts_vm/Immich`. Vaultwarden has a separate example export at `/mnt/<MASS_STORAGE_POOL>/ts_vm/Vaultwarden`. Both exports allow `<TS_VM_IP>/32`, using this VM's LAN address.
2. **Create Mount Points:** In the TS VM terminal, create the example mount points used by the template:

   ```bash
   sudo mkdir -p /mnt/truenas/immich
   sudo mkdir -p /mnt/truenas/vaultwarden
   ```

   Substitute your actual VM mount paths if they differ. Creating these directories does not mount the TrueNAS shares.
3. **Mount Storage:** Follow the [Debian NFS mounting workflow](../cf_vm/README.md#42-mounting-nfs-shares-in-the-debian-vm) for the Immich dataset and Vaultwarden dataset. Mount the Immich export at the example `/mnt/truenas/immich` and the Vaultwarden export at `/mnt/truenas/vaultwarden`, substituting your chosen VM mount points. Both Immich container paths must resolve within the mounted Immich dataset.
4. **Check Paths:** Set the environment variables to the mounted paths on this VM. TrueNAS dataset paths and VM mount points are different paths. The template's `library` and `model-cache` directory names are examples; use the existing library and cache directories within the Immich mount.
5. **Verify Mounts:** In the TS VM terminal, check the filesystem backing each path:

   ```bash
   findmnt -T /mnt/truenas/immich/library
   findmnt -T /mnt/truenas/immich/model-cache
   findmnt -T /mnt/truenas/vaultwarden
   ```

   The library and cache paths should both be backed by the Immich NFS export, and the Vaultwarden path by its own export, rather than the VM's local root filesystem. Confirm access using the application's actual user/group before starting containers.
6. **Map Paths into Compose:** Set `UPLOAD_LOCATION`, `MODEL_CACHE_LOCATION`, and `VW_DATA_LOCATION` to these VM paths. Set `SYNCTHING_LOCATION` to its intended photo source directory and prepare `SYNCTHING_CONFIG_LOCATION` with the Syncthing user's ownership.

### 4.2 Configuring the Immich Database Connection

Complete the [Immich PostgreSQL dataset and deployment on TrueNAS](../truenas/README.md#213-postgresql-dataset-and-deployment) first. The database runs on TrueNAS and is separate from the VM's Compose stack.

1. **Configure the VM Connection:** Set these values in the TS VM stack environment:

   | VM variable | Value source |
   |---|---|
   | `DB_HOSTNAME` | `<TRUENAS_IP>` |
   | `DB_PORT` | `<PUBLISHED_POSTGRES_PORT>` |
   | `DB_USERNAME` | User configured in the TrueNAS database |
   | `DB_PASSWORD` | That user's password |
   | `DB_DATABASE_NAME` | Immich database name |

2. **Verify Application Access:** After deploying the VM stack, inspect Immich's logs for a successful database connection and confirm its web interface starts.

### 4.3 Deploying the Docker Stack

1. **Select Environment:** In the central Portainer instance, select `ts_vm`.
2. **Add Stack:** Navigate to **Stacks** and click **"+ Add stack"**.
3. **Compose File:** Paste the [Docker Compose file](./docker-compose.yml) into the **Web editor**.
4. **Environment Variables:** Load the [environment template](./.env.example) and replace the placeholders with your configured values.
5. **Runtime Environment:** Immich and Syncthing read their runtime variables from `stack.env`. Keep this arrangement when deploying through Portainer.
6. **Review Service Settings:** Complete [Section 5](#5-service-specific-configurations) before deployment, including database connection values, storage paths, user/group settings, ports, and the intended Vaultwarden URL.
7. **Deploy:** Deploy the stack and check the containers' status and logs.

For command-line Compose deployment, copy the template to `.env` for interpolation and create a local `stack.env` containing the runtime variables needed by Immich and Syncthing. Keep both files private.

The stack includes Immich, its machine-learning container, Valkey, Vaultwarden, Syncthing, and Watchtower.

---

## 5. Service-Specific Configurations

Below are the environment variables and storage settings specific to this VM.

### 5.1 Immich

Immich provides photo and video storage. Its media library lives on TrueNAS's mass-storage pool and is mounted on this VM. The machine-learning cache also lives on TrueNAS and is bind-mounted into the container; no Docker named volume is needed.

Complete the [TrueNAS database setup](../truenas/README.md#213-postgresql-dataset-and-deployment) before deploying Immich. General pool architecture is described in the [TrueNAS guide](../truenas/README.md).

Configure:

* **UPLOAD_LOCATION:** VM mount path for the photo library, for example `/mnt/truenas/immich/library`.
* **MODEL_CACHE_LOCATION:** VM mount path for the TrueNAS-backed machine-learning cache, for example `/mnt/truenas/immich/model-cache`.
* **DB_HOSTNAME / DB_PORT:** TrueNAS IP and the published database port.
* **DB_USERNAME / DB_PASSWORD / DB_DATABASE_NAME:** Credentials and database name configured for the external PostgreSQL application.
* **IMMICH_VERSION:** Image tag used by both Immich containers, defaulting to `release` when unset.
* **REDIS_HOSTNAME:** `redis`, the Compose service name for the Valkey container. See [Immich's environment variable reference](https://docs.immich.app/install/environment-variables/).
* **IMMICH_PORT:** VM port forwarded to Immich by NPM.
* **TZ:** Timezone, shared with Vaultwarden and Watchtower.

Syncthing uses `PUID` and `PGID` to select its container user/group. Match these values to the permissions on its mounted directories.

### 5.2 Vaultwarden

Vaultwarden provides a Bitwarden-compatible password manager.

* **VW_DATA_LOCATION:** VM mount path for its TrueNAS-backed persistent data, mapped to `/data`.
* **VW_PORT:** VM port forwarded to Vaultwarden by NPM.
* **VW_DOMAIN:** Full URL used by clients to access Vaultwarden.
* **VW_UID / VW_GID:** Stack variables passed to the container as `PUID` and `PGID`.
* **TZ:** Timezone from the stack environment.

The Compose configuration disables signups.

### 5.3 Watchtower

Watchtower runs on this VM and uses `WT_NOTIF_URL` for notifications and `TZ` for its timezone. Its schedule is 09:00 daily in that timezone. See the [Watchtower guide](../control_lxc/watchtower/watchtower.md) for the common notification workflow; use this VM's variable name.

### 5.4 Syncthing and Google Pixel 1 Photo Backup

Syncthing also runs on this VM. Together with a script, it copies photos onto the owner's Google Pixel 1 for an additional backup to Google Photos.

The Compose stack uses the LinuxServer Syncthing image and configures:

* **SYNCTHING_CONFIG_LOCATION:** Persistent VM directory for Syncthing's settings and database, mapped to `/config`.
* **SYNCTHING_LOCATION:** Library path on this VM, mapped to `/data/immich`. Point this at the intended mounted TrueNAS photo folder.
* **PUID / PGID:** Syncthing's user/group IDs; match the actual permissions on both mounted directories.
* **TZ:** Shared timezone.
* **SYNCTHING_GUI_PORT:** Published web GUI port, originally `8384`.
* **SYNCTHING_SYNC_PORT:** Published TCP and UDP synchronization port, originally `22000`.

The library mount intentionally allows both reads and writes. Keep it writable for this workflow.

---

## 6. Post-Deployment Steps

Tailscale runs locally on `ts_vm`. With the optional DNS records below, name resolution and service access work as follows:

* **DNS:** `photos.<YOUR_DOMAIN>` or `vw.<YOUR_DOMAIN>` → CNAME to `<TS_VM_TAILSCALE_HOSTNAME>` → TS VM Tailscale IP.
* **Connection:** Authorized client connected to Tailscale → NPM on `ts_vm` → Immich or Vaultwarden.

Cloudflare supplies the DNS record; the client sends service traffic over Tailscale to NPM. These DNS-only records do not make the services publicly accessible. The client must be connected to Tailscale, able to resolve the VM's Tailscale hostname, and permitted to reach NPM by the tailnet's access rules. NPM uses the requested service domain to select the appropriate proxy host.

### 6.1 Optional Cloudflare DNS Names

These records make client URLs easier to remember. Before adding them, join `ts_vm` and the client to your tailnet and configure the TS VM's NPM proxy hosts for Immich and Vaultwarden. Each proxy host must use the same domain you add below and forward to its service's configured port (`IMMICH_PORT` or `VW_PORT`). For HTTPS, NPM needs a certificate covering the chosen service domain; the CNAME does not configure a certificate.

1. **Obtain the Tailscale Hostname:** In the **Tailscale admin console → Machines**, open the entry for `ts_vm` and copy its full DNS name, in the form `<DEVICE_NAME>.<TAILNET_NAME>.ts.net`. Use that name as `<TS_VM_TAILSCALE_HOSTNAME>` below; do not substitute the VM's LAN address or include `https://`, a port, or a path. Enable **MagicDNS** in the tailnet's **DNS** settings and allow the client to use Tailscale DNS settings. See [Tailscale MagicDNS](https://tailscale.com/docs/features/magicdns).
2. **Add the Immich Record:** In the **Cloudflare dashboard**, select your domain, open **DNS → Records**, and click **Add record**. Enter:

   | Field | Value |
   |---|---|
   | Type | **CNAME** |
   | Name | Your desired subdomain, for example `photos` |
   | Target | `<TS_VM_TAILSCALE_HOSTNAME>` |
   | Proxy status | **DNS only** (grey cloud) |
   | TTL | **Auto** |

   Replace the target with the hostname copied in Step 1, then click **Save**. With the example name, the Immich URL is `https://photos.<YOUR_DOMAIN>`. Replace `<YOUR_DOMAIN>` with your Cloudflare-managed domain. Keep the record **DNS only** so clients connect directly over Tailscale. See [Cloudflare record creation](https://developers.cloudflare.com/dns/manage-dns-records/how-to/create-dns-records/) and [proxy status](https://developers.cloudflare.com/dns/proxy-status/).
3. **Add the Vaultwarden Record:** Click **Add record** again. Use **CNAME**, your desired **Name**, for example `vw`, the same **Target** `<TS_VM_TAILSCALE_HOSTNAME>`, **DNS only**, and **TTL: Auto**. Save. With this example, enter `vw.<YOUR_DOMAIN>` as the Vaultwarden NPM proxy-host domain and `https://vw.<YOUR_DOMAIN>` as the stack's `VW_DOMAIN` value.
4. **Verify the Records:** Reopen both records and confirm their subdomain names, identical Tailscale hostname targets, **DNS only** status, and **Auto** TTL. In the **TS VM NPM web interface → Hosts → Proxy Hosts**, confirm each full domain matches its service's proxy host and HTTPS certificate.
5. **Test from a Tailscale Client:** Connect your client to the tailnet and open `https://photos.<YOUR_DOMAIN>` and `https://vw.<YOUR_DOMAIN>` in its browser. Expect the Immich and Vaultwarden interfaces respectively, with valid HTTPS certificates for those domains. If a name does not resolve, check that the client can resolve `<TS_VM_TAILSCALE_HOSTNAME>` and uses Tailscale DNS settings. If NPM's default page appears, check the proxy-host domain; if the upstream fails, check its destination and service port.
