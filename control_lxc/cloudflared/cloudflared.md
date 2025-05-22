# Cloudflared

Cloudflared creates a secure tunnel from Cloudflare's edge to services running in this LXC, exposing them without opening inbound ports on your router.

**Table of Contents:**

1.  [LXC Container Creation in Proxmox](../README.md#1-lxc-container-creation-in-proxmox)
2.  [Initial LXC configuration](../README.md#2-initial-lxc-configuration)
3.  [Portainer Installation](../README.md#portainer-installation)
4.  [Nginx Proxy Manager Installation](../npm/npm.md)
5.  [Cloudflared Installation](../cloudflared/cloudflared.md)
6.  [Tailscale Installation](../tailscale/notes.md)
7.  [Other Services Installation](./README.md#other-services)

### 1. Prerequisites

*   **Domain Name:** A registered domain managed through Cloudflare (e.g., `yourdomain.com`). You can obtain one via [Cloudflare Registrar](https://domains.cloudflare.com/).

### 2. Cloudflare Dashboard Configuration

1.  **Enable "Always Use HTTPS":**
    *   Cloudflare Dashboard -> Your Domain -> SSL/TLS -> Edge Certificates -> Enable "Always Use HTTPS".

2.  **Block Countries/Regions (Optional):**
    *   Cloudflare Dashboard -> Your Domain -> Security -> Security rules -> Create a custom rule.
    *   **Name:** e.g., "Block Undesired Regions".
    *   **Field:** Country.
    *   **Operator:** `is in`.
    *   **Value:** Select the countries to block, then **Action:** Block.
    *   Alternatively, create an "Allow" rule for specific countries and block others.
3.  **Configure Authentication (Example: Google):**
    *   This enables stronger authentication for the tunnel.
    *   Cloudflare Dashboard -> Zero Trust -> Settings -> Authentication.
    *   Click "Add new" for Login Methods and follow the guide for your chosen provider (e.g., Google).
    *   **Access Policies (Optional but Recommended):**
        *   Zero Trust Dashboard -> Access -> Policies.
        *   Create two policies for applications you'll define later:
            1.  **Allow Policy:** Action: `Allow`, Session Duration: (e.g., `1 week`), Configure Rules: You can select emails and add the emails you want to give access to.
            2.  **Deny All Policy:** Action: `Block`, Configure Rules: `Everyone`.
        *   *These policies will be applied to applications later; order will matter then.*

### 3. Tunnel Creation & Deployment

1.  **Create Tunnel in Cloudflare:**
    *   Zero Trust Dashboard -> Networks -> Tunnels -> "+ Create a tunnel".
    *   Connector: Choose "Cloudflared".
    *   Give the tunnel a name (e.g., `homelab`). Save tunnel.
    *   Choose "Docker" as the environment.
    *   **Copy the provided `docker run cloudflared tunnel --no-autoupdate run --token <YOUR_TUNNEL_TOKEN>` command.** Extract the `<YOUR_TUNNEL_TOKEN>` value.

2.  **Deploy Cloudflared Stack in Portainer:**
    *   Create a new stack (e.g., `cloudflared`).
    *   Copy content from [Cloudflared Docker Compose file](./cf-docker-compose.yml) into the web editor.
    *   Load environment variables from [env](./.env), ensuring you input the `TUNNEL_TOKEN` obtained above.
    *   Deploy the stack.

3.  **Configure Public Hostname in Cloudflare Tunnel:**
    *   Back in the Cloudflare Tunnel setup, on the next page, add a new public hostname:
        *   **Subdomain/Domain:** e.g. `yourdomain.com`.
        *   **Service Type:** `HTTPS`.
        *   **URL:** `npm:443` (assuming your NPM container is named `npm` and is on the same Docker network as Cloudflared).
        *   **Additional application settings -> TLS:**
            *   Enable **"No TLS Verify"** (NPM will handle SSL termination with a valid certificate).
            *   **Origin Server Name:** Enter the public hostname you are configuring (e.g., `yourdomain.com`).
    *   Save the hostname. Repeat for any other services you want to expose directly via the tunnel to NPM in the future/
    * If you go back to Tunnels, you should see that the one you've just created is healthy.

### 4. Cloudflare Application (Access Control)

1.  **Create Application:**
    *   Zero Trust Dashboard -> Access -> Applications -> "+ Add an application".
    *   Choose "Self-hosted".
2.  **Configuration:**
    *   **Application Name:** e.g., "Homelab".
    *   **Session Duration:** e.g., "24 hours".
    *   **Application Domain:** Add the public hostnames configured in your tunnel (e.g., `yourdomain.com`). Leave the input method to Default.
3.  **Policies:**
    *   Add the "Allow" and "Deny All" policies created earlier.
    *   **Order Matters:** Ensure the "Allow" policy is listed *before* the "Deny All" policy.
    *   Leave other settings at their defaults unless specific adjustments are needed.
4.  **Save the application.**

You should now be able to access your configured domain(s), authenticate via Cloudflare Access, and see the NPM "Congratulations" page if no proxy hosts are set up yet in NPM.

### 5. SSL Certificate for NPM via Cloudflare DNS

To enable NPM to issue valid Let's Encrypt certificates for your services using Cloudflare's DNS.

1.  **Create Cloudflare API Token:**
    *   Cloudflare Main Dashboard -> User Icon (top right) -> "Profile" -> "API Tokens" -> "Create Token".
    *   Use the "Edit zone DNS" template.
    *   **Permissions:** Ensure "Zone" - "DNS" - "Edit".
    *   **Zone Resources:** Select "Include" - "Specific zone" - `yourdomain.com`.
    *   Continue to summary and create the token. **Copy the generated token immediately.**

2.  **Configure DNS Challenge in NPM:**
    *   Access NPM Admin UI (`http://<LXC_IP>:81`).
    *   Go to "SSL Certificates" -> "Add SSL Certificate" -> "Let's Encrypt".
    *   **Domain Names:** Enter a wildcard for your domain (e.g., `*.yourdomain.com`) and your root domain (e.g., `yourdomain.com`). This allows one certificate to cover all subdomains.
    *   **Email Address for Let's Encrypt:** Your email.
    *   **Use a DNS Challenge:** Enable this.
    *   **DNS Provider:** Select "Cloudflare".
    *   **API Token:** In the text area, paste:
        ```ini
        dns_cloudflare_api_token = <YOUR_CLOUDFLARE_API_TOKEN_HERE>
        ```
    *   **Save**.

NPM should now be able to acquire SSL certificates for any proxy hosts you set up under `yourdomain.com`.