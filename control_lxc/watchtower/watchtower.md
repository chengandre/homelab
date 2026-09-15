# Watchtower

Watchtower monitors Docker containers on the host where it runs and automatically updates them to the latest image version available. This repository runs one Watchtower instance on the Control LXC and one inside each VM stack; each instance controls only the Docker host whose socket it mounts.

---

**Table of Contents:**

1.  [LXC Container Creation in Proxmox](../README.md#1-lxc-container-creation-in-proxmox)
2.  [Initial LXC configuration](../README.md#2-initial-lxc-configuration)
3.  [Portainer Installation](../README.md#3-portainer-installation)
4.  [Nginx Proxy Manager Installation](../npm/npm.md)
5.  [Cloudflared Installation](../cloudflared/cloudflared.md)
6.  [Tailscale Installation](../tailscale/tailscale.md)
7.  [Other Services Installation](../README.md#7-other-services-installation)

---

## 1. Optional: Configuring Discord Notifications

If you want Watchtower to send notifications to a Discord channel when it updates a container, follow these steps:

1.  **Open Discord and Navigate to Server Settings:**
    *   Go to the Discord server where you want to receive notifications.
    *   Open **Server Settings**
2.  **Access Integrations:**
    *   In the server settings menu, select **"Integrations"**.
3.  **Create a Webhook:**
    *   Click on **"Webhooks"**
    *   Click **"New Webhook"**.
    *   Give your webhook a descriptive name (e.g., "Watchtower Updates").
    *   Choose the channel where notifications should be posted.
    *   Click **"Copy Webhook URL"**. This URL will look like: `https://discord.com/api/webhooks/<channel>/<token>`.
4.  **Create the Shoutrrr value:** Convert the webhook to Watchtower's `discord://<token>@<channel>` format and store it securely. The Control LXC uses the `DISCORD_URL` stack variable; the `cf_vm` and `ts_vm` stacks use `WT_NOTIF_URL`.

---

## 2. Deploying Watchtower via Portainer

**Steps:**

1.  **Open Portainer:** In the central Portainer UI, select the Control LXC environment and open **Stacks → Add stack**.
2.  **Create the stack:** Enter a stack name, choose **Web editor**, and paste the [Watchtower Compose file](./wt-docker-compose.yml).
3.  **Prepare variables:** Copy [`.env.example`](./.env.example) to a private `.env` file. Set `DISCORD_URL` to the Shoutrrr value if notifications are enabled and set `TZ` to your chosen IANA timezone. Under **Environment variables**, choose **Load variables from .env file** and upload that private file.
4.  **Deploy the stack:** Click **Deploy the stack**. The Compose file mounts the Control LXC Docker socket, so this instance monitors containers on the Control LXC only.
5.  **Verify:** Confirm `watchtower_lxc` is running and inspect its logs. The schedule is 09:00 daily in the configured `TZ`; notification delivery and an update remain separate live checks.

For the VM stacks, use the existing Watchtower service in each VM's Compose file. Set `WT_NOTIF_URL` and `TZ` in that VM's private stack environment; do not deploy the Control LXC Compose file into a VM.
