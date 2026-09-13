# Service Deployment Guide: Tailscale VM

This Debian 12 VM runs Docker directly and is managed by the Control LXC's Portainer CE instance through the Portainer Agent. Its services are accessed through Tailscale. A separate Nginx Proxy Manager (NPM) instance runs on this VM and routes Tailscale requests.

For VM creation, Debian configuration, Docker installation, Portainer Agent setup, and the general NFS mounting workflow, follow the [CF VM guide](../cf_vm/README.md#1-proxmox-vm-creation). Use TS VM-specific names, shares, and ports. The CF VM's public Cloudflare routing steps do not apply here.

**Table of Contents:**

1. [Proxmox VM Creation](#1-proxmox-vm-creation)
2. [Initial Debian VM Configuration](#2-initial-debian-vm-configuration)
3. [Docker and Portainer Agent Installation](#3-docker-and-portainer-agent-installation)
4. [Service Deployment](#4-service-deployment)
   * [TrueNAS Storage](#41-preparing-and-mounting-truenas-storage)
   * [Immich Database on TrueNAS](#42-deploying-the-immich-database-on-truenas)
   * [Docker Stack](#43-deploying-the-docker-stack)
5. [Service-Specific Configurations](#5-service-specific-configurations)
6. [Post-Deployment Steps](#6-post-deployment-steps)

---

## 1. Proxmox VM Creation

Follow the [Proxmox VM creation steps](../cf_vm/README.md#1-proxmox-vm-creation). Use `ts_vm` for the VM name and a unique VM ID. Adjust the example CPU, memory, and disk allocations to suit the services on this VM.

## 2. Initial Debian VM Configuration

Follow the [Debian configuration steps](../cf_vm/README.md#2-initial-debian-vm-configuration), including NFS client tools and SSH setup. Use this VM's address wherever the guide asks for the CF VM address.

## 3. Docker and Portainer Agent Installation

Follow the [Docker and Portainer Agent installation steps](../cf_vm/README.md#3-docker-and-portainer-agent-installation). Register the environment as `ts_vm` and connect the central Portainer instance to `<TS_VM_IP>:9001`.

## 4. Service Deployment

### 4.1 Preparing and Mounting TrueNAS Storage

1. **Prepare Shares:** Use the [TrueNAS notes](../truenas/README.md) and the [existing NFS workflow](../cf_vm/README.md#41-preparing-nfs-shares-in-truenas) as references.
2. **Create Mount Points:** In the TS VM terminal, create the example mount points used by the template:

   ```bash
   sudo mkdir -p /mnt/truenas/immich/library
   sudo mkdir -p /mnt/truenas/immich/model-cache
   sudo mkdir -p /mnt/truenas/vaultwarden
   ```

   Substitute your actual VM mount paths if they differ. Creating these directories does not mount the TrueNAS shares.
3. **Mount Storage:** Follow the [Debian NFS mounting workflow](../cf_vm/README.md#42-mounting-nfs-shares-in-the-debian-vm) for the Immich library, machine-learning cache, and Vaultwarden data.
4. **Check Paths:** Set the environment variables to the mounted paths on this VM. TrueNAS dataset paths and VM mount points are different paths.
5. **Verify Mounts:** In the TS VM terminal, check the filesystem backing each path:

   ```bash
   findmnt -T /mnt/truenas/immich/library
   findmnt -T /mnt/truenas/immich/model-cache
   findmnt -T /mnt/truenas/vaultwarden
   ```

   Each path should be backed by the intended TrueNAS NFS export, rather than the VM's local root filesystem. Confirm access using the application's actual user/group before starting containers.
6. **Map Paths into Compose:** Set `UPLOAD_LOCATION`, `MODEL_CACHE_LOCATION`, and `VW_DATA_LOCATION` to these VM paths. Set `SYNCTHING_LOCATION` to its intended photo source directory and prepare `SYNCTHING_CONFIG_LOCATION` with the Syncthing user's ownership.

### 4.2 Deploying the Immich Database on TrueNAS

Immich uses a PostgreSQL application running on TrueNAS, with its persistent database storage mapped to a dataset in the separate SSD pool. The VM connects to the application's published port; the database is not part of the VM's Compose stack.

1. **Create the Database Dataset:** In TrueNAS, select the SSD pool and create the dataset that will hold Immich's PostgreSQL data. Use the [existing dataset creation workflow](../cf_vm/README.md#41-preparing-nfs-shares-in-truenas) for navigation. Use permissions appropriate to the database application's user; the photo-library NFS permissions apply to a different dataset.
2. **Configure the Custom Application:** Use the TrueNAS custom application deployment form. In its **Image Configuration**, set:

   | Field | Configured value |
   |---|---|
   | Repository | `ghcr.io/immich-app/postgres` |
   | Tag | `14-vectorchord0.3.0-pgvectors0.2.0` |
   | Pull Policy | Pull only if the image is not already present on the host |

   Check compatibility with the Immich version you deploy before changing the database image.
3. **Set Database Environment:** Configure the database application's initialization environment with your database name, user, and password. The VM's `DB_*` variables are connection settings and do not configure the TrueNAS application.
4. **Map Persistent Storage:** Map `<SSD_POOL_DATABASE_DATASET_PATH>` to the database application's configured container data path. This mapping is local to TrueNAS; it is separate from mounting photo-library shares on the VM.
5. **Publish the Database Port:** Configure the application's port mapping and use the published TrueNAS port for connections from the VM. Use the published port for `DB_PORT` on the VM.
6. **Start and Verify the Database:** Deploy the application and inspect its status and PostgreSQL logs.
7. **Configure the VM Connection:** Set these values in the TS VM stack environment:

   | VM variable | Value source |
   |---|---|
   | `DB_HOSTNAME` | `<TRUENAS_IP>` |
   | `DB_PORT` | `<PUBLISHED_POSTGRES_PORT>` |
   | `DB_USERNAME` | User configured in the TrueNAS database |
   | `DB_PASSWORD` | That user's password |
   | `DB_DATABASE_NAME` | Immich database name |

8. **Verify Application Access:** After deploying the VM stack, inspect Immich's logs for a successful database connection and confirm its web interface starts.

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

Complete the [TrueNAS database setup](#42-deploying-the-immich-database-on-truenas) before deploying Immich. General pool architecture is described in the [TrueNAS guide](../truenas/README.md).

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

The separate NPM instance on this VM routes Tailscale requests to the hosted services. Use each service's configured domain when accessing it from a device on the tailnet.
