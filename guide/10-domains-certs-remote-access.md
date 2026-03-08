# Chapter 10 — Domains, Certificates, Dynamic DNS & Remote Access

You've got containers running behind a reverse proxy, services talking to each other over Docker networks, and monitoring that tells you when things break. But right now, you're accessing everything by typing IP addresses into your browser like it's 1997. Or worse, you're using `.local` hostnames that half your devices don't resolve and no certificate authority will sign.

This chapter covers the full pipeline: how to give your services real names, prove you own those names to get valid TLS, deal with the fact that your ISP changes your IP address whenever it feels like it, and reach your homelab from anywhere without punching unnecessary holes in your firewall.

---

## Domain Names — Your $12/Year Foundation

### Why a Real Domain

"Can't I just use IP addresses? Or mDNS? Or edit /etc/hosts on every device?"

You can. And you'll hate it within a month.

A real domain gives you:

- **Valid TLS certificates.** Let's Encrypt will not issue a cert for `192.168.1.50` or `myserver.local`. Without a real domain, you're stuck with self-signed certs, browser warnings, and the muscle memory of clicking "proceed anyway" — which is exactly the habit that gets you phished.
- **Consistent naming across all your devices.** `grafana.home.yourdomain.com` works from your laptop, your phone, your work machine, and a hotel wifi. IP addresses and `.local` names do not.
- **Wildcard DNS and wildcard certs.** One DNS record and one certificate cover every service you'll ever add. Try doing that with `/etc/hosts`.
- **Split DNS capability.** The same name resolves to your LAN IP at home and your public IP outside. This only works with a real domain.

### The .local Trap

Apple's mDNS uses `.local` as its reserved TLD. If you name your homelab services `grafana.local`, you're going to collide with mDNS on every Apple device and many Linux machines running Avahi. You'll get intermittent resolution failures, cached stale answers, and debugging sessions that feel like they're gaslighting you.

And even if you dodge the mDNS conflicts, no public CA will issue a certificate for a `.local` domain. You're locked into self-signed certs forever.

Just buy a real domain. It costs less than a month of Netflix.

### Registrar Recommendations

| Registrar | Why | Notes |
|-----------|-----|-------|
| **Cloudflare** | At-cost pricing (~$10/year for .com), excellent DNS, API for automation | No markup on domains. DNS is fast and free. The API is what makes DDNS and cert validation painless. |
| **Porkbun** | Cheap, clean UI, good WHOIS privacy | Solid alternative if you don't want everything in Cloudflare's ecosystem. |
| **Namecheap** | Established, reasonable pricing | Fine. Not exciting. Gets the job done. |

Avoid GoDaddy. Their pricing is bait-and-switch, their UI is an upsell gauntlet, and they charge extra for things other registrars include for free.

### Subdomain Strategy

You need a naming convention. Here's one that works:

```
service.home.yourdomain.com
```

- `yourdomain.com` — your root domain, for whatever you want (personal site, email, etc.)
- `home.yourdomain.com` — the namespace for your homelab
- `grafana.home.yourdomain.com`, `gitea.home.yourdomain.com`, etc. — individual services

Why the `home.` prefix? It separates your homelab from other uses of your domain. If you later want `blog.yourdomain.com` pointing to a hosted site, it doesn't collide with your homelab wildcard. Your wildcard cert covers `*.home.yourdomain.com`, and your public stuff lives at the root.

Some people use `lab.`, `srv.`, or `int.` instead of `home.`. Doesn't matter. Pick one, be consistent, move on.

### One Domain or Two?

One domain for everything. You don't need separate domains for "internal" and "external" services. Split DNS (covered next) handles the distinction. Buying a second domain doubles the cost and the complexity for no benefit.

---

## DNS — Where Names Become Addresses

DNS is the system that turns `grafana.home.yourdomain.com` into an IP address your device can connect to. For a homelab, you have two distinct DNS problems, and they need different solutions.

### Problem 1: External DNS

When you're away from home and type `grafana.home.yourdomain.com` into your browser, your device asks a public DNS resolver (Cloudflare's 1.1.1.1, Google's 8.8.8.8, your ISP's resolver) for the IP address. That resolver eventually reaches the authoritative nameserver for your domain — whoever you configured when you registered it.

For most homelabbers, this is Cloudflare's DNS. You manage records in their dashboard or via API, and Cloudflare answers queries from the internet.

The records you need:

| Record | Name | Value | Purpose |
|--------|------|-------|---------|
| A | `yourdomain.com` | `your.public.ip` | Root domain points to your IP |
| CNAME | `*.home.yourdomain.com` | `yourdomain.com` | Wildcard — all services resolve to the same IP |

That's it. Two records. The wildcard CNAME means every new service you add resolves automatically — no DNS changes needed.

### Problem 2: Internal DNS (Split DNS)

Here's the problem with external DNS alone: when you're sitting on your couch and your browser asks for `grafana.home.yourdomain.com`, the public DNS returns your public IP. Your request goes out through your router, hits your ISP, and comes back in. This is called **hairpin NAT**, and it's bad:

- It's slow — you're round-tripping through your ISP for traffic that should never leave your house.
- Many consumer routers don't support it at all, so it simply doesn't work.
- It leaks information — your internal traffic patterns are visible to your ISP.
- It creates a dependency on your internet connection for purely local services.

The fix is split DNS: a local DNS resolver that answers queries for your domain with your server's **LAN IP** (e.g., `10.0.20.10`), while the rest of the internet still gets your public IP.

**Tools for split DNS:**

- **Pi-hole** — DNS-level ad blocker that also does custom DNS records. You probably already want this for ad blocking anyway. Add a local DNS record: `*.home.yourdomain.com → 10.0.20.10`. Done.
- **AdGuard Home** — Similar to Pi-hole with a more modern UI. Same capability for custom DNS rewrites.
- **CoreDNS** — More flexible, more config, less UI. Good if you want to get fancy with DNS policies. Overkill for most homelabs.

The setup is straightforward: configure your router's DHCP to hand out your Pi-hole/AdGuard instance as the DNS server for your LAN. Now every device on your network gets local resolution for your homelab domains and public resolution for everything else.

> **Note:** Set your external DNS records (the ones in Cloudflare) to a low TTL like 300 seconds for the A record pointing to your dynamic IP. For internal DNS, TTL matters less since you control both sides and can flush caches manually.

### DNS Records You'll Actually Use

- **A** — Maps a name to an IPv4 address. Your root domain's A record is the anchor everything else points to.
- **CNAME** — Maps a name to another name. Your wildcard `*.home.yourdomain.com` CNAMEs to `yourdomain.com`, which has the A record. Changes propagate — update the A record and the CNAMEs follow.
- **TXT** — Arbitrary text. Used by Let's Encrypt for DNS validation (proving you control the domain). You never create these manually; your ACME client (SWAG/certbot) does it via API.

---

## The Dynamic IP Problem

Residential ISPs give you a dynamic IP address. It changes on their schedule — could be every few days, could be every time your modem reboots, could be seemingly at random. When it changes, your DNS A record is wrong, and everything external breaks.

Before solving this, check if you even have a public IP. Compare the WAN IP on your router's status page with what `whatismyip.com` shows. If they differ, you're behind **CGNAT** (Carrier-Grade NAT), and you don't have a public IP at all. More on that at the end of this section.

### Solution 1: Dynamic DNS (DDNS)

The simplest fix: a script that checks your public IP periodically, compares it to your DNS record, and updates the record if it changed.

**Cloudflare DDNS** — The best option if you're using Cloudflare for DNS. Run a small container that polls your IP and updates the A record via Cloudflare's API.

```yaml
services:
  cloudflare-ddns:
    image: favonia/cloudflare-ddns:latest
    container_name: cloudflare-ddns
    environment:
      - CLOUDFLARE_API_TOKEN=your-scoped-api-token
      - DOMAINS=yourdomain.com
      - PROXIED=false
    restart: unless-stopped
```

Other options:
- **ddclient** — The classic. Supports many DNS providers. Configuration is less intuitive than it should be, but it works.
- **DuckDNS** — Free, gives you a `yourname.duckdns.org` subdomain. Fine for getting started, limiting if you want your own domain.

**How fast does DDNS converge?** It depends on two things: how often you check your IP (every 5 minutes is typical) and the TTL on your DNS record. Set the A record TTL to 300 seconds (5 minutes). Worst case, you're down for about 10 minutes after an IP change: 5 minutes to detect it and 5 minutes for DNS caches to expire.

Add a health check: have your DDNS updater ping healthchecks.io after each successful run. If the pings stop, you know the updater died before you notice external services are unreachable.

### Solution 2: Cloudflare Tunnel

Cloudflare Tunnel sidesteps the dynamic IP problem entirely. Instead of pointing DNS at your IP, your server makes an outbound connection to Cloudflare's edge network. Traffic flows through Cloudflare to your server without any port forwarding or public IP needed.

```yaml
services:
  cloudflared:
    image: cloudflare/cloudflared:latest
    container_name: cloudflared
    command: tunnel run
    environment:
      - TUNNEL_TOKEN=your-tunnel-token
    restart: unless-stopped
    networks:
      - proxy
```

**Trade-offs:**
- No ports to open. Works through CGNAT. No DDNS to manage.
- All your traffic routes through Cloudflare. They can see your request metadata (URLs, headers). They decrypt and re-encrypt your TLS traffic at their edge. If Cloudflare goes down, your external access goes down.
- There are bandwidth and usage considerations on free tiers. Streaming large amounts of media through it may violate their terms of service.

Cloudflare Tunnel is excellent for exposing a few web services. It's not a replacement for a VPN if you need full network-level access.

### Solution 3: Static IP

Call your ISP and ask. Some offer static IPs for $5-15/month extra. Business-class residential service often includes it. If you can get one, do — it eliminates an entire class of problems.

### The CGNAT Problem

If your router's WAN IP doesn't match `whatismyip.com`, your ISP is using Carrier-Grade NAT. You're sharing a public IP with other customers. Port forwarding from your router goes nowhere because there's another NAT layer between you and the internet.

Your options:
1. **Cloudflare Tunnel** — Works through CGNAT since connections are outbound.
2. **VPS relay** — Rent a cheap VPS ($3-5/month) with a static IP, set up a WireGuard tunnel to it, and proxy traffic through it. More complex but fully under your control.
3. **Call your ISP** — Some will move you off CGNAT if you ask. Some will charge you. Some will say no.
4. **Tailscale** — Works through CGNAT for remote access (covered later in this chapter).

> **Warning:** If you're behind CGNAT, traditional port forwarding will not work no matter what you configure on your router. Verify before spending hours troubleshooting.

---

## TLS Certificates

### Why You Need Valid TLS Everywhere

Including on services that never touch the internet. Including on your LAN-only dashboards. Including on that one service "only you use."

Three reasons:

1. **Browser warnings are training.** Every time you click "proceed to unsafe site," you're training yourself to bypass the one warning that might someday matter. Stop.
2. **HTTPS is a requirement.** Clipboard API, service workers, geolocation, WebRTC, and an ever-growing list of browser features flat-out require a secure context. Plain HTTP services are increasingly broken by design.
3. **It's free.** You're already getting a wildcard cert for external services. Using it internally costs nothing.

### Let's Encrypt — The Only Answer

Let's Encrypt issues free, automated, 90-day certificates. There is no reason to use anything else for a homelab. Paid certs offer nothing you need. Self-signed certs create exactly the problems described above.

### Validation Methods

Let's Encrypt needs to verify you control the domain before issuing a cert. Two methods matter:

**HTTP validation (http-01):**
- Let's Encrypt makes an HTTP request to port 80 on your server.
- Simple, but requires port 80 open and publicly reachable.
- Cannot issue wildcard certificates.
- If your server is behind CGNAT or you don't want to open ports during validation, this won't work.

**DNS validation (dns-01):**
- Let's Encrypt asks you to create a specific TXT record in your DNS.
- Works behind firewalls, through CGNAT, for servers with no public access at all.
- Supports wildcard certificates.
- Requires a DNS provider with an API (Cloudflare, Route53, etc.).

**DNS validation is what you want.** It solves every problem HTTP validation has, and it gives you wildcard certs. The only requirement is a DNS provider with an API, which you already have if you followed the Cloudflare recommendation above.

SWAG handles all of this automatically. You configure the DNS provider credentials, tell it to use DNS validation, and it obtains and renews certificates on schedule. You never manually create TXT records.

### Wildcard Certificates

A wildcard cert for `*.home.yourdomain.com` covers every subdomain: `grafana.home.yourdomain.com`, `gitea.home.yourdomain.com`, `whatever-you-add-next.home.yourdomain.com`. One cert, one renewal, no per-service configuration.

DNS validation is required for wildcard certs. This is non-negotiable — Let's Encrypt does not support wildcard issuance via HTTP validation.

### Renewal and Monitoring

Certs expire every 90 days. SWAG/certbot attempts renewal when the cert has 30 days left, giving you a 60-day window if something breaks silently. That window sounds generous until you realize you forgot to check and everything expired on a Friday night.

Monitor it:
- SWAG logs renewal attempts. Check them.
- Set up a healthchecks.io check that gets pinged after each successful renewal.
- Add a cert expiry check in your monitoring stack (Uptime Kuma can do this).

### Self-Signed Certs

Don't. The single exception is development/testing where you're explicitly testing TLS behavior and need to control the certificate parameters. For everything else — every internal dashboard, every API, every service — use Let's Encrypt with DNS validation. It's free, it's automated, and it eliminates an entire category of "works for me" debugging sessions.

---

## Remote Access — Beyond the Reverse Proxy

SWAG handles "how do I reach web services from a browser outside my network." But that's only one remote access pattern. You also need SSH access, access to non-HTTP services, and sometimes full network-level connectivity to your homelab.

Here are your options, ranked by the trade-off between security, simplicity, and capability.

### 1. Tailscale — The Answer for Most People

Tailscale is a mesh VPN built on WireGuard. Install it on your homelab server and on your devices. They can communicate as if they're on the same network, regardless of where they physically are. No port forwarding, no firewall holes, works through CGNAT, works on mobile.

Why it's the default recommendation:

- **Zero firewall configuration.** Connections are outbound from both sides and coordinated through Tailscale's relay infrastructure. Your router doesn't need any ports opened.
- **Free for personal use.** Up to 100 devices. You will not hit this limit.
- **Subnet routing.** Expose your entire homelab LAN to your Tailscale network without installing Tailscale on every container. Install it on one machine, advertise the subnet, and all your Tailscale devices can reach all your homelab IPs.
- **Exit nodes.** Route all your internet traffic through your homelab when you're on sketchy wifi. Your homelab becomes your personal VPN.
- **MagicDNS.** Automatic DNS names for your Tailscale devices. Access your server by name from anywhere.
- **SSH built in.** `tailscale ssh` provides authenticated SSH without managing keys or exposing port 22.

**The trade-off:** Tailscale's coordination server is hosted by Tailscale Inc. They can see device metadata (what devices you have, when they connect, their IP addresses) but not your traffic — the WireGuard tunnels are end-to-end encrypted. For most people, this is a perfectly acceptable trade-off. If it isn't, see Headscale.

### 2. Headscale — Self-Hosted Coordination

Headscale is an open-source reimplementation of Tailscale's coordination server. You run it yourself, getting the same mesh VPN without any third-party involvement.

Same WireGuard mesh, same client software, your server handles coordination. The cost is setup complexity and ongoing maintenance. You're now responsible for keeping the coordination server running, updated, and backed up.

Good if you're privacy-sensitive or want to understand how the coordination layer works. Not necessary for most people.

### 3. WireGuard (Raw)

Install WireGuard directly, manage keys and configs yourself. One open UDP port on your firewall, fast and lightweight protocol, full control.

The manual configuration is where it gets tedious. Every peer needs the other peer's public key and endpoint. Adding a device means editing configs on both sides. There's no coordination server, no automatic key exchange, no subnet discovery.

Good as a learning exercise. Less convenient for daily use than Tailscale, which uses the same underlying protocol with better management.

### 4. Cloudflare Tunnel (Revisited)

Already discussed for solving the dynamic IP problem, but worth mentioning as a remote access solution. Services behind a Cloudflare Tunnel are accessible as normal HTTPS URLs from anywhere. No VPN client needed.

The distinction: Cloudflare Tunnel is per-service, not network-level. You're exposing specific web applications, not providing general access to your homelab network. Good for sharing a status page or dashboard with others. Not a replacement for VPN-level access.

### 5. SSH Tunneling

The option that's always available, requires no extra software, and handles one-off access to specific services:

```bash
ssh -L 8080:localhost:3000 yourserver
```

Now `localhost:8080` on your laptop forwards to port 3000 on your server. Encrypted, simple, no additional infrastructure.

Practical for occasional use. Impractical for daily use with multiple services. And it requires SSH to be exposed, which means port 22 (or a non-standard port) must be reachable — and it will be probed by every scanner on the internet.

### 6. OpenVPN

It works. It's been around forever. It's well understood. WireGuard is faster, simpler, and more modern in every measurable way. Choose OpenVPN only if you have a specific compatibility requirement — a corporate VPN client that speaks OpenVPN, existing infrastructure you don't want to migrate. Otherwise, WireGuard (directly or via Tailscale) is the better choice.

### What NOT to Do

- **Don't expose Docker socket or Portainer to the internet.** The Docker socket is root access to your host. Portainer with default credentials is root access with a nice UI. Neither should ever be reachable from outside your network.
- **Don't rely on obscure port numbers.** Running SSH on port 2222 does not make it secure. Automated scanners check all 65,535 ports. Security through obscurity is not security.
- **Don't use plain HTTP externally.** Not "just for testing." Not "just temporarily." Not even once. If it's reachable from the internet, it's HTTPS or it's off.
- **Don't open more ports than necessary.** Ideal: port 80 and 443 for SWAG, one UDP port for WireGuard if you're using it directly. That's it. Every open port is attack surface.

### The Recommended Stack

Two layers, two purposes:

1. **Tailscale** for personal remote access — SSH, internal dashboards, admin tools, anything you access from your own devices.
2. **SWAG** for publicly accessible services — anything you want reachable from a browser without a VPN client, or services you share with others.

This gives you minimal attack surface (only ports 80/443 open) with full remote capability. Tailscale handles everything personal, SWAG handles everything public.

---

## Putting It All Together

Here's a concrete, end-to-end setup. This is not the only way, but it's a good default.

### Step 1: Domain and DNS

1. Register `yourdomain.com` on Cloudflare (~$10/year).
2. Cloudflare is now your DNS provider and nameserver.
3. Create an A record: `yourdomain.com → your.current.public.ip` (TTL: 300s).
4. Create a wildcard CNAME: `*.home.yourdomain.com → yourdomain.com` (TTL: auto).

### Step 2: Dynamic DNS

Deploy a DDNS container to keep the A record current:

```yaml
services:
  cloudflare-ddns:
    image: favonia/cloudflare-ddns:latest
    container_name: cloudflare-ddns
    environment:
      - CLOUDFLARE_API_TOKEN=your-dns-edit-scoped-token
      - DOMAINS=yourdomain.com
      - PROXIED=false
    restart: unless-stopped
```

Set up a healthchecks.io ping so you know if the updater dies.

### Step 3: TLS via SWAG

SWAG obtains a wildcard cert for `*.home.yourdomain.com` using DNS validation (covered in Chapter 04). The cert covers every service you add behind the proxy. Renewal is automatic.

### Step 4: Split DNS

Configure Pi-hole or AdGuard Home with a DNS rewrite:

```
*.home.yourdomain.com → 10.0.20.10  (your server's LAN IP)
```

Set your router's DHCP to hand out the Pi-hole/AdGuard address as the DNS server. Now all LAN devices resolve homelab domains to the local IP, bypassing hairpin NAT.

### Step 5: Remote Access

Install Tailscale on your server. Advertise your homelab subnet. Install Tailscale on your phone, laptop, and any device you use remotely. You now have full network access to your homelab from anywhere.

### Step 6: Monitor the Chain

Every link in this chain can break independently:

| Component | What breaks | How you'll know |
|-----------|------------|-----------------|
| DDNS | IP changed, record didn't update | Healthchecks.io missed ping |
| TLS cert | Renewal failed | Uptime Kuma cert check, browser errors in 60 days |
| Split DNS | Pi-hole/AdGuard down | Local resolution fails, hairpin NAT kicks in (slow) |
| Tailscale | Client not connected | Can't reach services remotely |
| SWAG | Container crashed | Everything external returns connection refused |

Set up monitoring for each. Chapter 05 covered the tools. Use them here.

### The Request Flow

**From inside your network:**
```
Browser → Pi-hole resolves grafana.home.yourdomain.com to 10.0.20.10
        → Hits SWAG on LAN IP, port 443
        → SWAG terminates TLS (wildcard cert)
        → Forwards to Grafana container on Docker network
```

**From outside your network:**
```
Browser → Public DNS resolves grafana.home.yourdomain.com to your public IP
        → Router port-forwards 443 to SWAG
        → SWAG terminates TLS (same wildcard cert)
        → Forwards to Grafana container on Docker network
```

**From your phone via Tailscale:**
```
Browser → Tailscale resolves to your server's Tailscale IP (100.x.x.x)
        → WireGuard tunnel to your server
        → Hits SWAG directly, or accesses services on internal ports
```

Three paths, same services, same certificates, same names. That's the payoff.

---

## Summary

The moving parts here — domain registration, DNS, DDNS, split DNS, TLS certificates, remote access — feel like a lot. They are a lot. But each piece solves a specific, real problem, and together they give you something that works reliably from anywhere.

The key decisions:

1. **Buy a real domain.** $10-15/year. Use Cloudflare for DNS.
2. **Use DNS validation for wildcard certs.** No ports to open during renewal, covers all services with one cert.
3. **Run split DNS internally.** Same domain names, local resolution, no hairpin NAT.
4. **Keep your A record current.** DDNS with health monitoring.
5. **Tailscale for personal access, SWAG for public access.** Two layers, minimal attack surface.

Get these right once and adding new services becomes trivial: deploy a container, drop a SWAG proxy config, done. The naming, certificates, and access patterns are already in place.
