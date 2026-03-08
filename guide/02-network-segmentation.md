# Chapter 02 — Network Segmentation

Most homelabs start with everything on one flat network: your laptop, your server, your smart TV, your IoT doorbell camera with firmware from 2019, and your kid's tablet — all on the same subnet, all able to talk to each other freely.

This is fine until it isn't. And when it isn't, it's usually because something you didn't expect to be a problem becomes a big one. A compromised IoT device scanning your network. A guest's infected laptop poking at your NAS. A misconfigured service exposing an admin interface to every device in the house.

Network segmentation is the fix. It's not paranoia — it's basic hygiene.

---

## Why VLANs Matter Even at Home

A VLAN (Virtual Local Area Network) lets you create separate logical networks on the same physical infrastructure. Devices on one VLAN can't talk to devices on another VLAN unless you explicitly allow it with firewall rules.

This gives you:

### Blast Radius Containment

If an IoT device gets compromised (and they do — many run ancient, unpatched Linux kernels with hardcoded credentials), it can only see other devices on the IoT VLAN. It can't reach your server, your workstation, or your NAS. The compromise is contained.

### Traffic Isolation

Your media server streaming 4K video doesn't compete with your management traffic. Your guest's torrenting (you have plausible deniability about what your guests do) doesn't saturate the same broadcast domain as your production services.

### Policy Enforcement

Different VLANs can have different rules. IoT devices get internet access but can't initiate connections to any other VLAN. Guests get internet only — no local network access at all. Your server VLAN can reach the internet for updates but isn't accessible from the guest network.

### Mental Clarity

When your network is segmented, you can reason about it. "What can reach my server?" has a clear answer: devices on the trusted VLAN and the server VLAN itself, via specific allowed ports. On a flat network, the answer is "everything," and that's not a comforting answer.

---

## The Hardware Floor

Let's get this out of the way: **you need a managed switch to do VLANs. There is no software-only workaround that's worth the pain.**

Consumer mesh systems (Eero, Google Wifi, most off-the-shelf routers) do not support VLANs. Some have a "guest network" feature that provides minimal isolation, but it's not configurable and doesn't extend to wired devices.

You need:
1. **A managed switch** that supports 802.1Q VLAN tagging
2. **A router/firewall** that can route between VLANs and apply firewall rules (or a device that does both)

This doesn't have to be expensive. But it does have to be specific hardware. Consumer gear won't cut it.

> **Note:** If you're not ready to invest in network hardware, skip to the "Stepping Stone" section at the end of this chapter. Docker network isolation provides some of the benefits without any hardware changes. It's not the same thing, but it's a start.

---

## Recommended VLAN Layout

Here's a VLAN layout that covers typical homelab needs. You don't need all of these on day one — start with what makes sense and add VLANs as your needs grow.

### VLAN 1 — Management (10.0.1.0/24)

**What lives here:** Switch management interfaces, access point management interfaces, router/firewall admin interface.

**Why it exists:** These are the most security-sensitive devices on your network. If someone compromises your switch, they own your entire network. This VLAN should be accessible only from the trusted VLAN, and only by you.

**Rules:**
- No internet access (management devices don't need it — or get updates via a controlled path)
- Accessible only from Trusted VLAN
- All other VLANs blocked

### VLAN 10 — Trusted (10.0.10.0/24)

**What lives here:** Your personal workstation, laptop, phone, tablet. Devices you control and trust.

**Why it exists:** These are the devices from which you manage everything else. They need broad access, but only they should have it.

**Rules:**
- Full internet access
- Can reach all other VLANs (you need to manage your servers, IoT devices, etc.)
- This is the "admin" VLAN — treat membership as a privilege

### VLAN 20 — Server/Infrastructure (10.0.20.0/24)

**What lives here:** Your prod utility server, any infrastructure services that need to be reached by other VLANs (DNS, reverse proxy).

**Why it exists:** Your production infrastructure needs to be reachable (for DNS resolution, for proxied web services) but shouldn't be able to be meddled with by arbitrary devices.

**Rules:**
- Internet access (for pulling container images, system updates)
- Reachable from Trusted VLAN (full access for management)
- Reachable from other VLANs on specific ports only (DNS on 53, HTTP/HTTPS on 80/443)
- Cannot initiate connections to Trusted VLAN (defense in depth — if the server is compromised, it can't attack your workstation)

### VLAN 30 — Dev (10.0.30.0/24)

**What lives here:** Your cortex/dev box, experimental services, anything under active development.

**Why it exists:** Dev workloads are inherently risky. You're running untested code, trying new containers, exposing experimental services. This VLAN isolates that risk.

**Rules:**
- Internet access
- Reachable from Trusted VLAN (for SSH, web UIs during development)
- Can reach Server VLAN on specific ports (if dev services need to query production DNS, etc.)
- Cannot reach Management VLAN
- Cannot reach IoT VLAN (no reason for dev experiments to touch your light bulbs)

### VLAN 40 — IoT (10.0.40.0/24)

**What lives here:** Smart home devices, cameras, smart plugs, robot vacuums, anything with firmware you don't control and can't audit.

**Why it exists:** IoT devices are the most likely entry point for network compromise. They frequently have security vulnerabilities, phone home to cloud services, and can't be updated or audited. Isolate them aggressively.

**Rules:**
- Internet access (most IoT devices require cloud connectivity to function — annoying but reality)
- Cannot initiate connections to any other VLAN
- Server VLAN can reach IoT VLAN on specific ports (Home Assistant needs to talk to devices)
- Trusted VLAN can reach IoT VLAN (for device setup and management apps)
- No access to Management VLAN — ever

> **Warning:** The IoT VLAN is the one people most often get wrong. The most common mistake is allowing IoT devices to reach the management VLAN. A compromised smart bulb should not be able to access your switch's admin interface. Block it explicitly and verify with a port scan.

### VLAN 50 — Guest (10.0.50.0/24)

**What lives here:** Guests' phones, laptops, tablets.

**Why it exists:** Guests need internet access. They don't need access to anything else on your network. Period.

**Rules:**
- Internet access
- Cannot reach any other VLAN
- Client isolation enabled (guests can't see each other's devices either)
- Bandwidth limiting optional but considerate

---

## VLAN Layout Summary

```
VLAN ID  | Name           | Subnet         | Internet | Can Reach
---------|----------------|----------------|----------|---------------------------
1        | Management     | 10.0.1.0/24    | No*      | Nothing (inbound only)
10       | Trusted        | 10.0.10.0/24   | Yes      | All VLANs
20       | Server/Infra   | 10.0.20.0/24   | Yes      | Internet, limited local
30       | Dev            | 10.0.30.0/24   | Yes      | Internet, Server (limited)
40       | IoT            | 10.0.40.0/24   | Yes      | Internet only
50       | Guest          | 10.0.50.0/24   | Yes      | Internet only

* Management devices may need internet for firmware updates — handle this via
  scheduled, temporary access or manual updates.
```

---

## Firewall Rules Between VLANs

The firewall is where VLAN isolation actually happens. Without firewall rules, VLANs on the same router can still talk to each other by default (inter-VLAN routing). You must explicitly block what you don't want.

### Rule Design Philosophy

Start with **deny all** between VLANs, then add specific allows. This is the opposite of how most consumer routers work (allow all, block specific things), and it's the only approach that's actually secure.

```
# Pseudocode — adapt to your firewall's syntax

# Default: deny all inter-VLAN traffic
deny all from any-vlan to any-vlan

# Trusted can reach everything (admin access)
allow from Trusted to Management
allow from Trusted to Server
allow from Trusted to Dev
allow from Trusted to IoT
allow from Trusted to Guest

# Server VLAN specifics
allow from Server to IoT port 80,443,1883,8123  # Home Assistant, MQTT
allow from Server to Internet

# Dev VLAN specifics
allow from Dev to Server port 53,80,443  # DNS, HTTP
allow from Dev to Internet

# IoT — internet only, nothing local
allow from IoT to Internet
deny from IoT to RFC1918  # Block all private IP ranges explicitly

# Guest — internet only, isolated
allow from Guest to Internet
deny from Guest to RFC1918

# DNS: all VLANs should be able to reach the DNS server
allow from any-vlan to Server port 53
```

### Important Details

**Block RFC1918 explicitly for IoT and Guest.** Just blocking inter-VLAN traffic isn't enough if your router does NAT hairpinning or if there are routing edge cases. Explicitly blocking all private IP ranges (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16) from IoT and Guest VLANs is belt-and-suspenders security.

**Allow established/related connections.** Your firewall rules should be stateful. When the server VLAN makes an outbound connection to the internet, the response packets need to get back. Most modern firewalls handle this automatically, but verify it.

**ICMP (ping) rules.** Allow ICMP from Trusted to everything (you need to ping things for troubleshooting). Block ICMP from IoT and Guest to local networks. This is a minor detail but prevents network reconnaissance from compromised devices.

---

## DNS Considerations

DNS deserves special attention in a segmented network because every device needs it and it crosses VLAN boundaries by nature.

### Running Your Own DNS

Pi-hole or AdGuard Home on your server VLAN acts as your network's DNS resolver. It provides:
- Ad blocking at the network level
- Local DNS resolution (so you can reach services by name instead of IP)
- DNS query logging (useful for debugging and seeing what your IoT devices phone home to)

Every VLAN should use your DNS server. Configure your DHCP server to hand out the DNS server's IP (on the server VLAN) to all VLANs. Your firewall rules must allow DNS traffic (port 53 UDP and TCP) from all VLANs to the server VLAN.

### Split DNS

Split DNS means resolving the same domain name to different IPs depending on where the request comes from. The most common homelab use case:

- **External:** `myservice.example.com` resolves to your public IP (or Cloudflare proxy)
- **Internal:** `myservice.example.com` resolves to your server's local IP (e.g., 10.0.20.10)

Without split DNS, internal requests go out to the internet and come back in (hairpin NAT), which is slower, may not work depending on your router, and is generally ugly.

Pi-hole handles this via Local DNS Records or custom dnsmasq configuration. AdGuard Home has DNS Rewrites. Both work well.

```
# Pi-hole local DNS example
# In /etc/pihole/custom.list or via the web UI:
10.0.20.10 myservice.example.com
10.0.20.10 nextcloud.example.com
10.0.20.10 jellyfin.example.com
```

### DNS and VPN

If you run a VPN (WireGuard) for remote access, your VPN clients should also use your internal DNS server. This lets you access local services by name from outside your network. Your VPN subnet needs the same DNS firewall rules as any other VLAN.

---

## The Stepping Stone: Docker Network Isolation

If you can't do VLANs yet — maybe you're using consumer network gear, maybe you're renting and can't change the network setup, maybe you're just not ready for that complexity — Docker's built-in networking provides a meaningful starting point.

### Default Bridge Network

By default, all Docker containers can talk to each other on the default bridge network. This is the flat-network equivalent for containers. Don't use it for anything beyond casual experimentation.

### Custom Docker Networks

Create separate Docker networks for different service groups:

```yaml
# In your compose file or via docker network create
networks:
  frontend:
    name: frontend
  backend:
    name: backend
  iot:
    name: iot-services

services:
  traefik:
    networks:
      - frontend

  nextcloud:
    networks:
      - frontend
      - backend

  postgres:
    networks:
      - backend  # Only reachable by services on the backend network

  homeassistant:
    networks:
      - frontend
      - iot
```

In this setup:
- Traefik (reverse proxy) is on the `frontend` network
- PostgreSQL is on the `backend` network only — it can't be reached from the `frontend` network directly
- Nextcloud bridges both — it can receive traffic from Traefik and connect to PostgreSQL
- Home Assistant has its own `iot` network for IoT-related containers

This isn't VLAN-level isolation. All containers share the same host, and a compromised container with sufficient privileges can escape its network. But it's a meaningful layer of defense and, more importantly, it gets you thinking in terms of network segments.

### Docker Network Limitations

Be clear-eyed about what Docker networks don't give you:

- **No isolation from the host.** Containers can reach the host's network interfaces unless you configure iptables rules to prevent it.
- **No isolation from the physical network.** Containers with port mappings are reachable from the LAN.
- **No protection against container escape.** A container running as root with elevated privileges can access the host network stack.
- **No inter-host isolation.** If you have two Docker hosts on the same LAN, Docker networks on one host don't affect the other.

Docker networks are an application-level concern. VLANs are a network-level concern. They complement each other but don't substitute.

---

## Common Mistakes

### 1. Forgetting to Block IoT to Management

This is the most common and most dangerous mistake. Your management VLAN has the admin interfaces for your network infrastructure. If an IoT device can reach it, a compromised device can potentially reconfigure your switch or router. Always explicitly block IoT-to-Management traffic and test it.

### 2. Over-Permissive Inter-VLAN Rules

"I'll just allow all traffic between Server and Dev VLANs because it's easier." No. The whole point is controlled access. If everything can reach everything, you have a flat network with extra steps.

### 3. Not Testing the Rules

Set up your rules, then test them. From a device on each VLAN, try to reach devices on other VLANs. Use `nmap` or simple `ping` and `curl` tests. Rules you haven't tested are rules you don't know work.

```bash
# From an IoT device (or a laptop temporarily on the IoT VLAN):
ping 10.0.1.1      # Management gateway — should fail
ping 10.0.10.100   # Trusted workstation — should fail
ping 10.0.20.10    # Server — should fail (except DNS port)
ping 8.8.8.8       # Internet — should succeed
```

### 4. Forgetting mDNS/Bonjour

Many services use mDNS (multicast DNS) for discovery — AirPlay, Chromecast, Spotify Connect, printers. mDNS is link-local and doesn't cross VLAN boundaries by default. If you put your Chromecast on the IoT VLAN and your phone on the Trusted VLAN, casting won't work without an mDNS reflector/repeater.

Solutions:
- Run an mDNS reflector (like `avahi-daemon` with reflector mode, or your router may have this feature)
- Accept that some devices need to be on the same VLAN to work together
- Use IP-based connection instead of discovery where possible

### 5. Making It Too Complex Too Fast

Start with three VLANs: Trusted, Server, and IoT. That covers the most critical isolation. Add Management, Dev, and Guest VLANs when you understand the first three and want more granularity.

---

## Hardware Recommendations

### Router/Firewall

Your router/firewall is the device that routes between VLANs and enforces firewall rules. Options:

**OPNsense/pfSense on a mini PC ($100-200)**
Install the free OPNsense or pfSense firewall OS on a mini PC with two or more network interfaces (or a single NIC with VLAN trunking). This gives you a full-featured, enterprise-grade firewall for the cost of used hardware. This is the power user's choice — maximum flexibility, maximum learning.

**Ubiquiti UniFi Dream Machine / USG ($150-350)**
UniFi gear provides a polished UI and integrates switch, AP, and firewall management into one interface. It's less flexible than OPNsense but much easier to set up. Good if you want VLANs working in an afternoon, not a weekend. The Dream Machine series combines router, switch, and AP in one device.

**MikroTik ($50-150)**
MikroTik routers are incredibly capable for the price. A MikroTik hEX S can route between VLANs at gigabit speeds for $60. The catch: RouterOS has a steep learning curve and the documentation assumes networking knowledge. But if you want to learn networking deeply, MikroTik forces it.

### Managed Switches

**TP-Link Omada series ($30-100)**
The TL-SG108E (8-port) or TL-SG116E (16-port) are cheap, reliable, and support 802.1Q VLANs. The web UI is basic but functional. If you're pairing with a separate firewall, these are hard to beat on value.

**Ubiquiti UniFi switches ($100-300)**
If you're already in the UniFi ecosystem for your router/firewall, the UniFi switches integrate seamlessly. Managed entirely through the UniFi controller. More expensive per port than TP-Link but the unified management is genuinely nice.

**MikroTik switches ($50-200)**
Same story as MikroTik routers — powerful, cheap, steep learning curve. The CRS series doubles as both a switch and a router, which can simplify your setup.

### Access Points

If you want VLANs on WiFi (you do — your phone needs to be on the Trusted VLAN, your guests on Guest, your IoT devices on IoT), your access point needs to support multiple SSIDs mapped to different VLANs.

**Ubiquiti UniFi APs ($80-180)**
The standard recommendation. Multiple SSIDs, VLAN tagging, solid performance. The U6 Lite or U6+ covers most homes.

**TP-Link Omada APs ($60-120)**
The budget alternative. Similar feature set to UniFi. The EAP series supports multiple SSIDs with VLAN tagging. Managed through the Omada controller (free software, runs on your server or a dedicated hardware controller).

---

## A Practical Starting Point

If this all feels like a lot, here's the minimum viable segmented network:

1. **Buy a managed switch** — TP-Link TL-SG108E ($30) is enough to start
2. **Use your existing router** — if it supports VLANs (many prosumer routers do) or runs OpenWrt
3. **Create three VLANs** — Trusted, Server, IoT
4. **Move your server to the Server VLAN** — static IP, configure firewall rules
5. **Move IoT devices to the IoT VLAN** — new SSID on your AP if it supports it
6. **Test everything** — verify isolation, verify DNS works across VLANs, verify internet works from all VLANs

This is a weekend project. It won't be perfect, but it'll be a massive improvement over a flat network, and you'll understand your network much better afterward.

If even this is too much right now, go back to the Docker network isolation section. Set up separate Docker networks for your different service groups. It's not the same thing, but it's something, and it teaches the mental model.

The next chapter covers Docker foundations — how to actually organize and run your containers.
