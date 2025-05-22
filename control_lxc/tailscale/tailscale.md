# Tailscale VPN Service

Tailscale provides a secure virtual private network (VPN) solution, enabling access to services within this LXC container (and other devices on your Tailnet) without requiring open inbound ports on your router. It creates a peer-to-peer mesh network.


### 1. Prerequisites for LXC Deployment

To run Tailscale effectively within an **unprivileged LXC container** on Proxmox VE, we need to do the following steps:

1.  Edit the LXC configuration file located at `/etc/pve/lxc/<LXC_ID>.conf`. For example, if your LXC ID is `101`:
    ```bash
    nano /etc/pve/lxc/101.conf
    ```
2.  Add the following lines to the end of this file, as per the [official Tailscale LXC documentation](https://tailscale.com/kb/1130/lxc-unprivileged):
    ```ini
    lxc.cgroup2.devices.allow: c 10:200 rwm
    lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file
    ```

3.  Save the configuration file (Ctrl-O, Enter, Ctrl-X).
4.  **Restart the LXC container** from the Proxmox UI for these changes to take effect.

---

### 2. Generating a Tailscale Authentication Key

An authentication key allows the Tailscale service within your LXC to join your Tailnet (your private Tailscale network) without interactive login.

**Steps:**

1.  Log in to your [Tailscale Admin Console](https://login.tailscale.com/admin/machines).
2.  Navigate to **Settings**->**Keys** and generate a new authentication key.
3.  **Configure the key:** You can choose it to be reusable and its expiration period.
7.  **Copy the generated key** (e.g., `tskey-auth-kEXAMPLE...`).

---

### 3. Deploying Tailscale via Portainer

1.  Create a new stack in Portainer and give it a name of your choice.
2.  In the Web editor, copy and paste the content from the [Tailscale Docker Compose file](./ts-docker-compose.yml).
3.  Add the env variables as in the [env file](./.env), choose your desired path, and input your generated auth key.
4.  **Deploy the stack.**

Once deployed, the Tailscale container should start and appear in your Tailscale Admin Console under "Machines".

---

### 4. Firewall Configuration for Tailscale Access

To allow traffic originating from your Tailnet to reach services running *within this LXC container*, you need to add specific UFW rules. The Tailscale service creates a virtual network interface, typically named `tailscale0`.

**Add UFW Rules (Inside the LXC Console):**

```bash
sudo ufw allow in on tailscale0 to any port 81 proto tcp comment 'NPM Web UI (Tailscale)'

sudo ufw allow in on tailscale0 to any port 22 proto tcp comment 'SSH (Tailscale)'
```

---