# My Homelab

This repository documents my personal homelab setup. The configurations and choices are tailored to my specific needs and learning objectives, and suggestions for improvements, alternative approaches, or new services are welcome.

## Guide Order

These walkthroughs assume a Proxmox VE host, a TrueNAS system for persistent storage, and a Cloudflare-managed domain where the relevant guide uses Cloudflare services. Follow the guides in this order:

1. **Prepare the infrastructure:** Create and initially configure the [Control LXC](./control_lxc/README.md), [TrueNAS](./truenas/README.md), `cf_vm`, and `ts_vm` hosts.
2. **Prepare shared storage and databases:** In TrueNAS, create the application datasets, database applications, and NFS shares required by each VM.
3. **Configure host dependencies:** On each VM, install Docker and the Portainer Agent, then mount the required TrueNAS NFS shares.
4. **Deploy application stacks:** Configure the private environment file from the relevant `.env.example`, review the service-specific settings, and deploy through the central Portainer CE instance.
5. **Configure access:** Set up the appropriate NPM instance, Cloudflare Tunnel and Access policies for `cf_vm`, or Tailscale, DNS and NPM for `ts_vm`.

Complete the TrueNAS procedures before the VM steps that depend on them. The host guides link to the exact dataset, database, mounting, and access sections needed for each application.

## Core Architecture

My homelab is built upon a foundation of **Proxmox VE** for virtualization. Centralized storage is managed by **TrueNAS** using ZFS. Large application data is stored on TrueNAS datasets and made available to the virtualized environments through **NFS shares**. Database data uses a separate SSD pool on TrueNAS and is accessed by the VM services over the database application's published TCP port. Some service configuration, Docker volumes, and Paperless export and consume directories remain local to the VMs.

## Virtualized Environments

The documented Proxmox setup includes:

*   [**TrueNAS Storage Server:**](./truenas/README.md)
    *   **Version:** 24.10.2.1
    *   **Role:** Provides centralized ZFS storage, NFS shares for the VMs, and database applications for services that run on TrueNAS.
*   [**A Control LXC Container:**](./control_lxc/README.md)
    *   **OS:** Debian 11 (Bullseye)
    *   **Role:** This container acts as a central management and routing point. It handles incoming requests, monitors the health of other VMs, and hosts various network-wide utility services.
*   **Two Virtual Machines (VMs):**
    *   [**`cf_vm` (Cloudflare-Exposed VM):**](./cf_vm/README.md)
        *   **OS:** Debian 12 (Bookworm)
        *   **Role:** Hosts services intended to be accessible from the internet. Access is secured and managed via **Cloudflare Tunnel**.
    *   [**`ts_vm` (Tailscale-Accessible VM):**](./ts_vm/README.md)
        *   **OS:** Debian 12 (Bookworm)
        *   **Role:** Hosts private services that are only accessible via my **Tailscale** private network.

## Documented Services

The component guides document Docker containers managed through **Portainer CE**. The host-by-host breakdown is below.

The Control LXC runs the central Portainer CE instance. Portainer Agents on the VMs allow it to manage their Docker environments. Watchtower is documented for the hosts where it is included in their stack.

### Common Utility Services

The documented homelab setup also includes the following utility services for operation, monitoring, and maintenance:

*   **Glances:** System monitoring dashboard providing a quick overview of resource usage on each host.

### Services by Host

#### [Control LXC](./control_lxc/README.md) (`control-lxc`)

This LXC container is responsible for overall management, monitoring, and secure access:

*   [**Cloudflared:**](./control_lxc/cloudflared/cloudflared.md) Manages the secure tunnel to Cloudflare for exposing public services.
*   **Homepage:** A simple, customizable dashboard to access all homelab services.
*   [**Nginx Proxy Manager (NPM):**](./control_lxc/npm/npm.md) Manages reverse proxying, SSL certificates (Let's Encrypt), and custom domain routing for services, particularly those exposed via Cloudflared.
*   [**Portainer CE (Main Instance):**](./control_lxc/README.md#3-portainer-installation) Docker container management UI for all Docker hosts.
*   [**Tailscale:**](./control_lxc/tailscale/tailscale.md) Provides secure VPN access to the LXC and its permitted homelab services.
*   **Uptime Kuma:** Monitors the availability of all critical services.
*   [**Watchtower:**](./control_lxc/watchtower/watchtower.md) Automatically updates containers according to the stack configuration.

#### `cf_vm` (Cloudflare-Exposed VM)

Services hosted on this VM are intended for public access via Cloudflare Tunnel:

*   **Glances:** System monitoring dashboard providing a quick overview of resource usage on the VM.
*   [**SearXNG:**](./cf_vm/README.md#54-searxng) A privacy-respecting metasearch engine.
*   [**Nextcloud:**](./cf_vm/README.md#51-nextcloud) Personal cloud storage, file sharing, and collaboration platform.
*   [**Paperless-ngx:**](./cf_vm/README.md#52-paperless-ngx) Document management and searchable document archive.
*   [**Open WebUI:**](./cf_vm/README.md#55-open-webui) A user-friendly web interface for interacting with local Large Language Models (LLMs).
*   [**Gluetun:**](./cf_vm/README.md#53-gluetun-vpn-client) Containerized VPN client routing outbound traffic for other VM services (e.g. SearXNG).
*   **Stirling-PDF:** PDF manipulation and document utility service.
*   [**Portainer Agent:**](./cf_vm/README.md#32-deploy-portainer-agent) Allows the main Portainer CE instance on the Control LXC to manage this VM.
*   **Tailscale:** Provides private network access to the VM.
*   [**Watchtower:**](./cf_vm/README.md#56-watchtower) Automatically updates the stack's containers according to its configuration.

#### `ts_vm` (Tailscale-Accessible VM)

Services on this VM are for private use and accessed securely via Tailscale:

*   **Glances:** System monitoring dashboard providing a quick overview of the VM's resource usage.
*   [**Immich:**](./ts_vm/README.md#51-immich) Self-hosted photo and video backup solution.
*   [**Vaultwarden:**](./ts_vm/README.md#52-vaultwarden) Self-hosted Bitwarden-compatible password manager.
*   [**Syncthing:**](./ts_vm/README.md#54-syncthing-and-google-pixel-1-photo-backup) File synchronization used by the documented Pixel 1 photo pipeline.
*   **Nginx Proxy Manager (NPM):** Reverse proxy for the VM's private services.
*   [**Portainer Agent:**](./ts_vm/README.md#3-docker-and-portainer-agent-installation) Allows the main Portainer CE instance on the Control LXC to manage this VM.
*   [**Watchtower:**](./ts_vm/README.md#53-watchtower) Automatically updates the stack's containers according to its configuration.

## Future Plans

This homelab is an evolving project. Future additions currently planned include:

*   A **Torrenting Stack** (e.g., qBittorrent with Gluetun for VPN).
*   The **\*Arr Stack** (Sonarr, Radarr, Lidarr, Prowlarr, etc.) for media management.

As mentioned, constructive feedback, suggestions for alternative configurations, or ideas for new services are always welcome.
