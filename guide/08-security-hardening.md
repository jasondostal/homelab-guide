# Chapter 08: Security Hardening and Defense in Depth

"It's just a homelab." That sentence has preceded more compromised networks than any zero-day exploit. Your homelab runs on your home network. Your home network has your personal devices, your family's devices, your banking sessions, your private data. A compromised homelab container is a foothold into all of that.

Security isn't a feature you bolt on at the end. It's a set of decisions you make at every layer, each one reducing the blast radius of the inevitable failure. Because something will fail. A container will have a vulnerability. A password will be weak. A port will be exposed that shouldn't be. The question isn't whether a layer will be breached — it's whether the next layer holds.

That's defense in depth.

---

## The Layer Model

Think of your homelab security as concentric rings. An attacker (or an accident) has to penetrate each layer to reach your data:

```
+-----------------------------------------------------------+
|  Layer 0: Network Edge                                     |
|  Router firewall, VLANs, no unnecessary inbound ports      |
|                                                             |
|  +-------------------------------------------------------+ |
|  |  Layer 1: Reverse Proxy                                | |
|  |  SWAG, TLS termination, fail2ban, rate limiting        | |
|  |                                                         | |
|  |  +---------------------------------------------------+ | |
|  |  |  Layer 2: Docker Network Isolation                 | | |
|  |  |  Custom networks, no --net=host, scoped exposure   | | |
|  |  |                                                     | | |
|  |  |  +-----------------------------------------------+ | | |
|  |  |  |  Layer 3: Container Configuration              | | | |
|  |  |  |  Read-only FS, dropped caps, non-root user     | | | |
|  |  |  |                                                 | | | |
|  |  |  |  +-----------------------------------------+   | | | |
|  |  |  |  |  Layer 4: Application Auth               |   | | | |
|  |  |  |  |  SSO, per-service auth, API keys         |   | | | |
|  |  |  |  |                                           |   | | | |
|  |  |  |  |  +-----------------------------------+   |   | | | |
|  |  |  |  |  |  Layer 5: Data Protection          |   |   | | | |
|  |  |  |  |  |  Encryption at rest + in transit   |   |   | | | |
|  |  |  |  |  |  Encrypted backups, secrets mgmt  |   |   | | | |
|  |  |  |  |  +-----------------------------------+   |   | | | |
|  |  |  |  +-----------------------------------------+   | | | |
|  |  |  +-----------------------------------------------+ | | |
|  |  +---------------------------------------------------+ | |
|  +-------------------------------------------------------+ |
+-----------------------------------------------------------+
```

No single layer is trusted completely. Each one assumes the layers outside it have already been breached.

---

## Layer 0: Network Edge

Your router is your first wall. Configure it like one.

### What Your Router/Firewall Should Do

- **Block all unsolicited inbound traffic.** Nothing from the internet should reach your homelab unless it goes through your reverse proxy (ports 80/443) or your VPN. That's it. Two entry points, maximum.
- **Disable UPnP.** UPnP lets devices on your network automatically open ports on your router. This is a convenience feature that services and malware alike can exploit. Turn it off. If something needs a port forwarded, do it manually and document it.
- **VLAN segmentation.** If your router supports VLANs (most prosumer gear does — UniFi, pfSense, OPNsense, MikroTik), put your homelab on its own VLAN. This means a compromised container can't directly reach your personal devices on the main network. At minimum, separate IoT devices, your homelab, and your personal devices.
- **DNS filtering.** Run Pi-hole or AdGuard Home (which you probably already have if you're reading a homelab guide) and use it for basic DNS-level blocking.

### What About Exposing Services to the Internet?

The safest answer: don't. Use a VPN (Tailscale or WireGuard) to access your homelab remotely. This means zero inbound ports, zero attack surface from the internet.

If you must expose services (maybe you're hosting something for others, or you want HTTPS access without a VPN):

- Only ports 80 and 443 through the reverse proxy. Nothing else.
- Every exposed service goes through the reverse proxy. No exceptions.
- fail2ban watches every exposed endpoint.
- Consider Cloudflare Tunnel as an alternative to port forwarding — it establishes an outbound connection, so no inbound ports needed.

---

## Layer 1: Reverse Proxy (SWAG)

This was covered in depth in Chapter 04, but it's worth reinforcing the security-relevant points:

- **TLS everywhere.** Every service, even internal ones accessed through the proxy, gets HTTPS. Let's Encrypt makes this free and automatic.
- **fail2ban is not optional.** It watches your access logs and bans IPs that show patterns of abuse (brute force attempts, vulnerability scanning, repeated 401s). SWAG ships with fail2ban baked in.
- **Security headers.** SWAG's default nginx configs include headers like `X-Content-Type-Options`, `X-Frame-Options`, `Strict-Transport-Security`, and `Referrer-Policy`. Don't remove them.
- **Rate limiting.** For any service exposed to the internet, configure rate limits in the nginx location block. A legitimate user doesn't need to make 100 requests per second.

```nginx
location / {
    limit_req zone=default burst=20 nodelay;
    # ... proxy_pass config
}
```

---

## Layer 2: Docker Network Isolation

This is where most homelabbers fall down. Docker's default networking is permissive by design — it optimizes for "things just work" over "things are secure." You need to push back on those defaults.

### Never Use --net=host (Almost Never)

`--net=host` removes all network isolation between the container and the host. The container shares the host's network stack, can see all ports, can bind to any interface. It's the networking equivalent of `--privileged`.

Valid use cases for `--net=host`:
- Network monitoring tools that need to see all host traffic (rare)
- Some DHCP/DNS servers that need to bind to specific interfaces
- Performance-critical applications where Docker's NAT overhead matters (measure first)

That's about it. If you're using `--net=host` because "it was easier," you're trading security for convenience.

### Create Purpose-Specific Networks

Don't put all your containers on one network. Segment them by function:

```yaml
networks:
  frontend:    # Reverse proxy and web-facing services
    driver: bridge
  backend:     # Application servers, API services
    driver: bridge
  database:    # Database servers only
    driver: bridge
  monitoring:  # Prometheus, Grafana, exporters
    driver: bridge
```

Then assign containers to only the networks they need:

```yaml
services:
  webapp:
    networks:
      - frontend
      - backend    # Needs to talk to API services
      # NOT on database network — talks to DB through backend API

  api:
    networks:
      - backend
      - database   # Needs direct DB access

  postgres:
    networks:
      - database   # Only reachable from database network
```

A compromised webapp container can reach the API but can't directly connect to Postgres. That's the point.

### Don't Expose Ports to 0.0.0.0

When you write `ports: - "8080:80"`, Docker binds that port to `0.0.0.0` — all interfaces. Your container is now accessible from any network your host is on.

If a service only needs to be reached by other containers on the same host, or through the reverse proxy, bind it to localhost:

```yaml
ports:
  - "127.0.0.1:8080:80"   # Only reachable from the host itself
```

If a service only needs to be reached by other containers, don't expose a port at all. Containers on the same Docker network can communicate using the service name as a hostname — that's Docker's internal DNS.

```yaml
services:
  api:
    # No 'ports' section at all — only reachable from other containers on the same network
    networks:
      - backend

  webapp:
    networks:
      - backend
    # Can reach 'api' at http://api:80 through Docker's internal DNS
```

---

## Layer 3: Container Configuration

Every container should be locked down to the minimum permissions it needs.

### Read-Only Root Filesystem

Most containers don't need to write to their root filesystem. They write to mounted volumes and tmpfs. Make the root read-only:

```yaml
services:
  myapp:
    read_only: true
    tmpfs:
      - /tmp
      - /run
    volumes:
      - app_data:/data   # Writable volume for actual data
```

If the container crashes because it can't write somewhere unexpected, that tells you something useful about what that container is doing. Add specific tmpfs mounts for the directories it needs.

### Drop All Capabilities, Add Back Selectively

Linux capabilities are fine-grained permissions that replace the blunt "root or not root" distinction. Docker grants containers a default set of capabilities that most don't need.

```yaml
services:
  myapp:
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE   # Only if it needs to bind to ports below 1024
```

Common capabilities you might need to add back:

| Capability | When You Need It |
|------------|-----------------|
| `NET_BIND_SERVICE` | Binding to ports < 1024 |
| `CHOWN` | Changing file ownership at startup |
| `SETUID` / `SETGID` | Running as a different user after startup |
| `DAC_OVERRIDE` | Bypassing file permission checks (try to avoid) |

If you're not sure what capabilities a container needs, start with `cap_drop: ALL` and add back one at a time when things break.

### Run as Non-Root

Most containers that run as root don't need to. The application inside runs fine as an unprivileged user — the image was just built lazily.

```yaml
services:
  myapp:
    user: "1000:1000"
```

Some images support this through environment variables:

```yaml
environment:
  PUID: 1000
  PGID: 1000
```

If an image truly requires root at startup (to bind a privileged port, for example), it should drop privileges after initialization. If it doesn't, consider whether there's an alternative image that does.

### No Privileged Mode

`privileged: true` gives a container full access to the host. All devices, all capabilities, all kernel modules. It's a complete bypass of container isolation.

Legitimate use cases:
- GPU passthrough (though `nvidia-container-toolkit` often avoids this)
- Running Docker-in-Docker (usually for CI/CD)
- Some system-level monitoring tools

That's it. If you find yourself reaching for `privileged: true`, stop and figure out the specific capability or device access the container actually needs. There's almost always a more targeted solution.

---

## Layer 4: Application Authentication

Even behind a reverse proxy and a firewall, services should authenticate their users. The proxy can go down. Network rules can be misconfigured. Defense in depth means every layer pulls its weight.

### Authelia vs. Authentik: Pick One

Both are self-hosted identity providers that give you SSO across your homelab services. They integrate with SWAG/nginx to intercept requests and require authentication before forwarding to the backend service.

**Authelia:**
- Lighter weight. Runs in a single container with a small footprint.
- Configuration is YAML-based. Less GUI, more infrastructure-as-code.
- Supports TOTP, WebAuthn, and push notifications for 2FA.
- Simpler to set up and maintain.
- Best for: Homelabs where you're the only user or you have a small number of users.

**Authentik:**
- Full-featured identity provider. SAML, OIDC, LDAP, SCIM.
- Web-based admin UI for managing users, groups, policies.
- More complex setup, more moving parts (separate worker, database).
- Best for: Homelabs with multiple users, or if you want to learn enterprise identity management.

For most homelabbers, **Authelia is the right choice.** It's simpler, lighter, and does what you need. Pick Authentik if you have specific requirements around SAML/OIDC integration or multi-user management.

Basic SWAG integration with Authelia:

```nginx
# In your SWAG site config
location / {
    include /config/nginx/authelia-location.conf;
    # If Authelia approves, proxy to the service
    include /config/nginx/proxy.conf;
    proxy_pass http://myservice:8080;
}
```

### Basic Auth as a Minimum

For services that don't justify a full SSO setup, SWAG can provide HTTP basic auth:

```bash
# Generate a password file
htpasswd -c /config/nginx/.htpasswd username
```

```nginx
location / {
    auth_basic "Restricted";
    auth_basic_user_file /config/nginx/.htpasswd;
    proxy_pass http://myservice:8080;
}
```

It's not glamorous. It works. It's infinitely better than no auth.

### API Key Rotation

If you're running services with API keys (your AI stack, webhook endpoints, service-to-service auth), rotate them periodically. Not because you know they've been compromised, but because you might not know.

Establish a cadence — quarterly is reasonable for a homelab. Put it in your maintenance calendar.

---

## Layer 5: Data Protection

### Encrypted Backups

If you followed Chapter 06, your backups are already encrypted with restic. If you skipped that chapter, go back. Unencrypted backups are a security liability — they contain everything an attacker wants, conveniently packaged in one place.

### Database Connections Over TLS

Most database Docker images support TLS connections. For Postgres:

```yaml
services:
  postgres:
    command: >
      -c ssl=on
      -c ssl_cert_file=/var/lib/postgresql/server.crt
      -c ssl_key_file=/var/lib/postgresql/server.key
    volumes:
      - ./certs/server.crt:/var/lib/postgresql/server.crt:ro
      - ./certs/server.key:/var/lib/postgresql/server.key:ro
```

Is this overkill for containers on the same Docker network? Maybe. But it costs almost nothing and protects against network-level attacks or misconfigured network segmentation. Defense in depth means not assuming other layers are intact.

### Secrets Management

There's a spectrum of approaches, from "good enough" to "enterprise":

**`.env` files** (minimum viable):
- Simple. One file per service or project.
- `chmod 600` the file. Add it to `.gitignore`. Don't commit it.
- Downside: secrets in plaintext on disk. Anyone with host access can read them.

**Docker Secrets** (better for Swarm, awkward for standalone):
- Docker's built-in secrets management. Mounts secrets as files in `/run/secrets/`.
- Works cleanly with Docker Swarm. In standalone Docker Compose, it's a bit clunky but functional.

```yaml
secrets:
  db_password:
    file: ./secrets/db_password.txt

services:
  postgres:
    secrets:
      - db_password
    environment:
      POSTGRES_PASSWORD_FILE: /run/secrets/db_password
```

**External vault (HashiCorp Vault, Bitwarden Secrets Manager)**:
- Centralized secret storage with access policies, audit logging, rotation.
- More complex to set up and maintain. Worth it if you have many services and multiple users.
- For most homelabs, this is aspirational. Get the basics right first.

> **The practical minimum:** `.env` files with `chmod 600`, in `.gitignore`, with a `.env.example` for documentation. That handles 90% of homelab use cases.

---

## SSH Hardening

SSH is your primary management interface. Lock it down accordingly.

### Key-Only Authentication

Disable password authentication entirely. SSH keys are not optional — they're the baseline.

```bash
# /etc/ssh/sshd_config
PasswordAuthentication no
PubkeyAuthentication yes
PermitRootLogin no
AuthenticationMethods publickey
```

Generate a key pair if you haven't:

```bash
ssh-keygen -t ed25519 -C "homelab-$(hostname)"
ssh-copy-id user@your-server
```

Use `ed25519` keys. They're shorter, faster, and more secure than RSA. There's no reason to use RSA for new key pairs in 2025.

### Non-Standard Port

Change SSH from port 22 to something else:

```bash
# /etc/ssh/sshd_config
Port 2222
```

Let's be clear: **this is not security.** Any serious attacker will port-scan and find it. But it eliminates 99% of automated brute-force attempts from bots that only try port 22, which means your logs are cleaner and fail2ban has less noise to filter through.

### fail2ban for SSH

```ini
# /etc/fail2ban/jail.local
[sshd]
enabled = true
port = 2222
maxretry = 3
bantime = 3600
findtime = 600
```

Three failed attempts in 10 minutes gets you banned for an hour. Adjust to taste, but don't be too lenient.

### Consider Not Exposing SSH at All

The best SSH hardening is not exposing SSH to the internet in the first place. Use Tailscale or WireGuard to create a VPN overlay network, and SSH only over that. Zero inbound ports. Zero attack surface.

```bash
# SSH over Tailscale — only accessible from your Tailnet
ssh user@homelab-server  # Using Tailscale hostname
```

This is the approach I'd recommend for anyone who doesn't have a specific reason to expose SSH publicly.

---

## Automatic Updates: Convenience vs. Control

### Host OS: Unattended Security Patches

Enable automatic security updates for the host OS. These are the patches that fix known, actively-exploited vulnerabilities. You don't want to be manually applying these.

```bash
sudo apt install unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades
```

Configure it to only install security updates, not general package upgrades:

```bash
# /etc/apt/apt.conf.d/50unattended-upgrades
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::Automatic-Reboot "false";  # Don't auto-reboot
Unattended-Upgrade::Mail "your@email.com";      # Get notified
```

Kernel updates and major version upgrades should still be manual. Read the changelogs. Reboot during a maintenance window.

### Container Updates: The Watchtower Dilemma

Watchtower automatically pulls new container images and restarts containers with the updated image. Sounds great. Here's the trade-off:

**The argument for auto-updates:**
- Security patches get applied immediately.
- You don't have to remember to check for updates.
- Most updates are minor and non-breaking.

**The argument against:**
- A bad image update at 3am takes down your service with no one watching.
- Database containers can require migration steps between versions. Auto-updating Postgres without running migrations is a recipe for data loss.
- You lose the ability to review changelogs before deploying.
- Rolling back is harder when you didn't notice the update happened.

**The middle ground (recommended):**

Run Watchtower in **monitor-only mode**. It checks for updates and notifies you, but doesn't automatically pull or restart anything:

```yaml
services:
  watchtower:
    image: containrrr/watchtower:latest
    container_name: watchtower
    restart: unless-stopped
    environment:
      WATCHTOWER_MONITOR_ONLY: "true"
      WATCHTOWER_NOTIFICATIONS: shoutrrr
      WATCHTOWER_NOTIFICATION_URL: "discord://token@webhookid"
      WATCHTOWER_SCHEDULE: "0 0 6 * * *"   # Check daily at 6am
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
```

You get notified when updates are available. You choose when to apply them. You read the changelog first. You update during a maintenance window. This is the adult way to do it.

---

## Vulnerability Scanning

### Trivy for Container Images

Trivy scans container images for known vulnerabilities in OS packages and application dependencies. Run it against your images:

```bash
# Scan a specific image
docker run --rm aquasec/trivy image postgres:16

# Scan all running container images
for img in $(docker ps --format '{{.Image}}' | sort -u); do
  echo "=== Scanning $img ==="
  docker run --rm aquasec/trivy image "$img"
done
```

Automate this on a schedule (weekly is reasonable) and review the output. Not every CVE is relevant to your usage, but high/critical vulnerabilities in packages your service actually uses should be addressed.

You can also run Trivy as a container on a schedule:

```yaml
services:
  trivy:
    image: aquasec/trivy:latest
    container_name: trivy-scanner
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - trivy_cache:/root/.cache/trivy
    entrypoint: ""
    command: >
      sh -c 'for img in $$(docker ps --format "{{.Image}}" | sort -u); do
        echo "=== $$img ===";
        trivy image --severity HIGH,CRITICAL "$$img";
      done'
    # Run via cron or a scheduling container
```

---

## The Principle of Least Privilege

This isn't a layer — it's the philosophy that runs through every layer. Every decision should start from "no access" and add only what's needed:

- **Network access:** If a container doesn't need to reach the internet, don't put it on a network that has internet access. If it only talks to one other service, put them on a dedicated network together.
- **Filesystem access:** Mount volumes read-only unless write access is required. Mount specific directories, not entire filesystems.
- **Capabilities:** Drop all, add back the minimum.
- **User permissions:** Run as non-root. Use the most restricted user possible.
- **Port exposure:** Don't expose ports that don't need to be exposed. Bind to `127.0.0.1` instead of `0.0.0.0`.
- **Secrets:** Give each service its own credentials with the minimum necessary permissions. Don't share a single admin database password across all services.

Every permission granted is attack surface. Be stingy.

---

## Common Homelab Security Mistakes

A field guide to the things that will bite you:

### Running Everything as Root

If your containers all run as root and one gets compromised, the attacker has root inside the container. Combined with a kernel vulnerability or a Docker escape, that's root on your host. Run as non-root. It's one line in your Compose file.

### Exposing Admin Interfaces to the Internet

Portainer, database admin panels, monitoring dashboards — these should never be directly accessible from the internet. Put them behind your reverse proxy with authentication. Better yet, only access them over VPN or SSH tunnels.

### Using Default Credentials

Every service you deploy comes with default credentials. Change them. All of them. Even the ones "nobody would guess" (they will). Especially the ones for databases and admin panels.

### No Network Segmentation

Everything on one flat network means one compromised container can reach every other container. It takes 10 minutes to set up purpose-specific Docker networks. Do it.

### No Backups

A ransomware attack that encrypts your data is a security incident. If you have backups, it's an inconvenience — restore and move on. If you don't have backups, it's a catastrophe. Backups are security infrastructure.

### "It's Just a Homelab"

This mindset is the root cause of all the others. Yes, it's a homelab. It's also on your home network, with your personal data, your financial accounts, your family's devices. Treat it with appropriate seriousness. You don't need enterprise-grade security, but you need more than zero.

---

## A Hardened Container Template

Here's a starting point for any new service. Not every option will work for every container, but start here and remove restrictions only when you have a specific reason:

```yaml
services:
  example-service:
    image: example/service:latest
    container_name: example-service
    restart: unless-stopped

    # Run as non-root
    user: "1000:1000"

    # Read-only root filesystem
    read_only: true
    tmpfs:
      - /tmp
      - /run

    # Drop all capabilities
    cap_drop:
      - ALL

    # No privileged mode
    security_opt:
      - no-new-privileges:true

    # Resource limits
    deploy:
      resources:
        limits:
          memory: 512M
          cpus: "1.0"

    # Only on needed networks
    networks:
      - backend

    # Don't expose ports unless needed by the host
    # Other containers reach this via Docker DNS

    # Writable data in volumes only
    volumes:
      - service_data:/data

    # Health check
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
```

Copy this. Adapt it. Make it your default. When you deviate from it, document why.

Security in a homelab isn't about paranoia — it's about making thoughtful, deliberate decisions at every layer instead of accepting insecure defaults because they're easier. The thirty minutes you spend hardening a service is insurance against the hours you'd spend recovering from a compromise.
