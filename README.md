# My Homelab

This repository documents my personal homelab and the services I run. The configurations and choices reflect my specific needs and learning objectives.

## Why This Homelab Is Different

Many homelabs run their applications, storage, and supporting services together on one machine or VM. This setup deliberately separates those responsibilities. The VMs run the application workloads, TrueNAS provides durable shared storage and external databases, and the Control LXC coordinates management and access.

This separation means that applications run in Docker stacks on the VMs while their persistent files and, where appropriate, databases live on TrueNAS and are made available over the network. Proxmox provides the virtualization layer, and the component guides explain how the storage, databases, VMs, containers, and access services connect.

This repository is both a record of the services I run and a practical runbook for recreating the setup. It is intended as a useful starting point for building a similar homelab, while leaving room for different hardware, names, addresses, storage policies, and service choices.

## Core Architecture

My homelab is built upon a foundation of **Proxmox VE** for virtualization. Centralized storage is managed by **TrueNAS** using ZFS. Large application data is stored on TrueNAS datasets and made available to the virtualized environments through **NFS shares**. Database data uses a separate SSD pool on TrueNAS and is accessed by the VM services over the database application's published TCP port. Some service configuration, Docker volumes, and Paperless export and consume directories remain local to the VMs.

This creates a deliberate division of responsibility: TrueNAS owns durable shared data and external databases, the VMs run the application workloads, and the Control LXC provides centralized management plus the network services used to reach them. The Control LXC runs the client-facing NPM and routes requests to both VMs; `ts_vm` also runs its own NPM as a downstream proxy for its local services. Each component guide connects its local setup to the other guides at the point where that dependency is required.

## Guide Order

These walkthroughs assume a Proxmox VE host, a TrueNAS system for persistent storage, and a Cloudflare-managed domain where the relevant guide uses Cloudflare services. Follow the guides in this order:

1. **Prepare the infrastructure:** Create and initially configure the [Control LXC](./control_lxc/README.md), [TrueNAS](./truenas/README.md), [`cf_vm`](./cf_vm/README.md), and [`ts_vm`](./ts_vm/README.md) hosts.
2. **Prepare shared storage and databases:** In TrueNAS, create the application datasets, database applications, and NFS shares required by each VM.
3. **Connect the VMs to shared services:** On each VM, install Docker and the Portainer Agent, create the required local directories, and mount the TrueNAS NFS shares.
4. **Deploy application stacks:** Configure the private environment file from the relevant `.env.example`, review the service-specific settings, and deploy through the central Portainer CE instance.
5. **Configure access:** Configure the Control LXC NPM as the client-facing entry point, then set up Cloudflare Tunnel and Access for `cf_vm` or Tailscale and DNS for `ts_vm`. Keep the TS VM NPM as the downstream proxy for its local services.

Complete the TrueNAS procedures before the VM steps that depend on them. The host guides link to the exact dataset, database, mounting, and access sections needed for each application, so you can follow the storage-to-application relationship for each service.

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
        *   **Role:** Hosts services reached through the Control LXC's NPM via **Cloudflare Tunnel** or the Control LXC's **Tailscale** connection, depending on the service.
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

Services hosted on this VM are reached through the Control LXC's NPM. The normal internet-facing path is Cloudflare Tunnel with Cloudflare Access. Applications that require a URL without Cloudflare Access can instead use the Control LXC's Tailscale connection; Tailscale is installed on `control_lxc`, not on `cf_vm`:

*   **Glances:** System monitoring dashboard providing a quick overview of resource usage on the VM.
*   [**SearXNG:**](./cf_vm/README.md#54-searxng) A privacy-respecting metasearch engine.
*   [**Nextcloud:**](./cf_vm/README.md#51-nextcloud) Personal cloud storage, file sharing, and collaboration platform.
*   [**Paperless-ngx:**](./cf_vm/README.md#52-paperless-ngx) Document management and searchable document archive.
*   [**Open WebUI:**](./cf_vm/README.md#55-open-webui) A user-friendly web interface for interacting with local Large Language Models (LLMs).
*   [**Gluetun:**](./cf_vm/README.md#53-gluetun-vpn-client) Containerized VPN client routing outbound traffic for other VM services (e.g. SearXNG).
*   **Stirling-PDF:** PDF manipulation and document utility service.
*   [**Portainer Agent:**](./cf_vm/README.md#32-deploy-portainer-agent) Allows the main Portainer CE instance on the Control LXC to manage this VM.
*   [**Watchtower:**](./cf_vm/README.md#56-watchtower) Automatically updates the stack's containers according to its configuration.

#### `ts_vm` (Tailscale-Accessible VM)

Services on this VM are for private use and accessed securely via Tailscale:

*   **Glances:** System monitoring dashboard providing a quick overview of the VM's resource usage.
*   [**Immich:**](./ts_vm/README.md#51-immich) Self-hosted photo and video backup solution.
*   [**Vaultwarden:**](./ts_vm/README.md#52-vaultwarden) Self-hosted Bitwarden-compatible password manager.
*   [**Syncthing:**](./ts_vm/README.md#54-syncthing-and-google-pixel-1-photo-backup) File synchronization used by the documented Pixel 1 photo pipeline.
*   [**Nginx Proxy Manager (NPM):**](./ts_vm/README.md#61-npm-deployment-and-proxy-hosts) Reverse proxy for the VM's private services.
*   [**Portainer Agent:**](./ts_vm/README.md#3-docker-and-portainer-agent-installation) Allows the main Portainer CE instance on the Control LXC to manage this VM.
*   [**Watchtower:**](./ts_vm/README.md#53-watchtower) Automatically updates the stack's containers according to its configuration.

## Future Plans

This homelab is an evolving project. Future additions currently planned include:

*   A **Torrenting Stack** (e.g., qBittorrent with Gluetun for VPN).
*   The **\*Arr Stack** (Sonarr, Radarr, Lidarr, Prowlarr, etc.) for media management.

As mentioned, constructive feedback, suggestions for alternative configurations, or ideas for new services are always welcome.
