# Service Deployment Guide: Tailscale VM

This Debian 12 VM runs Docker directly and is managed by the Control LXC's Portainer CE instance through the Portainer Agent. Tailscale is installed locally on `ts_vm`. The VM runs its own Nginx Proxy Manager (NPM) as a downstream proxy for its hosted services, while the Control LXC NPM provides the client-facing entry point. Optional DNS-only CNAME records in Cloudflare point service domains to the Control LXC's Tailscale hostname.

For the shared VM procedures, follow the [CF VM creation steps](../cf_vm/README.md#1-proxmox-vm-creation), [Debian configuration steps](../cf_vm/README.md#2-initial-debian-vm-configuration), [Docker and Portainer Agent steps](../cf_vm/README.md#3-docker-and-portainer-agent-installation), and [NFS mounting steps](../cf_vm/README.md#42-mounting-nfs-shares-in-the-debian-vm). Use TS VM-specific names, shares, paths, and ports described below. Service domains are handled by the Control LXC NPM and forwarded to this VM's downstream NPM.

**Table of Contents:**

1. [Proxmox VM Creation](#1-proxmox-vm-creation)
2. [Initial Debian VM Configuration](#2-initial-debian-vm-configuration)
3. [Docker and Portainer Agent Installation](#3-docker-and-portainer-agent-installation)
   * [Tailscale Installation and Tailnet Setup](#31-tailscale-installation-and-tailnet-setup)
   * [Tailnet Access Policy](#32-tailnet-access-policy)
4. [Service Deployment](#4-service-deployment)
   * [TrueNAS Storage](#41-preparing-and-mounting-truenas-storage)
   * [Immich Database Connection](#42-configuring-the-immich-database-connection)
   * [Docker Stack](#43-deploying-the-docker-stack)
5. [Service-Specific Configurations](#5-service-specific-configurations)
   * [Immich](#51-immich)
   * [Vaultwarden](#52-vaultwarden)
   * [Watchtower](#53-watchtower)
   * [Syncthing and Google Pixel 1 Photo Backup](#54-syncthing-and-google-pixel-1-photo-backup)
     * [Install the Pipeline Dependencies](#541-install-the-pipeline-dependencies)
     * [Run the Weekly Pipeline](#542-run-the-weekly-pipeline)
     * [Sync the Staging Directory to the Pixel](#543-sync-the-staging-directory-to-the-pixel)
6. [Post-Deployment Steps](#6-post-deployment-steps)
   * [NPM Deployment and Proxy Hosts](#61-npm-deployment-and-proxy-hosts)
   * [Optional Cloudflare DNS Names](#62-optional-cloudflare-dns-names)

---

## 1. Proxmox VM Creation

Follow the [Proxmox VM creation steps](../cf_vm/README.md#1-proxmox-vm-creation). Use `ts_vm` for the VM name and a unique VM ID. Adjust the example CPU, memory, and disk allocations to suit the services on this VM.

## 2. Initial Debian VM Configuration

Follow the [Debian configuration steps](../cf_vm/README.md#2-initial-debian-vm-configuration), including NFS client tools and SSH setup. Use this VM's address wherever the guide asks for the CF VM address.

## 3. Docker and Portainer Agent Installation

Follow the [Docker and Portainer Agent installation steps](../cf_vm/README.md#3-docker-and-portainer-agent-installation). Register the environment as `ts_vm` and connect the central Portainer instance to `<TS_VM_IP>:9001`.

### 3.1 Tailscale Installation and Tailnet Setup

Tailscale runs directly on the Debian VM. It provides the private network path to the VM's NPM; the Docker stack does not run a Tailscale container.

1. **Install Tailscale:** In the **TS VM terminal**, run the official installation script:

   ```bash
   curl -fsSL https://tailscale.com/install.sh | sh
   sudo tailscale up
   ```

   The `tailscale up` command prints a browser URL. Open it, sign in to the existing tailnet, and approve the new `ts_vm` device. This setup uses interactive browser authentication rather than a reusable auth key. No special routes, exit-node settings, or other `tailscale up` flags are configured. For reference, see the [Tailscale Linux installation](https://tailscale.com/docs/install/linux) page.
2. **Set the Device Name:** In the Tailscale admin console sidebar, open **Network → Machines**, select the new device, open its device menu, choose the option to edit or rename the machine, enter `ts_vm`, and save. For background, see [Tailscale MagicDNS](https://tailscale.com/docs/features/magicdns).
3. **Apply the Server Tag:** In **Network → Machines**, open the `ts_vm` device and select **Edit ACL tags**. Select `tag:server` and save. If `tag:server` is not available, create it first using the [tag creation steps](../control_lxc/tailscale/tailscale.md#5-tailnet-access-policy), then return to **Edit ACL tags**. Tags identify server devices and are targeted by the homelab's [tailnet access policy](#32-tailnet-access-policy). For background, see [Tailscale server setup](https://tailscale.com/docs/how-to/set-up-servers) and [Tailscale tags](https://tailscale.com/docs/features/tags).
4. **Disable Key Expiry:** In **Network → Machines**, open the `ts_vm` device menu, choose **Disable key expiry**, and confirm the change. Reopen the device menu and check that the action now indicates key expiry is disabled. This is the confirmed setting for this long-running server. For background, see [Tailscale key expiry](https://tailscale.com/docs/features/access-control/key-expiry).
5. **Enable Tailnet DNS:** In the Tailscale admin console sidebar, open **DNS**, turn on **MagicDNS**, and enable the setting that allows clients to use Tailscale DNS settings. Save the DNS settings. This lets authorized clients resolve the VM's `.ts.net` hostname while connected to the tailnet. Do not add a custom nameserver or split-DNS configuration unless your tailnet requires one. For background, see [Tailscale MagicDNS](https://tailscale.com/docs/features/magicdns).

### 3.2 Tailnet Access Policy

Apply the homelab's redacted tailnet policy from the [Control LXC Tailscale guide](../control_lxc/tailscale/tailscale.md#5-tailnet-access-policy). The `ts_vm` device must have the `tag:server` tag. Under this policy, ordinary tailnet members can reach the server's HTTP, HTTPS, and SMB ports, while SSH, the NPM administration interface, and Portainer remain available only to the administrator's laptop. The policy is enforced by Tailscale; it is separate from the NPM proxy-host configuration.

## 4. Service Deployment

### 4.1 Preparing and Mounting TrueNAS Storage

1. **Prepare Shares:** Complete the TrueNAS [Immich dataset and NFS setup](../truenas/README.md#211-mass-storage-dataset) and [Vaultwarden dataset and NFS setup](../truenas/README.md#221-mass-storage-dataset). The Immich library and model cache are within one dataset, with the example export path `/mnt/<MASS_STORAGE_POOL>/ts_vm/Immich`. Vaultwarden has a separate example export at `/mnt/<MASS_STORAGE_POOL>/ts_vm/Vaultwarden`. Both exports allow `<TS_VM_IP>/32`, using this VM's LAN address.
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

The stack includes NPM, Immich, its machine-learning container, Valkey, Vaultwarden, Syncthing, and Watchtower.

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

Vaultwarden requires HTTPS for normal client access. Its DNS-only record points to the Control LXC's Tailscale hostname. The Control LXC NPM forwards HTTPS over the LAN to the TS VM NPM, which sends the request to Vaultwarden over its internal HTTP port. Both NPM proxy hosts use a certificate covering the Vaultwarden domain. Clients must be connected to Tailscale. See [Cloudflare DNS names](#62-optional-cloudflare-dns-names) for the record and certificate configuration.

### 5.3 Watchtower

Watchtower runs as part of this VM stack and monitors containers on `ts_vm` through its Docker socket. Set `WT_NOTIF_URL` to the private Shoutrrr Discord value from the [Watchtower guide](../control_lxc/watchtower/watchtower.md), and set `TZ` for the desired IANA timezone. Its schedule is 09:00 daily in that timezone; verify notification delivery and updates separately.

### 5.4 Syncthing and Google Pixel 1 Photo Backup

Syncthing also runs on this VM. Together with a script, it copies photos onto the owner's Google Pixel 1 for an additional backup to Google Photos.

The Compose stack uses the LinuxServer Syncthing image and configures:

* **SYNCTHING_CONFIG_LOCATION:** Persistent VM directory for Syncthing's settings and database, mapped to `/config`.
* **SYNCTHING_LOCATION:** Pipeline staging path on this VM, mapped to `/data/immich`. Set this to `/mnt/truenas/immich/pipeline/staging` so Syncthing exposes only MotionPhoto2 output to the Pixel.
* **PUID / PGID:** Syncthing's user/group IDs; match the actual permissions on both mounted directories.
* **TZ:** Shared timezone.
* **SYNCTHING_GUI_PORT:** Published web GUI port, originally `8384`.
* **SYNCTHING_SYNC_PORT:** Published TCP and UDP synchronization port, originally `22000`.

The library mount intentionally allows both reads and writes. Keep it writable for this workflow.

#### 5.4.1 Install the pipeline dependencies

The pipeline runs on the **TS VM** as the account that owns `/home/<USERNAME>/pipeline`. It uses the [motionphoto-cli](https://github.com/chengandre/motionphoto-cli) command-line project. This version removes the Gooey graphical interface, uses Python's `argparse`, and omits Gooey from `requirements.txt`.

1. **Install ExifTool:** Download `Image-ExifTool-13.59.tar.gz` from the [ExifTool home page](https://exiftool.org/), then run:

   ```bash
   cd <download-directory>
   gzip -dc Image-ExifTool-13.59.tar.gz | tar -xf -
   cd Image-ExifTool-13.59
   perl Makefile.PL
   make test
   sudo make install
   exiftool -ver
   ```

   `make test` verifies the installation; the expected version is `13.59`.
2. **Choose a converter installation:** Use either the Python source workflow or the published Linux binary. Both provide the same command-line operation; choose one for the pipeline.

   **Python virtual environment:** Clone [motionphoto-cli](https://github.com/chengandre/motionphoto-cli) into the path expected by the Python workflow. This destination name preserves the paths used by the pipeline script:

   ```bash
   cd /home/<USERNAME>/pipeline
   git clone https://github.com/chengandre/motionphoto-cli.git MotionPhoto2
   ```

   Debian 12 includes Python 3.11. Install the venv and pip packages, then create and populate the environment used by the script:

   ```bash
   sudo apt update
   sudo apt install -y python3-venv python3-pip
   mkdir -p /home/<USERNAME>/pipeline
   cd /home/<USERNAME>/pipeline
   python3 -m venv .venv
   .venv/bin/python -m pip install --upgrade pip
   .venv/bin/pip install -r MotionPhoto2/requirements.txt
   .venv/bin/python MotionPhoto2/motionphoto2.py --help
   ```

   The final command should display MotionPhoto2's command-line options. The supplied [pipeline script](./pipeline/run_pipeline.sh) uses this Python installation by default.

   **Linux release binary:** Download the Linux archive from the [motionphoto-cli releases](https://github.com/chengandre/motionphoto-cli/releases), extract it on `ts_vm`, and make the executable runnable. For example:

   ```bash
   mkdir -p /home/<USERNAME>/pipeline/bin
   cd /home/<USERNAME>/pipeline/bin
   curl -fL -o motionphoto2-linux.zip '<MOTIONPHOTO_LINUX_RELEASE_URL>'
   unzip motionphoto2-linux.zip
   chmod +x ./motionphoto2
   ./motionphoto2 --help
   ```

   The published Linux binary is built against an earlier glibc version for compatibility with older systems such as Debian 12. Set `MOTIONPHOTO_BIN` in `run_pipeline.sh` to the extracted executable path, for example:

   ```bash
   MOTIONPHOTO_BIN="/home/<USERNAME>/pipeline/bin/motionphoto2"
   ```

   Do not use both installations for one scheduled pipeline. Test the selected command with `--help` before enabling the cron job.

#### 5.4.2 Run the weekly pipeline

The script is `/home/<USERNAME>/pipeline/run_pipeline.sh`. Use the repository's [redacted script reference](./pipeline/run_pipeline.sh) as the starting point, replacing `<USERNAME>` with the account that owns the pipeline. It scans the Immich upload directory, excludes `.xmp` and `.immich` sidecar files, compares basenames with a ledger, and hard-links only new files into a temporary processing directory. MotionPhoto2 then writes converted output and copied non-motion-photo files to the staging directory. The temporary directory is emptied after processing; the ledger is retained at `/home/<USERNAME>/pipeline/pipeline_ledger.txt`, and output is appended to `/home/<USERNAME>/pipeline/pipeline.log`.

| Purpose | Path |
|---|---|
| Immich source | `/mnt/truenas/immich/library/upload` |
| Temporary hard-link directory | `/mnt/truenas/immich/pipeline/to_process` |
| Syncthing staging directory | `/mnt/truenas/immich/pipeline/staging` |

These directories are on the same TrueNAS filesystem so that `ln` can create hard links. Create the schedule in the pipeline user's crontab with `crontab -e`:

```cron
0 2 * * 6 /bin/bash /home/<USERNAME>/pipeline/run_pipeline.sh
```

This runs every Saturday at 02:00 in the TS VM's configured timezone. Confirm the job with `crontab -l`; cron installation and a successful scheduled run are not verified by this repository.

#### 5.4.3 Sync the staging directory to the Pixel

1. **Install and pair the app:** Install Syncthing-Fork on the Google Pixel 1. In Syncthing-Fork, display the phone's device ID or QR code. In the server Syncthing GUI, choose **Add Remote Device**, enter or scan the phone's device ID, and save it with a reader-chosen device name. Both devices need internet access for the Syncthing relay used by this setup; the Pixel does not need Tailscale for this synchronization step.
2. **Create the server folder:** In the server Syncthing GUI, choose **Add Folder**. Use a reader-chosen folder ID and label, and set the folder path to `/data/immich`. The Docker Compose mapping makes this the TS VM host directory `/mnt/truenas/immich/pipeline/staging`. Share the folder with the newly added Pixel device, set the folder type to **Send & Receive**, and leave the server's rescan interval at its default unless a different policy is needed.
3. **Accept the folder on the Pixel:** Accept the folder-sharing request in Syncthing-Fork and choose `DCIM/ImmichSync` as the local folder path. Set the Pixel folder type to **Send & Receive**. This permits deleting files from the phone after upload and synchronizing those deletions back to the staging directory.
4. **Confirm the connection:** With the Pixel online and Syncthing-Fork running, expand its entry under **Remote Devices** in the TS VM Syncthing web UI. Confirm the shared folder is **Up to Date**. A **Relay WAN** connection can synchronize the folder without a direct tailnet connection on port 22000; this is the connection type shown by the documented setup. See [Syncthing's relay guidance](https://docs.syncthing.net/v1.30.0/users/faq.html). Device IDs, folder IDs, labels, hostnames, and addresses are created by the reader and must not be copied from another installation.
5. **Enable Google Photos backup:** In Google Photos, enable backup for `DCIM/ImmichSync` and select full-quality/original upload. After Google Photos confirms upload, use **Free up space** to remove local copies from the Pixel while retaining the cloud copies. The staging directory is an additional Google Photos copy; it does not replace Immich library or database backups.

---

## 6. Post-Deployment Steps

Tailscale runs locally on `ts_vm`, and the TS VM NPM remains the downstream proxy for its application containers. With the optional DNS records below, name resolution and service access work as follows:

* **DNS:** `photos.<YOUR_DOMAIN>` or `vw.<YOUR_DOMAIN>` → CNAME to `<CONTROL_LXC_TAILSCALE_HOSTNAME>` → Control LXC Tailscale IP.
* **Connection:** Authorized client connected to Tailscale → Control LXC NPM → TS VM LAN IP → TS VM NPM → Immich or Vaultwarden.

Cloudflare supplies the DNS record; the client sends service traffic over Tailscale to the Control LXC NPM, which forwards it to the TS VM NPM. These DNS-only records do not make the services publicly accessible. The client must be connected to Tailscale, able to resolve the Control LXC's Tailscale hostname, and permitted to reach the Control LXC NPM by the tailnet's access rules. Both NPM instances use the requested service domain to select the appropriate proxy host.

### 6.1 NPM Deployment and Proxy Hosts

NPM runs as part of this TS VM Compose stack. It publishes HTTP, HTTPS, and its administration interface on the TS VM and shares the `proxy-net` Docker network with `immich-server` and `vaultwarden`. Because the downstream proxy hosts use Docker container names, this shared network is required. The Control LXC NPM forwards the service domains to this NPM over the TS VM's LAN address.

The Control LXC must be able to reach `<TS_VM_IP>:443` on the LAN. Docker publishes this port independently of the VM's UFW allow rules; those rules alone do not limit which LAN clients can reach it. If source restrictions are needed, configure them in the network firewall or Docker's firewall backend. See [Docker's firewall guidance](https://docs.docker.com/engine/network/packet-filtering-firewalls/).

1. **Prepare Persistent Directories:** In the **TS VM terminal**, create the host directories for NPM data and certificates. Replace the examples with paths chosen for this VM:

   ```bash
   sudo mkdir -p /srv/docker/npm/data
   sudo mkdir -p /srv/docker/npm/letsencrypt
   ```

   Set `NPM_DATA_LOCATION` and `NPM_LETSENCRYPT_LOCATION` in the private stack environment to those same paths. These directories must persist across container recreation.
2. **Deploy NPM with the Stack:** In central Portainer, select the `ts_vm` environment, open **Stacks**, edit the TS VM stack, and deploy the updated [Compose file](./docker-compose.yml). Ensure the stack environment includes the two NPM path variables and `TZ`. Confirm that the `npm`, `immich_server`, and `vaultwarden` containers are running and that all three are attached to `proxy-net`.
3. **Open the NPM Interface:** From the local network, open `http://<TS_VM_IP>:81`. If this is a new instance, enter the administrator email address and a strong administrator password when prompted, save the form, and confirm that the NPM dashboard opens. Keep these credentials private. The NPM administration interface has no NPM access list configured; access is through the TS VM's port 81. Tailnet-level restrictions remain governed by the [tailnet access policy](../control_lxc/tailscale/tailscale.md#5-tailnet-access-policy).
4. **Create the Immich Proxy Host:** In **Hosts → Proxy Hosts**, click **Add Proxy Host** and enter:

   | Field | Value |
   |---|---|
   | Domain Names | `photos.<YOUR_DOMAIN>` |
   | Scheme | `http` |
   | Forward Hostname / IP | `immich_server` |
   | Forward Port | `2283` |
   | Access List | **Public** |

   On the **SSL** tab, select the Let's Encrypt certificate covering this domain and enable **Force SSL** and **HTTP/2 Support**. Leave the other proxy-host fields unchanged. Do not add an access list; the host uses **Public** access. Save the proxy host and confirm its status is **Online**.
5. **Create the Vaultwarden Proxy Host:** Add another proxy host with:

   | Field | Value |
   |---|---|
   | Domain Names | `vw.<YOUR_DOMAIN>` |
   | Scheme | `http` |
   | Forward Hostname / IP | `vaultwarden` |
   | Forward Port | `80` |
   | Access List | **Public** |

   On the **SSL** tab, select the Let's Encrypt certificate covering this domain and enable **Force SSL** and **HTTP/2 Support**. Leave the other proxy-host fields unchanged. Do not add an access list; the host uses **Public** access. Save the proxy host and confirm its status is **Online**.
6. **Configure the Control LXC NPM:** In the **Control LXC NPM web interface → Hosts → Proxy Hosts**, create a proxy host for each TS VM service. Use the same public domain and certificate configured on this downstream NPM. For Immich, enter:

   | Field | Value |
   |---|---|
   | Domain Names | `photos.<YOUR_DOMAIN>` |
   | Scheme | `https` |
   | Forward Hostname / IP | `<TS_VM_IP>` |
   | Forward Port | `443` |
   | Access List | **Public** |

   On the **SSL** tab, select the certificate covering this domain and enable **Force SSL** and **HTTP/2 Support**. Leave the other proxy-host fields unchanged. Save the proxy host and confirm its status is **Online**. Repeat for Vaultwarden using `vw.<YOUR_DOMAIN>` as **Domain Names**, the same TS VM LAN address, and port `443`.
7. **Verify the End-to-End Path:** From an authorized Tailscale client, the expected path is `photos.<YOUR_DOMAIN>` or `vw.<YOUR_DOMAIN>` → Control LXC Tailscale IP → Control LXC NPM → TS VM LAN IP → TS VM NPM → the corresponding container.

### 6.2 Optional Cloudflare DNS Names

These records make client URLs easier to remember. Before adding them, join `ts_vm` and the client to your tailnet, then configure the downstream and client-facing proxy hosts in the [NPM procedure above](#61-npm-deployment-and-proxy-hosts). Each proxy host must use the same domain you add below. The CNAME does not configure a certificate; both NPM instances need a certificate covering the chosen service domain.

1. **Obtain the Control LXC Tailscale Hostname:** In the Tailscale admin console, open **Network → Machines**, select the Control LXC device, and copy its full DNS name in the form `<DEVICE_NAME>.<TAILNET_NAME>.ts.net`. Use that name as `<CONTROL_LXC_TAILSCALE_HOSTNAME>` below; do not substitute the TS VM's address or include `https://`, a port, or a path. MagicDNS and client DNS acceptance should already be enabled from the earlier setup.
2. **Add the Immich Record:** In the **Cloudflare dashboard**, select your domain, open **DNS → Records**, and click **Add record**. Enter:

   | Field | Value |
   |---|---|
   | Type | **CNAME** |
   | Name | Your desired subdomain, for example `photos` |
   | Target | `<CONTROL_LXC_TAILSCALE_HOSTNAME>` |
   | Proxy status | **DNS only** (grey cloud) |
   | TTL | **Auto** |

   Replace the target with the hostname copied in Step 1, then click **Save**. With the example name, the Immich URL is `https://photos.<YOUR_DOMAIN>`. Replace `<YOUR_DOMAIN>` with your Cloudflare-managed domain. Keep the record **DNS only** so clients connect over Tailscale to the Control LXC NPM. See [Cloudflare record creation](https://developers.cloudflare.com/dns/manage-dns-records/how-to/create-dns-records/) and [proxy status](https://developers.cloudflare.com/dns/proxy-status/).
3. **Add the Vaultwarden Record:** Click **Add record** again. Use **CNAME**, your desired **Name**, for example `vw`, the same **Target** `<CONTROL_LXC_TAILSCALE_HOSTNAME>`, **DNS only**, and **TTL: Auto**. Save. With this example, enter `vw.<YOUR_DOMAIN>` as both NPM proxy-host domains and `https://vw.<YOUR_DOMAIN>` as the stack's `VW_DOMAIN` value.
4. **Verify the Records:** Reopen both records and confirm their subdomain names, identical Control LXC Tailscale hostname targets, **DNS only** status, and **Auto** TTL. In both the **Control LXC NPM** and **TS VM NPM** web interfaces → **Hosts → Proxy Hosts**, confirm each full domain matches its proxy host and HTTPS certificate.
5. **Test from a Tailscale Client:** Connect your client to the tailnet and open `https://photos.<YOUR_DOMAIN>` and `https://vw.<YOUR_DOMAIN>` in its browser. Expect the Immich and Vaultwarden interfaces respectively, with valid HTTPS certificates for those domains. If a name does not resolve, check that the client can resolve `<CONTROL_LXC_TAILSCALE_HOSTNAME>` and uses Tailscale DNS settings. If NPM's default page appears, check the proxy-host domain; if the upstream fails, check its destination and service port.
