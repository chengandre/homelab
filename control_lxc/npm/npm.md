## Nginx Proxy Manager (NPM)

NPM acts as a reverse proxy, providing a single entry point for external requests and routing them to the appropriate backend services.

**Table of Contents:**

1.  [LXC Container Creation in Proxmox](../README.md#1-lxc-container-creation-in-proxmox)
2.  [Initial LXC configuration](../README.md#2-initial-lxc-configuration)
3.  [Portainer Installation](../README.md#3-portainer-installation)
4.  [Nginx Proxy Manager Installation](../npm/npm.md)
5.  [Cloudflared Installation](../cloudflared/cloudflared.md)
6.  [Tailscale Installation](../tailscale/tailscale.md)
7.  [Other Services Installation](../README.md#7-other-services-installation)

### 1. Deployment

1.  Navigate to **Stacks** in Portainer and click **"+ Add stack"**.
2.  **Name:** `npm` (or anything you want).
3.  **Web editor:** Copy the content from the [NPM Docker Compose file](./npm-docker-compose.yml).
4.  **Environment Variables:** Copy [`.env.example`](./.env.example) to `.env`, set the host paths for `DATA_PATH` and `LETSENCRYPT_PATH`, and load the private `.env` file when deploying the stack.
5.  **Deploy the stack.**
    *Note: The provided Compose file defines the shared external Docker network as `proxy_net`; Cloudflared must join that same network to reach NPM by container name.*

### 2. Access & Firewall Rules

*   NPM Admin UI: `http://<LXC_IP>:81`
*   On first login, enter the administrator email address and a strong administrator password when prompted, save the form, and confirm that the NPM dashboard opens. Keep these credentials private.
*   Add UFW rules:
    ```bash
    sudo ufw allow 80/tcp comment 'NPM HTTP'
    sudo ufw allow 443/tcp comment 'NPM HTTPS'
    sudo ufw allow from <LAN_SUBNET> to any port 81 proto tcp comment 'NPM Web UI (LAN)'
    ```
    Replace `<LAN_SUBNET>` with your LAN range, such as `192.168.1.0/24`.
