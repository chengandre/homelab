# Watchtower

Watchtower monitors your running Docker containers and automatically updates them to the latest image version available. This helps keep your services up-to-date with new features and security patches.

---

**Table of Contents:**

1.  [LXC Container Creation in Proxmox](../README.md#1-lxc-container-creation-in-proxmox)
2.  [Initial LXC configuration](../README.md#2-initial-lxc-configuration)
3.  [Portainer Installation](../README.md#portainer-installation)
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
4.  **Save the Webhook URL:** Store this URL securely; you will need it for Watchtower's configuration.

---

## 2. Deploying Watchtower via Portainer

**Steps:**

1.  Create a new stack in Portainer and assign it a name of your choice
3.  Copy the content from [Watchtower Docker Compose file](./wt-docker-compose.yml) and paste it into Portainer's **Web editor**.
4.  **For Discord Notifications:** Add the environment variable `WATCHTOWER_NOTIFICATION_URL`. The value should be your full Discord Webhook URL copied formatted as: `discord://<token>@<channel>` (order swapped). You can check out the [Official Documentation](https://containrrr.dev/watchtower/notifications/).
5.  **Deploy the Stack:**

Watchtower will now start and, based on its schedule, begin monitoring your other running containers for updates.
