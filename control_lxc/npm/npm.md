## Nginx Proxy Manager (NPM)

NPM acts as a reverse proxy, providing a single entry point for external requests and routing them to the appropriate backend services.

**Table of Contents:**

1.  [LXC Container Creation in Proxmox](../README.md#1-lxc-container-creation-in-proxmox)
2.  [Initial LXC configuration](../README.md#2-initial-lxc-configuration)
3.  [Portainer Installation](../README.md#portainer-installation)
4.  [Nginx Proxy Manager Installation](../npm/npm.md)
5.  [Cloudflared Installation](../cloudflared/cloudflared.md)
6.  [Tailscale Installation](../tailscale/tailscale.md)
7.  [Other Services Installation](../README.md#7-other-services-installation)

### 1. Deployment

1.  Navigate to **Stacks** in Portainer and click **"+ Add stack"**.
2.  **Name:** `npm` (or anything you want).
3.  **Web editor:** Copy the content from the [NPM Docker Compose file](./npm-docker-compose.yml).
4.  **Environment Variables:** Upload the [env file](./.env) and add in your paths.
5.  **Deploy the stack.**
    *Note: The provided NPM `docker-compose.yml` should define a Docker network (e.g., `proxy_network`) for inter-container communication.*

### 2. Access & Firewall Rules

*   NPM Admin UI: `http://<LXC_IP>:81`
*   Complete initial admin setup.
*   Add UFW rules:
    ```bash
    sudo ufw allow 80/tcp comment 'NPM HTTP'
    sudo ufw allow 443/tcp comment 'NPM HTTPS'
    sudo ufw allow from 192.168.1.0/24 to any port 81 proto tcp comment 'NPM Web UI (LAN)'
    ```
