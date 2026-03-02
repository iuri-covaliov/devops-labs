# Lab 2 --- GitLab Behind Cloudflare Tunnel (Host Nginx Design)

This lab builds on [**Lab 1 (GitLab behind Cloudflare Access)**](../GitLabSE-behind-CloudFlare/docs/step-by-step.md) and
introduces:

-   Cloudflare Tunnel for HTTP
-   Cloudflare Tunnel for SSH
-   No architectural changes to host Nginx
-   Disposable VM support
-   No required firewall changes

------------------------------------------------------------------------

## Prerequisites

-   Lab 1 fully working (GitLab + Nginx + HTTPS + Cloudflare Access)
-   Domain managed in Cloudflare
-   Host has outbound internet access
-   GitLab VM reachable from host

------------------------------------------------------------------------

# Conventions and Placeholders

Use consistent variables:

``` bash
export GITLAB_VM_IP="192.168.56.101"
export GITLAB_DOMAIN="gitlab.yourdomain.com"
```

Confirm:

``` bash
echo "$GITLAB_VM_IP $GITLAB_DOMAIN"
```

------------------------------------------------------------------------

# Phase 1 --- Install and Authenticate Cloudflare Tunnel

## 1. Install cloudflared (Host)

``` bash
sudo apt update
sudo apt install -y curl gnupg lsb-release
```

``` bash
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo gpg --dearmor -o /usr/share/keyrings/cloudflare-main.gpg
echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/cloudflared.list
sudo apt update
sudo apt install -y cloudflared
```

Verify:

``` bash
cloudflared --version
```

------------------------------------------------------------------------

## 2. Authenticate Host (Headless-Safe)

``` bash
cloudflared tunnel login
```

If the host has no browser:

-   Copy printed URL
-   Open it on your local machine
-   Log in via Google
-   Select zone
-   Approve

Certificate appears automatically on the host.

Verify:

``` bash
ls ~/.cloudflared
```

Expected:

    cert.pem

------------------------------------------------------------------------

# Phase 2 --- Create and Configure Tunnel

## 3. Create Tunnel

``` bash
cloudflared tunnel create gitlab-tn
```

Get UUID:

``` bash
cloudflared tunnel list
```

Copy the Tunnel ID (UUID).

------------------------------------------------------------------------

## 4. Prepare Service Credentials

``` bash
sudo mkdir -p /etc/cloudflared
sudo install -m 0644 ~/.cloudflared/<TUNNEL_UUID>.json /etc/cloudflared/<TUNNEL_UUID>.json
```

------------------------------------------------------------------------

## 5. Create /etc/cloudflared/config.yml

``` yaml
tunnel: <TUNNEL_UUID>
credentials-file: /etc/cloudflared/<TUNNEL_UUID>.json

ingress:
  - hostname: <GITLAB_DOMAIN>
    service: http://127.0.0.1:80

  - hostname: ssh-<GITLAB_DOMAIN>
    service: ssh://<GITLAB_VM_IP>:22

  - service: http_status:404
```

Validate:

``` bash
sudo cloudflared tunnel ingress validate --config /etc/cloudflared/config.yml
```

------------------------------------------------------------------------

## 6. Create DNS Records

``` bash
cloudflared tunnel route dns gitlab-tn ${GITLAB_DOMAIN}
cloudflared tunnel route dns gitlab-tn ssh-${GITLAB_DOMAIN}
```

Verify in Cloudflare DNS dashboard that both records exist and are
proxied.

------------------------------------------------------------------------

# Phase 3 --- Run Tunnel as a Service

``` bash
sudo cloudflared service install
sudo systemctl enable cloudflared
sudo systemctl restart cloudflared
```

Check:

``` bash
sudo systemctl status cloudflared --no-pager
sudo journalctl -u cloudflared -n 50 --no-pager
```

------------------------------------------------------------------------

# Phase 4 --- Validate HTTP

Open in an incognito browser:

    https://<GITLAB_DOMAIN>

Expected:

-   Cloudflare Access login
-   Redirect to GitHub
-   GitLab UI loads

Host validation:

``` bash
curl -I http://127.0.0.1
```

------------------------------------------------------------------------

# Phase 5 --- Configure SSH Access

## 7. Create SSH Access Application

Cloudflare Zero Trust:

Access → Applications → Add application → Self-hosted

Public hostname:

    ssh-<GITLAB_DOMAIN>

Policy (recommended for lab):

    Include → Login Methods → GitHub
> This assumes GitHub is already configured under
> Zero Trust → Integrations → Identity Providers.

Save configuration.

This configuration means:
- SSH access requires Cloudflare Access authentication
- Authentication must be performed via GitHub
- Identity is enforced before SSH reaches the VM

------------------------------------------------------------------------

## 8. Configure SSH on Laptop

### Create SSH key:

``` bash
ssh-keygen -t ed25519 -C "<EMAIL>"
```

### Add public key to GitLab:

GitLab SE -> Your user -> Edit profile -> SSH Keys -> Add new key

------------------------------------------------------------------------

### Configure SSH client

Edit `~/.ssh/config`:

``` ssh
Host <GITLAB_DOMAIN>
  User git
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
  ProxyCommand cloudflared access ssh --hostname ssh-<GITLAB_DOMAIN>
```

------------------------------------------------------------------------

## 9. Test SSH

``` bash
ssh -T git@${GITLAB_DOMAIN}
```

Expected:

    Welcome to GitLab, @yourusername!

------------------------------------------------------------------------

## 10. Test Git Clone

``` bash
git clone git@${GITLAB_DOMAIN}:group/repo.git
```

------------------------------------------------------------------------

# VM Recreation Note

If you destroy and recreate the VM:

SSH host keys will change.

Fix locally:

``` bash
ssh-keygen -R "${GITLAB_DOMAIN}"
```

Reconnect and accept the new fingerprint.

------------------------------------------------------------------------

# Validation Checklist

-   cloudflared service active after reboot
-   DNS records exist
-   HTTP works via Access
-   SSH works via Access
-   Git clone works
-   Survives VM recreation

------------------------------------------------------------------------

# Troubleshooting

### websocket: bad handshake

Wrong hostname used for SSH. Ensure ProxyCommand uses:

    ssh-<GITLAB_DOMAIN>

------------------------------------------------------------------------

### Permission denied (publickey)

SSH key not added to GitLab or wrong IdentityFile specified.

------------------------------------------------------------------------

### Tunnel service fails on boot

Verify:

-   Correct Tunnel UUID
-   Correct credentials-file path
-   /etc/cloudflared/config.yml exists

------------------------------------------------------------------------

# Scope and Notes

-   Firewall changes are not required.
-   Tunnel model allows full inbound closure if desired.
-   Architecture separates HTTP and SSH ingress cleanly.
-   VM remains fully disposable.
