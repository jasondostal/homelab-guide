# Chapter 04 — Reverse Proxy & Edge Defense

## The Front Door

Every request from the outside world hits your reverse proxy first. Every single one. It is the bouncer, the receptionist, and the traffic cop rolled into one. If you get one thing right in your homelab networking, make it this.

A reverse proxy sits between the internet and your services. It receives incoming requests on ports 80 and 443, inspects them, and forwards them to the appropriate internal container. The outside world never talks to your services directly. It talks to the proxy, and the proxy decides what happens next.

This gives you exactly one place to:

- Terminate SSL/TLS
- Enforce authentication
- Apply rate limits
- Block bad actors
- Route traffic based on hostname or path
- Log everything that touches your network

Without a reverse proxy, you're exposing individual container ports to the internet. Port 8080 for this, port 3000 for that, port 9090 for the other thing. Every exposed port is an attack surface. Every service has to handle its own SSL. Every service needs its own firewall rules. It's a mess, and it doesn't scale.

## Why SWAG

SWAG — Secure Web Application Gateway — is an opinionated bundle from LinuxServer.io that packages nginx, Let's Encrypt (via certbot), and fail2ban into a single container. You could assemble these pieces yourself. You probably shouldn't.

Here's what you'd need to replicate SWAG from scratch:

1. An nginx container with a proper config
2. A certbot container or sidecar for certificate management
3. A fail2ban container that can read nginx logs
4. Shared volumes between all three
5. Scripts to orchestrate renewal, reload, and jail management
6. Someone to maintain all of that when things break at 2am

SWAG gives you all of this in one image that the LinuxServer.io team maintains. It's well-documented, widely used in the homelab community, and has pre-built proxy configurations for dozens of popular self-hosted applications.

There are other options. Traefik is popular and handles automatic service discovery well if you're running Kubernetes or heavy Docker Swarm setups. Caddy is elegant and has automatic HTTPS built in. Nginx Proxy Manager gives you a web UI. But for a Docker Compose homelab, SWAG hits the sweet spot of power, simplicity, and community support.

### The Compose Configuration

```yaml
services:
  swag:
    image: lscr.io/linuxserver/swag:latest
    container_name: swag
    cap_add:
      - NET_ADMIN
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=America/Chicago
      - URL=yourdomain.com
      - SUBDOMAINS=wildcard
      - VALIDATION=dns
      - DNSPLUGIN=cloudflare
      - EMAIL=you@yourdomain.com
    volumes:
      - ./swag/config:/config
    ports:
      - 443:443
      - 80:80
    restart: unless-stopped
    networks:
      - proxy
```

A few things to note:

- `cap_add: NET_ADMIN` is required for fail2ban to manipulate iptables.
- `SUBDOMAINS=wildcard` with `VALIDATION=dns` gives you a wildcard certificate. One cert covers `*.yourdomain.com`. No need to list every subdomain individually.
- Only ports 80 and 443 are exposed. That's it. That's the whole external attack surface.

## SSL/TLS Everywhere

### DNS Validation for Wildcard Certs

There are three ways to validate domain ownership for Let's Encrypt certificates:

1. **HTTP validation** — Let's Encrypt hits `http://yourdomain.com/.well-known/acme-challenge/`. Requires port 80 open and pointed at the right place. Only works for specific subdomains you list.
2. **TLS-ALPN validation** — Similar concept over port 443. Same limitations.
3. **DNS validation** — You prove ownership by creating a TXT record in your DNS. Works for wildcard certs. Doesn't require any ports open during validation.

DNS validation is the right answer for homelabs. Here's why:

- You get a wildcard cert (`*.yourdomain.com`), so adding new services doesn't require re-issuing certificates.
- It works even if your homelab isn't publicly accessible during cert renewal.
- It works for internal-only services that will never be reachable from the internet.

The trade-off is that you need to give SWAG API access to your DNS provider. For Cloudflare, that means creating an API token scoped to DNS editing for your zone. Store it carefully.

```ini
# swag/config/dns-conf/cloudflare.ini
dns_cloudflare_api_token = your-scoped-api-token-here
```

> **Warning:** Scope your Cloudflare API token to the minimum permissions needed — Zone:DNS:Edit for your specific zone. Do not use a Global API Key. If this token leaks, you want the blast radius to be "someone can edit my DNS" not "someone owns my entire Cloudflare account."

### Internal SSL — Yes, Do It Anyway

"But my services are only on my local network. Why bother with SSL internally?"

Three reasons:

1. **Browsers complain.** Modern browsers increasingly distrust HTTP. You'll get warnings, broken features (clipboard API, service workers, geolocation all require HTTPS), and a worse experience.
2. **Defense in depth.** If something compromises one container, it can't sniff traffic between other containers because everything is encrypted.
3. **It's free.** You already have the wildcard cert. Using it internally costs you nothing but a few lines of config.

Your internal services should use the same wildcard cert. SWAG makes this straightforward since the cert files are in the config volume and can be referenced by other containers if needed, or you just route internal traffic through SWAG too.

## Routing: Subdomains vs. Subfolders

You have two choices for how users reach your services:

- **Subdomains:** `grafana.yourdomain.com`, `gitea.yourdomain.com`, `jellyfin.yourdomain.com`
- **Subfolders:** `yourdomain.com/grafana`, `yourdomain.com/gitea`, `yourdomain.com/jellyfin`

### Subdomains — The Default Choice

Subdomains are almost always the right answer. Here's why:

- Each service gets complete isolation. Cookie scoping, CORS policies, CSP headers — all cleanly separated.
- Most self-hosted applications expect to run at the root path. Subfolder routing often requires the application to support a "base URL" or "path prefix" setting, and many don't do it well.
- Wildcard DNS makes it trivial. One `*.yourdomain.com` A record pointed at your server, and every new subdomain just works.
- Wildcard cert means no certificate changes when you add services.

### Subfolders — The Exception

Subfolders make sense in a few cases:

- You're on a domain that doesn't support wildcard DNS (rare, but it happens with some dynamic DNS providers).
- You specifically want a single-origin setup for some security or organizational reason.
- The application explicitly supports and documents subfolder operation.

In practice, subfolder routing breaks more things than it fixes. Websocket paths get mangled, relative URLs in the application break, and you spend hours debugging path-rewriting rules in nginx. Don't do it unless you have a specific reason.

## SWAG Dashboard

SWAG includes a built-in dashboard that gives you a quick overview of your proxy's state. It shows:

- **Active proxy configurations** — which `.conf` files are enabled and routing traffic
- **Certificate status** — when your certs were issued and when they expire
- **Fail2ban status** — active jails, current bans, recent ban activity
- **Container logs** — recent nginx access and error logs

Access it at `https://yourdomain.com` (the root domain) or configure it on its own subdomain. It's not a deep analytics tool — it's a quick health check. Glance at it when something feels off. Check that your cert isn't about to expire. See if fail2ban is being unusually busy (which might mean someone is poking at you, or might mean you misconfigured a jail and are banning yourself).

## Fail2ban — Automated Threat Response

### How Jails Work

Fail2ban is beautifully simple in concept:

1. It watches log files.
2. It matches log lines against regex patterns (called "filters").
3. When a pattern matches too many times from the same IP within a time window, it bans that IP.
4. Bans are implemented via iptables rules — the banned IP literally cannot reach your server.
5. After a configurable time, the ban expires.

A "jail" is the combination of a filter (what to look for), a log file (where to look), and action parameters (how many strikes, how long to ban).

### Default Jails to Enable

SWAG ships with several pre-configured jails. Enable these at minimum:

```ini
# In /config/fail2ban/jail.local

[nginx-http-auth]
enabled = true
filter  = nginx-http-auth
port    = http,https
logpath = /config/log/nginx/error.log
maxretry = 3
bantime  = 3600

[nginx-badbots]
enabled = true
filter  = nginx-badbots
port    = http,https
logpath = /config/log/nginx/access.log
maxretry = 1
bantime  = 86400

[nginx-botsearch]
enabled = true
filter  = nginx-botsearch
port    = http,https
logpath = /config/log/nginx/access.log
maxretry = 2
bantime  = 86400
```

- **nginx-http-auth** catches repeated failed login attempts. Three wrong passwords and you're out for an hour.
- **nginx-badbots** blocks known malicious user agents. One hit and you're gone for 24 hours. These are automated scanners; there's no reason to be gentle.
- **nginx-botsearch** catches requests for common exploit paths (`/wp-admin`, `/phpmyadmin`, `/admin.php`). If you're not running WordPress, anyone requesting `/wp-login.php` is up to no good.

### Custom Jails

For services with their own authentication (Authelia, Vaultwarden, Gitea), you can write custom jails that watch those services' logs for failed login attempts:

```ini
[vaultwarden]
enabled  = true
filter   = vaultwarden
port     = http,https
logpath  = /path/to/vaultwarden/vaultwarden.log
maxretry = 3
bantime  = 14400
findtime = 600
```

The corresponding filter file matches Vaultwarden's login failure log format:

```ini
# /config/fail2ban/filter.d/vaultwarden.local
[Definition]
failregex = ^.*Username or password is incorrect\. Try again\. IP: <ADDR>\. Username:.*$
ignoreregex =
```

### Tuning — The Art of Not Banning Yourself

This is where most people get burned. You configure aggressive jails, forget your password three times, and lock yourself out of your own server.

Guidelines for sane defaults:

| Parameter | Conservative | Moderate | Aggressive |
|-----------|-------------|----------|------------|
| `maxretry` | 5 | 3 | 1 |
| `findtime` | 600 (10 min) | 300 (5 min) | 60 (1 min) |
| `bantime` | 600 (10 min) | 3600 (1 hr) | 86400 (24 hr) |

Start conservative. Tighten over time as you understand your traffic patterns.

> **Note:** Always whitelist your own IP range. In `jail.local`, set `ignoreip = 127.0.0.1/8 ::1 192.168.1.0/24` (substituting your actual LAN subnet). This is not optional. You will lock yourself out otherwise. It's not a question of "if" but "when."

You can also use `bantime.increment = true` for progressive banning — first offense is short, repeat offenders get increasingly longer bans. This is a nice middle ground.

## Proxy Configuration Patterns

SWAG uses per-service `.conf` files in `/config/nginx/proxy-confs/`. The naming convention matters:

- `service.subdomain.conf` — routes `service.yourdomain.com` to the container
- `service.subfolder.conf` — routes `yourdomain.com/service` to the container

SWAG ships with dozens of sample configs (with `.sample` extension). To enable one:

```bash
cd /config/nginx/proxy-confs/
cp gitea.subdomain.conf.sample gitea.subdomain.conf
# Edit as needed, then restart SWAG
```

A typical subdomain config looks like this:

```nginx
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;

    server_name gitea.*;

    include /config/nginx/ssl.conf;

    client_max_body_size 0;

    location / {
        include /config/nginx/proxy.conf;
        include /config/nginx/resolver.conf;
        set $upstream_app gitea;
        set $upstream_port 3000;
        set $upstream_proto http;
        proxy_pass $upstream_proto://$upstream_app:$upstream_port;
    }
}
```

The key pieces:

- `server_name gitea.*` matches `gitea.yourdomain.com`
- `$upstream_app gitea` is the Docker container name (containers on the same Docker network can resolve each other by name)
- `$upstream_port 3000` is the port the service listens on *inside* the container (not a published port)
- The includes pull in shared SSL and proxy header configurations

## Headers That Matter

The default proxy headers SWAG includes cover the basics, but you should understand what they do.

### Forwarding Headers

```nginx
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_set_header Host $host;
```

Without these, your backend services see every request as coming from the SWAG container's IP. They can't do their own rate limiting, logging, or geo-based decisions because they don't know who's actually connecting. These headers pass the real client information through.

### Security Headers

```nginx
add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-Frame-Options "SAMEORIGIN" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
add_header Content-Security-Policy "default-src 'self'; script-src 'self'" always;
```

- **HSTS** tells browsers to always use HTTPS. Once set, browsers won't even try HTTP. The `preload` directive is a commitment — don't enable it unless you're sure you'll keep HTTPS forever.
- **X-Content-Type-Options** prevents MIME-type sniffing attacks.
- **X-Frame-Options** prevents your site from being embedded in iframes (clickjacking protection).
- **Content-Security-Policy** is the most powerful and the most likely to break things. Start with a permissive policy and tighten. Many self-hosted apps need `unsafe-inline` and `unsafe-eval` for their JavaScript to work, which weakens CSP significantly. Set it per-service, not globally.

> **Note:** CSP is worth getting right, but don't let perfect be the enemy of good. A permissive CSP is still better than no CSP. Start with `default-src 'self'` and add exceptions as things break.

## Rate Limiting

Nginx has built-in rate limiting that's effective and lightweight:

```nginx
# In your http block or a shared include
limit_req_zone $binary_remote_addr zone=general:10m rate=10r/s;
limit_req_zone $binary_remote_addr zone=login:10m rate=1r/s;

# In your server/location blocks
location / {
    limit_req zone=general burst=20 nodelay;
    # ...
}

location /api/login {
    limit_req zone=login burst=3 nodelay;
    # ...
}
```

The `zone` allocates shared memory for tracking request rates per IP. The `rate` sets the sustained request rate. The `burst` allows short spikes above the rate. `nodelay` means burst requests are served immediately rather than queued.

For a homelab, the general zone keeps scrapers from hammering you, and the login zone makes brute-force attacks tediously slow. These work alongside fail2ban — rate limiting slows attackers down, fail2ban locks them out.

## Geo-blocking

Geo-blocking means denying requests from entire countries based on the source IP's geographic location. nginx can do this with the GeoIP2 module.

### When It Makes Sense

- You and everyone who uses your services are in one country. Blocking the rest of the world eliminates a huge volume of automated attacks.
- You're seeing persistent attack traffic from specific regions.
- You want to reduce noise in your logs.

### When It Doesn't

- You travel. Getting locked out of your own services from a hotel in another country is not fun.
- You have friends or family in other countries who use your services.
- You're relying on it as a security measure. It isn't one. VPNs exist. Geo-blocking reduces noise; it doesn't provide security.

If you do use it, implement it as a deny list (block specific countries) rather than an allow list (allow only your country) unless you're very sure of your access patterns. And always have an alternative access method (VPN to your home network) in case you need to bypass it.

## Internal-Only Services

Not everything should be reachable from the internet. Your database management tools, monitoring dashboards, and admin panels should only be accessible from your LAN.

There are several approaches, from simplest to most robust:

### 1. Nginx Allow/Deny

```nginx
location / {
    allow 192.168.1.0/24;
    allow 10.0.0.0/8;
    deny all;

    include /config/nginx/proxy.conf;
    # ...
}
```

Simple. Effective. Requests from outside your LAN get a 403. The downside is that if you're accessing through a VPN that doesn't route through your LAN, you're blocked too.

### 2. Separate Server Block Without External DNS

Don't create a public DNS record for the service. Use a local DNS entry (via Pi-hole, Adguard Home, or your router) that only resolves on your LAN. SWAG still handles SSL (your wildcard cert covers it), but the subdomain simply doesn't resolve from outside your network.

### 3. Authentication Layer

Use Authelia or Authentik as an authentication middleware in front of sensitive services. This is covered in a later chapter but is worth mentioning here — it's the most flexible approach because it allows access from anywhere while still requiring authentication.

For most internal tools, option 1 or 2 is sufficient. Save the auth layer for services that genuinely need remote access.

## The "No Ports Exposed" Rule

This is the single most important operational rule for your homelab:

**No container should publish ports to the host except SWAG (80 and 443) and services that fundamentally cannot be proxied (VPN servers, game servers).**

That means your Compose files should not have `ports:` sections. Instead, services communicate over Docker networks:

```yaml
services:
  gitea:
    image: gitea/gitea:latest
    # NO ports: section
    networks:
      - proxy
      - backend

  swag:
    image: lscr.io/linuxserver/swag:latest
    ports:
      - 443:443
      - 80:80
    networks:
      - proxy

networks:
  proxy:
    external: true
  backend:
    internal: true
```

Gitea is reachable by SWAG (both on the `proxy` network) but not from the host or the internet directly. The `backend` network is marked `internal: true`, meaning containers on it can talk to each other but have no outbound internet access — perfect for databases.

> **Warning:** If you're running `docker compose` from multiple directories, you need a shared external network. Create it once with `docker network create proxy` and reference it as `external: true` in each Compose file. Otherwise, each Compose project creates its own isolated network and SWAG can't reach the other services.

## Common Mistakes

### Exposing Management Ports

phpMyAdmin on port 8080 exposed to the internet. Portainer on port 9000 with no auth. These are the homelab equivalent of leaving your front door open with a sign that says "free stuff inside."

If a service has a web UI, it goes behind SWAG. No exceptions. If it doesn't have a web UI (like a database), it doesn't need to be reachable from outside at all.

### Forgetting Websocket Proxying

Many modern applications use websockets for real-time updates — chat applications, live dashboards, collaborative editors. Standard HTTP proxying doesn't handle the websocket upgrade handshake.

SWAG's default `proxy.conf` include handles this, but if you're writing custom configs, make sure you have:

```nginx
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection $http_connection;
```

Symptoms of missing websocket support: the application loads but real-time features don't work, you see 400 errors in the browser console for websocket connections, or the app falls back to polling and feels sluggish.

### SSL Termination Confusion

SSL termination happens at SWAG. The connection between SWAG and your backend services is typically plain HTTP over the internal Docker network. This is fine — the traffic never leaves the host.

Where people get confused:

- **Setting the backend to HTTPS** when SWAG is already handling SSL. Now you have double encryption and usually certificate errors because the backend's self-signed cert isn't trusted by SWAG.
- **Forgetting `X-Forwarded-Proto`** so the backend thinks it's being accessed over HTTP and generates HTTP URLs, breaking redirects and links.
- **Backend redirect loops** where the app sees HTTP (from SWAG's internal connection), redirects to HTTPS (which hits SWAG), which proxies over HTTP, which triggers another redirect. Fix this with the `X-Forwarded-Proto https` header so the app knows the client connection is encrypted even though the proxy-to-backend connection isn't.

The rule is simple: SWAG terminates SSL. Everything behind SWAG speaks HTTP unless there's a specific reason not to. Set `$upstream_proto http` in your proxy configs and move on.

### Not Testing After Changes

Nginx is unforgiving about syntax errors. A single misplaced semicolon takes down every site, not just the one you were editing.

Always test before restarting:

```bash
docker exec swag nginx -t
```

If it says `syntax is ok`, you're safe to restart. If it doesn't, fix the error before restarting. SWAG won't start with an invalid nginx config, and then nothing works.

## Summary

The reverse proxy is the foundation of your homelab's network architecture. Get it right and everything else is easier — adding services is a matter of dropping in a `.conf` file and creating a DNS record. Get it wrong and you're debugging networking issues forever.

The key principles:

1. Everything goes through SWAG. No exceptions.
2. SSL everywhere, even internally. DNS validation with wildcard certs.
3. Fail2ban jails for automated defense. Whitelist yourself.
4. One Docker network for proxy communication. No published ports on backend services.
5. Test your nginx config before restarting. Every time.
