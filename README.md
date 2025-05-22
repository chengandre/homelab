# My Homelab

This repository serves as a comprehensive documentation hub for my personal homelab setup. All configurations and choices are tailored to my specific needs and learning objectives. However, I welcome suggestions for improvements, alternative approaches, or new services that could enhance this environment.

## Core Architecture

My homelab is built upon a foundation of **Proxmox VE** for virtualization. Centralized storage is managed by **TrueNAS**, utilizing **ZFS** with a **RAID-Z2** configuration for data redundancy and integrity. A key principle of this setup is that persistent data for all hosted services is stored on TrueNAS datasets and made available to the virtualized environments via **NFS shares**.

## Virtualized Environments

Beyond the TrueNAS instance, the current Proxmox setup includes:

*   **A Control LXC Container:**
    *   **OS:** Debian 11 (Bullseye)
    *   **Role:** This container acts as a central management and routing point. It handles incoming requests, monitors the health of other VMs, and hosts various network-wide utility services.
*   **Two Virtual Machines (VMs):**
    *   **`cf_vm` (Cloudflare Exposed VM):**
        *   **OS:** Debian 12 (Bookworm)
        *   **Role:** Hosts services intended to be accessible from the internet. Access is secured and managed via **Cloudflare Tunnel**.
    *   **`ts_vm` (Tailscale Accessible VM):**
        *   **OS:** Debian 12 (Bookworm)
        *   **Role:** Hosts private services that are only accessible via my **Tailscale** private network.

## Hosted Services

The services are all deployed in Docker containers using **Portainer CE** for easier management and orchestration. Below is a breakdown of these services.

### Common Utility Services

The following utility services are deployed on most, if not all, virtualized environments (LXC and VMs) to ensure consistent operation, monitoring, and maintenance:

*   **Glances:** System monitoring dashboard providing a quick overview of resource usage on each host.
*   **Portainer Agent:** Allows the central Portainer CE instance (running on the Control LXC) to manage Docker environments on the respective VMs. *(The Control LXC runs the main Portainer CE instance).*
*   **Watchtower:** Automatically updates running Docker containers to their latest versions on each host where it's deployed.

### Services by Host

#### Control LXC (`control-lxc`)

This LXC container is responsible for overall management, monitoring, and secure access:

*   **Cloudflared:** Manages the secure tunnel to Cloudflare for exposing public services.
*   **Homepage:** A simple, customizable dashboard to access all homelab services.
*   **Nginx Proxy Manager (NPM):** Manages reverse proxying, SSL certificates (Let's Encrypt), and custom domain routing for services, particularly those exposed via Cloudflared.
*   **Portainer CE (Main Instance):** Docker container management UI for all Docker hosts.
*   **Tailscale:** Provides secure VPN access to the LXC and potentially acts as a subnet router or exit node for the homelab network.
*   **Uptime Kuma:** Monitors the availability of all critical services.

#### `cf_vm` (Cloudflare Exposed VM)

Services hosted on this VM are intended for public access via Cloudflare Tunnel:

*   **SearXNG:** A privacy-respecting metasearch engine.
*   **Nextcloud:** Personal cloud storage, file sharing, and collaboration platform.
*   **OpenWebUI:** A user-friendly web interface for interacting with local Large Language Models (LLMs).

#### `ts_vm` (Tailscale Accessible VM)

Services on this VM are for private use and accessed securely via Tailscale:

*   **Immich:** Self-hosted photo and video backup solution.
*   **Vaultwarden:** Self-hosted Bitwarden-compatible password manager.

## Future Plans & Contributions

This homelab is an evolving project. Future additions currently planned include:

*   A **Torrenting Stack** (e.g., qBittorrent with Gluetun for VPN).
*   The **\*Arr Stack** (Sonarr, Radarr, Lidarr, Prowlarr, etc.) for media management.

As mentioned, constructive feedback, suggestions for alternative configurations, or ideas for new services are always welcome. Please feel free to open an issue or submit a pull request if you have ideas for improvement.