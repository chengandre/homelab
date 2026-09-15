# My Homelab

This repository documents my personal homelab setup. The configurations and choices are tailored to my specific needs and learning objectives, and suggestions for improvements, alternative approaches, or new services are welcome.

## Prerequisites and Guide Order

These walkthroughs assume a Proxmox VE host, a TrueNAS system for persistent storage, and a Cloudflare-managed domain where the relevant guide uses Cloudflare services. Complete host creation and initial configuration before deploying Docker stacks. Create the required TrueNAS datasets, database applications, and NFS shares before mounting storage in either VM; the VM guides then cover mounts, Compose configuration, and service access.

## Core Architecture

My homelab is built upon a foundation of **Proxmox VE** for virtualization. Centralized storage is managed by **TrueNAS**, utilizing **ZFS** with a **RAID-Z2** configuration for data redundancy and integrity. Large application data is stored on TrueNAS datasets and made available to the virtualized environments via **NFS shares**. Database data uses the separate SSD pool on TrueNAS. Some service configuration, Docker volumes, and Paperless export and consume directories remain local to the VMs.

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

## Hosted Services

The services documented here run in Docker containers managed through **Portainer CE**. The host-by-host breakdown is below.

### Common Utility Services

The homelab uses the following common utility services across its LXC and VM environments for operation, monitoring, and maintenance:

*   **Glances:** System monitoring dashboard providing a quick overview of resource usage on each host.
*   **Portainer Agent:** Allows the central Portainer CE instance (running on the Control LXC) to manage Docker environments on the respective VMs. *(The Control LXC runs the main Portainer CE instance).*
*   **Watchtower:** Automatically updates running Docker containers to their latest versions on each host where it's deployed.

### Services by Host

#### [Control LXC](./control_lxc/README.md) (`control-lxc`)

This LXC container is responsible for overall management, monitoring, and secure access:

*   [**Cloudflared:**](./control_lxc/cloudflared/cloudflared.md) Manages the secure tunnel to Cloudflare for exposing public services.
*   **Homepage:** A simple, customizable dashboard to access all homelab services.
*   [**Nginx Proxy Manager (NPM):**](./control_lxc/npm/npm.md) Manages reverse proxying, SSL certificates (Let's Encrypt), and custom domain routing for services, particularly those exposed via Cloudflared.
*   [**Portainer CE (Main Instance):**](./control_lxc/README.md#3-portainer-installation) Docker container management UI for all Docker hosts.
*   [**Tailscale:**](./control_lxc/tailscale/tailscale.md) Provides secure VPN access to the LXC and potentially acts as a subnet router or exit node for the homelab network.
*   **Uptime Kuma:** Monitors the availability of all critical services.

#### `cf_vm` (Cloudflare-Exposed VM)

Services hosted on this VM are intended for public access via Cloudflare Tunnel:

*   **SearXNG:** A privacy-respecting metasearch engine.
*   **Nextcloud:** Personal cloud storage, file sharing, and collaboration platform.
*   **Open WebUI:** A user-friendly web interface for interacting with local Large Language Models (LLMs).
*   **Gluetun:** Containerized VPN client routing outbound traffic for other VM services (e.g. SearXNG).

#### `ts_vm` (Tailscale-Accessible VM)

Services on this VM are for private use and accessed securely via Tailscale:

*   **Immich:** Self-hosted photo and video backup solution.
*   **Vaultwarden:** Self-hosted Bitwarden-compatible password manager.

## Future Plans & Contributions

This homelab is an evolving project. Future additions currently planned include:

*   A **Torrenting Stack** (e.g., qBittorrent with Gluetun for VPN).
*   The **\*Arr Stack** (Sonarr, Radarr, Lidarr, Prowlarr, etc.) for media management.

As mentioned, constructive feedback, suggestions for alternative configurations, or ideas for new services are always welcome.
