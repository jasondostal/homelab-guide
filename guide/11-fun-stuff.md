# Chapter 11 — The Fun Stuff

This is the chapter that justifies everything else. You didn't learn about VLANs and write backup scripts and configure fail2ban because you love YAML — you did it so you could run cool shit safely. This chapter covers the services that make a homelab feel like home.

The theme: every one of these services replaces a cloud subscription, gives you something you can't get from the cloud, or both. And because you built the foundation right (Chapters 00-10), adding any of these is a compose file and ten minutes of your time.

Let's get into it.

---

## Network-Wide Ad Blocking

### What It Does

DNS-level ad and tracker blocking for every device on your network. No browser extensions needed. Your smart TV stops phoning home. Your kid's tablet stops loading sketchy ad networks. Devices that don't support ad blockers — game consoles, IoT gadgets, smart displays — all get filtered automatically.

This is the single highest-impact homelab service per effort invested. Fifteen minutes of setup, and your entire household's internet experience improves permanently.

### Pi-hole vs AdGuard Home

Both are excellent. You need to pick one. Here's how:

**Pi-hole** is the original. Massive community, extensive blocklist ecosystem, tons of blog posts and YouTube tutorials for every edge case. The web UI is functional but dated. Configuration is split between the UI and config files in ways that can be confusing. It works. Millions of people run it. You won't go wrong here.

**AdGuard Home** is the newer entrant. Modern web UI, built-in DNS-over-HTTPS (DoH) and DNS-over-TLS (DoT) support without extra configuration, slightly easier initial setup. Smaller community but growing fast. The UI gives you more control over individual client settings without touching config files.

This guide uses AdGuard Home because the built-in encrypted DNS support and the per-client configuration make it a better fit for the VLAN-segmented network we built in Chapter 02. Pi-hole can do all of this too — it just requires more manual configuration to get there.

> **Note:** This is a "pick one and move on" decision. Both tools solve the same problem. Don't install both. Don't spend three days comparing them. Pick the one whose UI you like better and get on with your life.

> **Full disclosure:** This guide recommends AdGuard Home for new setups because of its lower configuration overhead with VLANs and encrypted DNS. The author runs Pi-hole. Has for years. It's rock solid and the community support is unmatched. The recommendation isn't "AdGuard is better" — it's "AdGuard has less friction for the specific setup we're describing." Either choice is a good one.

### The Real Magic: VLANs + DNS Blocking

Here's where your Chapter 02 network segmentation pays dividends. Your IoT devices are on their own VLAN, and you control their DNS. Point that VLAN's DHCP to your AdGuard Home instance and those devices physically cannot resolve tracking domains.

Your Roku can't phone home to `ads.roku.com`. Your smart TV can't report your viewing habits. Your robot vacuum can't upload your floor plan to the cloud. They'll try, they'll get `NXDOMAIN`, and they'll deal with it.

This is something you genuinely cannot get from a cloud service. No amount of browser extensions or VPN subscriptions gives you DNS-level blocking for devices that don't support those tools.

### Gotchas

Some apps break when their tracking domains are blocked. Hulu is the poster child — it intermingles ad-serving and content-delivery domains so aggressively that blocking ads breaks playback. You'll whitelist selectively. The Pi-hole and AdGuard subreddits maintain good compatibility lists.

Captive portals at hotels and coffee shops won't work if your laptop is hardcoded to use your home DNS. This only matters if you're using DoH/DoT to your home server from remote — which is a power move but comes with this trade-off.

> **Warning:** If you set AdGuard Home as your network's DNS and it goes down, DNS resolution stops for your entire network. This is fine in practice — the container is rock solid and restarts automatically — but be aware that your DNS server is now a critical service. Monitor it (Chapter 05) and keep the host's fallback DNS configured in case you need to troubleshoot.

### Split DNS for Internal Services

AdGuard Home also doubles as your split-horizon DNS server. You can create DNS rewrites that resolve `jellyfin.yourdomain.com` to your server's internal IP instead of going through the public DNS. This means internal traffic stays internal — your media streams don't hairpin through your router or your Cloudflare tunnel.

This ties directly back to Chapter 10's domain setup. One service, two critical functions: ad blocking and internal name resolution.

### Resource Usage

AdGuard Home uses almost nothing. On your server, expect ~50MB of RAM and negligible CPU. This thing was designed to run on a Raspberry Pi. On your homelab hardware, it's a rounding error.

---

## Media Server: Jellyfin

### What It Does

Your own Netflix. Your own Spotify. Stream your media library — movies, TV shows, music, audiobooks, photos — to any device on your network (and remotely, if you set up external access in Chapter 10). Browser, phone, tablet, smart TV, Fire Stick, Roku.

This is the service that makes non-technical family members understand why you have a server in the closet.

### Why Jellyfin, Not Plex

Plex is fine software. Many people love it. But consider what you're doing here: you're self-hosting to own your stack. Plex requires an account on their servers. Plex phones home. Plex has "premium" features behind a paywall. Plex's authentication goes through their cloud — if Plex's servers go down, you can't log into your own media server on your own network.

Jellyfin is fully open source. No account required. No premium tier. No phone-home. All features available. Your server, your software, your rules. It's the philosophically consistent choice for a self-hosted stack, and the software has matured to the point where the practical gap with Plex is small and closing.

> **Note:** If your household already uses Plex and everyone's happy, don't switch just for ideological purity. But if you're starting fresh, start with Jellyfin. You can always try Plex later if Jellyfin doesn't meet your needs.

### Hardware Transcoding

This is the make-or-break feature for a good media server experience. Transcoding is what happens when a client device can't play your media's native format — the server converts it in real-time.

Software transcoding (CPU-only) works but is slow and CPU-intensive. A single 4K transcode can pin all your cores. Hardware transcoding offloads this to dedicated silicon on your GPU or iGPU, and it's dramatically faster and more efficient.

If your server has an Intel CPU from the last decade, you almost certainly have Quick Sync — Intel's hardware transcoding engine. It's excellent and it's free. You just need to pass the render device through to the container (the compose file in this guide does this).

AMD APUs also support hardware transcoding via VAAPI. Nvidia GPUs work too but require the Nvidia Container Toolkit and are more complex to set up.

For Intel Quick Sync (the most common homelab scenario):
1. Verify `/dev/dri` exists on your host
2. Pass it through to the container (see the compose file)
3. Enable hardware transcoding in Jellyfin's dashboard under Playback > Transcoding

That's it. The difference is night and day.

### Client Apps

Jellyfin has clients for the web (excellent), Android (good), iOS (good), Android TV (good), Roku (functional), Fire TV (functional via the Android app), and more. The web client is honestly the best experience. The native apps are not as polished as Plex's — this is the one area where Plex still has a genuine edge.

For smart TVs without a native app, the web client works in most built-in browsers, or use a Fire Stick / Roku / Chromecast as the client.

### Media Organization

Jellyfin's scrapers are good but not magic. Help them out by following the standard naming convention:

```
Movies/
  Movie Name (2024)/
    Movie Name (2024).mkv
TV Shows/
  Show Name (2020)/
    Season 01/
      Show Name (2020) - S01E01 - Episode Title.mkv
Music/
  Artist/
    Album (Year)/
      01 - Track Title.flac
```

This is the same convention Plex, Emby, and Kodi use. Follow it and metadata scraping just works. Deviate from it and you'll spend your weekend manually matching files.

### Storage Considerations

Media libraries get big. A modest movie collection is hundreds of gigabytes. A serious one is multiple terabytes. This is where spinning rust earns its keep — HDDs are dramatically cheaper per terabyte than SSDs, and sequential read performance (which is what streaming is) is perfectly fine on mechanical drives.

If you're running a NAS or have a dedicated storage array, mount it via NFS or SMB and point Jellyfin at it. If you're running bare drives, consider a simple MergerFS + SnapRAID setup for pooling and parity without the complexity of a full RAID array.

> **Warning:** Your media library is large and changes infrequently — it's a different backup profile than your application data. Back up your Jellyfin configuration and metadata database (small, changes often), but think carefully about whether you need to back up the media files themselves. If they're ripped from discs you own, the discs ARE the backup.

### The Jellyfin Ecosystem: From Server to Platform

Jellyfin on its own is a media server. Add a couple of companion tools and it becomes a polished, multi-user media platform that rivals commercial streaming services.

**Jellyseerr** — media request management. This is how you let family and friends request movies and shows without giving them access to your server's admin panel. Jellyseerr presents a Netflix-like discovery UI where users browse, search, and request content. It integrates with the *arr stack (below) to automatically fulfill requests, or you can approve them manually.

Why it matters: without Jellyseerr, you're the bottleneck. "Hey, can you add Season 3 of X?" becomes a text message you deal with at 10 PM. With Jellyseerr, the request goes into a queue, you approve (or it auto-approves), and the media pipeline handles the rest. Your users feel like they're using a real streaming service.

**jellyfin-accounts (Go)** — invite-based user management. Jellyfin's built-in user creation is fine for you and your household, but it doesn't scale gracefully when you want to share with friends. jellyfin-accounts-go provides invite links, self-service account creation with configurable permissions, and password reset flows — all the account management you'd expect from a real service.

Together, the stack looks like:

```
Jellyfin (media server)
  + Jellyseerr (request & discovery UI)
  + jellyfin-accounts-go (user management & invites)
  + *arr stack (automated media acquisition — optional, see below)
```

This is the difference between "I run a Plex alternative" and "I run a streaming service for my people." The polish matters — not because you're chasing features, but because a smooth experience means people actually use it, which justifies the infrastructure.

### The *arr Stack

You'll hear about Sonarr, Radarr, Prowlarr, Bazarr, Lidarr, and the rest. These are automated media management tools that monitor for new content, manage downloads, organize files, and feed them to Jellyfin. They're powerful and they're a rabbit hole.

Don't set them up in the same session as Jellyfin. Get Jellyfin working with a few manually-added files first. Understand the media server before you automate around it. The *arr stack is a chapter unto itself (and beyond the scope of this guide).

---

## Home Automation: Home Assistant

### What It Does

Unified control and automation for every smart device in your house. Lights, thermostats, locks, cameras, motion sensors, door sensors, plugs, switches, blinds, fans, sprinklers — all in one dashboard, all running locally, all without depending on some company's cloud servers.

This is the most technically ambitious service in this chapter, and also the one with the highest quality-of-life payoff if you have any smart home devices at all.

### Why It Matters

Here's the dirty secret of the smart home industry: almost every device requires a cloud connection. Your "smart" light bulb sends a command from your phone to a server in AWS, which sends a command back to the bulb sitting three feet away from you. If the company's servers go down — or the company goes bankrupt, or they push a bad firmware update, or they decide to change their pricing — your lights stop being smart.

Home Assistant runs locally. It talks directly to your devices over your local network (WiFi, Zigbee, Z-Wave, Bluetooth, MQTT). Commands execute in milliseconds, not seconds. And nothing breaks because someone's cloud had an outage.

### The Iron Rule: Everything Works Without Home Assistant

This is the most important philosophy in this section, and it's non-negotiable: **every physical control in your house must work even when Home Assistant is down.**

Your light switches still toggle lights. Your garage door button still opens the garage. Your thermostat still heats and cools. Home Assistant adds intelligence on top — automations, remote control, scheduling, dashboards — but it is never a single point of failure for basic functionality.

This is why we use Shelly relays wired behind physical switches instead of "smart switches" that require a hub or cloud connection. A Shelly relay sits between your wall switch and your light fixture. Flip the switch, the relay toggles, the light turns on. No network required. No Home Assistant required. No WiFi required. It's a relay. It relays.

When Home Assistant IS running, it can also control that relay via MQTT or HTTP — scheduling, automations, remote control, the works. But when HA is down (update, crash, your server is off), your house still works like a house. Switches switch. Lights light.

This principle extends to everything:
- **Thermostats** should have local controls and schedules. HA enhances, not replaces.
- **Garage doors** have wall buttons. HA adds remote control and notifications.
- **Locks** have physical keys or keypads. HA adds logging and automation.

If you design your smart home so that Home Assistant being unavailable means your family can't turn on a light, you've built a fragile system that will generate justified complaints. Home Assistant is the brain, not the spine. The spine is simple, reliable hardware that works with or without software.

### The Integration Ecosystem

Home Assistant supports over 2,000 integrations. That number is not a typo. If it's a smart device, Home Assistant almost certainly talks to it. The big ones:

- **Zigbee** devices (sensors, bulbs, switches) via a USB coordinator
- **Z-Wave** devices via a USB controller
- **WiFi** devices (Shelly, Tasmota, ESPHome) directly
- **MQTT** for anything that speaks it
- **HomeKit** devices (yes, you can control HomeKit devices from Home Assistant)
- **Cloud integrations** for devices that don't support local control (Nest, Ring, etc. — though the goal is to move away from these)

### Hardware: The Zigbee Coordinator

If you want to use Zigbee devices (and you should — they're cheap, reliable, low-power, and don't need WiFi), you need a USB coordinator. The go-to recommendation is the **Sonoff ZBDongle-E** (based on the EFR32MG21 chip). It's about $25 and handles a Zigbee network of 200+ devices.

Plug it into your server's USB port and pass it through to the Home Assistant container. The compose file in this guide has the device passthrough commented out with instructions.

> **Note:** If you're running Home Assistant in Docker (as opposed to Home Assistant OS on a dedicated device), some USB-dependent integrations require specific device passthrough configuration. The compose file handles this, but check the Home Assistant docs for your specific coordinator if things don't work on first try.

### The VLAN Connection

Remember your IoT VLAN from Chapter 02? This is its moment. Your smart devices live on an isolated network segment. They can't reach the internet. They can't reach your personal devices. They can't reach your dev box.

Home Assistant bridges this gap. It lives on (or has access to) the IoT VLAN, so it can communicate with your smart devices. But it also has access to your trusted VLAN for its web UI. The devices stay contained; Home Assistant is the authorized broker.

This is defense in depth applied to home automation. A compromised smart bulb can't pivot to your network. It can barely talk to the coordinator, let alone your laptop.

### Automations: Where It Gets Addictive

The dashboard is nice. Controlling your lights from your phone is nice. But automations are where Home Assistant transforms from "convenient" to "I can't live without this."

Some examples that actually improve daily life:

- **Motion + time of day = appropriate lighting.** Walk into the kitchen at 2 AM and get dim warm light, not the blazing overhead at full brightness.
- **Sunset = close blinds.** Adjusted automatically for the actual sunset time, which changes daily.
- **Door opens + nobody home = phone notification.** With a photo from the camera if you have one.
- **Temperature + humidity = fan control.** Basement dehumidifier kicks on based on actual conditions, not a timer.
- **Washer vibration sensor stops = notification.** No more forgetting laundry in the machine for two days.

The automation engine supports conditions, triggers, time-based rules, templates, and scripting. It's genuinely powerful. Which brings us to...

### The Rabbit Hole Warning

Home Assistant can consume infinite time. This is not an exaggeration. You will find yourself at 1 AM writing an automation that adjusts your living room color temperature based on the sun's position and whether someone is watching TV, and you'll think "this is totally normal."

Discipline yourself. Start with one room and one use case — typically lighting. Get it solid. Live with it for a week. Then expand. Don't try to automate your entire house in a weekend. You'll end up with a fragile web of half-finished automations that fight each other, and your partner will develop strong opinions about the "smart" house that can't reliably turn on a light.

### Container vs Dedicated Install

Home Assistant comes in several flavors:

- **Home Assistant OS**: Full operating system, runs on dedicated hardware or a VM. Includes the Supervisor, which manages add-ons (basically pre-packaged Docker containers). Best hardware support, easiest setup, most features.
- **Home Assistant Container**: Just the core application in Docker. No Supervisor, no add-ons. You manage everything else yourself (which is what you're already doing with this guide's approach).
- **Home Assistant Core**: Python virtual environment install. Maximum control, most work.

For this guide, we use the Container install. It fits our Docker Compose workflow, it's sufficient for most use cases, and you can always migrate to HA OS later if you need Supervisor add-ons. The main things you lose are: the add-on ecosystem and some automatic USB device detection. Both are workable limitations.

> **Warning:** Home Assistant Container uses host networking. This is an exception to the general "never use host networking" guidance from Chapter 03. Home Assistant needs host networking for mDNS/SSDP device discovery — without it, auto-discovery of devices on your network won't work. The compose file documents this trade-off. It's a legitimate exception, not laziness.

---

## Password Management: Vaultwarden

### What It Does

A self-hosted, Bitwarden-compatible password manager. All your passwords, TOTP codes, secure notes, and credit card details stored on your hardware, synced across all your devices through the official Bitwarden clients and browser extensions.

This might be the most practically important service in your homelab. Not the most fun, not the most impressive — but the one where self-hosting has the strongest argument.

### Why Self-Host Your Passwords

Every cloud password manager is a juicy target. They store millions of users' vaults in one place. LastPass proved this isn't theoretical — their 2022 breach exposed encrypted vault data for every user. Even if the encryption holds (it should, with a strong master password), the metadata, URLs, and unencrypted fields were exposed.

Self-hosting your vault means your data is a target of one. An attacker would need to specifically target your server, not just breach a single company to get millions of vaults. The risk profile is fundamentally different.

### Vaultwarden vs Official Bitwarden Server

The official Bitwarden server is a complex multi-container deployment (SQL Server, multiple .NET services, nginx). It's designed for enterprise scale. For a homelab, it's comically overprovisioned.

Vaultwarden is a lightweight Rust reimplementation of the Bitwarden server API. Single container. SQLite database. Uses maybe 30MB of RAM. Fully compatible with all official Bitwarden clients — browser extensions, desktop apps, mobile apps. All the features including organizations, send, and emergency access.

There's no reason to run the official server for personal use. Vaultwarden is the right tool.

### Security: Treat This Differently

This is not like your other services. If Jellyfin goes down, you can't watch a movie. If Vaultwarden goes down or gets compromised, you can't log into anything, and someone else might be able to.

Concrete steps:

- **Put it behind SWAG with strict rate limiting.** Fail2ban should be configured to ban after very few failed login attempts.
- **Enable two-factor authentication.** Not optional. Use a TOTP app, not SMS.
- **Use a strong, unique master password.** This is the one password you memorize. Make it long. A passphrase is ideal.
- **HTTPS only.** Never access Vaultwarden over plain HTTP, even on your local network. The SWAG setup handles this.
- **Back up aggressively.** The SQLite database is tiny (usually under 10MB). Include it in your regular backup rotation AND do periodic encrypted exports stored offline.

> **Warning:** Keep an offline copy of your most critical passwords (email, bank, infrastructure) somewhere physically secure. If your homelab has an extended outage and your password vault is unreachable, you need to be able to log into the things that let you fix the problem. A printed sheet in a fireproof safe is unglamorous but effective.

### The Backup Strategy

Vaultwarden's data lives in a SQLite database and an attachments directory. Both are tiny. Your regular backup strategy (Chapter 06) should cover these, but add a belt-and-suspenders layer:

1. **Automated database backup**: The built-in backup mechanism or a simple `sqlite3 db.sqlite3 ".backup '/backup/db-$(date +%Y%m%d).sqlite3'"` cron job.
2. **Encrypted vault export**: Periodically export your vault from the Bitwarden client to an encrypted JSON file. Store this on a different medium — USB drive, different machine, safe deposit box.
3. **Test your restores**: Actually try restoring from backup onto a fresh Vaultwarden instance. Do this at least once. Untested backups are not backups.

---

## File Sync: Syncthing or Nextcloud

### Two Philosophies, One Problem

You want to sync files between your devices. You have two fundamentally different approaches, and the right one depends on what you actually need.

### Syncthing: The Unix Philosophy Approach

Syncthing does one thing: syncs files between devices, peer-to-peer, encrypted, with no central server. Install it on your laptop, your phone, your homelab server (as an always-on node), and your desktop. Pick folders to share. They stay in sync.

That's it. No web UI for browsing files (well, there is, but it's for configuration, not file browsing). No calendar. No contacts. No office suite. No photo gallery. Just files, synced, reliably.

Why it's great for developers:
- Sync your dotfiles across machines without a git workflow
- Share project scaffolds or templates between devices
- Keep notes (Obsidian vaults, plain text, whatever) in sync
- Conflict handling is sane — it renames the conflicting file instead of silently overwriting
- Works behind NATs, through firewalls, without port forwarding (relay servers handle introduction, data goes peer-to-peer)

Your homelab server makes Syncthing better by being an always-on peer. Without it, your laptop and phone can only sync when both are online simultaneously. With your server in the mesh, files sync to the server immediately and then to your other devices whenever they come online.

Syncthing is not included in the compose stacks because it's peer-to-peer by design — it runs on each device, not as a centralized server. Install it directly on your homelab host if you want an always-on node.

### Nextcloud: The Google Workspace Replacement

Nextcloud is a full productivity platform. File sync, yes, but also:

- Calendar and contacts (CalDAV/CardDAV)
- Photo management with AI-powered face recognition and auto-tagging
- Collaborative document editing (with the Office integration)
- Talk (video calls and chat)
- Forms, Deck (kanban boards), Notes, Bookmarks
- App ecosystem with hundreds of add-ons

It's impressive. It's also heavier, more complex, and demands more maintenance. PHP, PostgreSQL (or MySQL), Redis, a cron job that actually matters — Nextcloud is a real application stack, not a single binary.

### The Recommendation

**If you just want Dropbox replacement, use Syncthing.** It's simpler, more reliable, and does file sync better than Nextcloud does because that's all it does.

**If you want to replace Google Workspace** — calendar, contacts, documents, the whole stack — Nextcloud is the answer. But go in with eyes open: you're signing up for ongoing maintenance, PHP upgrades that occasionally break things, and an application that's genuinely complex to run well.

**Don't run Nextcloud just for file sync.** It's like buying a Swiss Army knife to open envelopes. It works, but you're maintaining a lot of tool you're not using.

> **Note:** Nextcloud is not included in this chapter's compose stacks because doing it right requires its own database, Redis, and careful tuning. It deserves its own stack (and arguably its own chapter). If you go down this road, start with the official Docker example and customize from there.

---

## Dashboard: Homepage

### What It Does

A single landing page with links, status indicators, and widgets for all your homelab services. Open a browser tab and see everything: what's running, what's down, quick links to every UI.

This sounds trivial. It is trivial. And it's surprisingly useful once you have more than a handful of services.

### Why Bother — Blinkenlights

Without a dashboard, you're either memorizing URLs (`http://192.168.1.50:8096` for Jellyfin, `https://ha.yourdomain.com` for Home Assistant, `https://status.yourdomain.com:3001` for Uptime Kuma...) or maintaining a bookmark folder that you forget to update. A dashboard with service health indicators eliminates this friction.

But let's be honest about the real reason: **this is your aquarium.**

Throughout this guide we've preached "containers are cattle, data is pets." That's operationally correct. But emotionally? You care about these things. You built them. You configured them. You nursed them through broken updates at midnight. Your Homepage dashboard is where you get to watch all your pets in one place — container status tiles blinking green, service widgets pulling live stats, resource graphs ticking along. It's the blinkenlights experience for the modern homelab.

There's genuine value in this beyond vanity. A dashboard you actually enjoy looking at is a dashboard you check regularly. And a dashboard you check regularly means you notice problems early — before a silent failure becomes a data loss event. The little green tiles aren't just satisfying; they're a passive monitoring layer. When one goes red, you notice because it breaks the pattern.

Put it on a spare tablet on your desk. Let it auto-refresh. It's part information radiator, part ambient monitoring, part proof that all the YAML was worth it.

### Homepage vs Homarr

**Homepage** (gethomepage.dev) is YAML-configured, fast, clean, and integrates with a huge number of services for live widgets (Docker container status, Jellyfin now playing, AdGuard stats, etc.). If you're comfortable with YAML — and if you've made it to Chapter 11, you are — Homepage is the right choice.

**Homarr** is drag-and-drop, more visual, easier for non-technical users to customize. If you want your partner or housemates to be able to customize the dashboard without editing YAML, Homarr is more accessible.

This guide includes Homepage in the compose stack because it fits the YAML-configured, infrastructure-as-code approach we've been using throughout.

### Integration Tips

- Set Homepage as the default page behind your SWAG reverse proxy
- Add Docker socket access for automatic container status monitoring
- Use the built-in service widgets to pull stats from Jellyfin, AdGuard, Vaultwarden, and others
- Keep the configuration in your git repo alongside your compose files

---

## Bookmarks and Read-Later

### Linkding: Minimal Bookmark Management

Linkding is a self-hosted bookmark manager with tags, search, and a browser extension. It's the answer to the question "where did I see that article about ZFS tuning three months ago?"

It replaces Pinboard, Pocket's bookmarking features, or the giant unsorted bookmark folder in your browser that you're pretending doesn't exist.

Resource usage is negligible. Setup is a single container. Maintenance is essentially zero. You add it, you use the browser extension to save links, and you forget it's self-hosted.

### Wallabag: Full Read-Later Service

Wallabag goes further than bookmarking. It's a self-hosted Instapaper/Pocket. Save an article and Wallabag downloads the full content, strips ads and navigation, and presents a clean reading view. Works offline via the mobile apps. Supports tagging, annotations, and export.

If you read a lot of long-form content and want to save it permanently (not just hope the URL still works in two years), Wallabag is the tool. If you just need bookmarks with search, Linkding is lighter and simpler.

Both are small, stable, and low-maintenance. Neither is included in the compose stacks because they're trivial single-container deploys — add them when you want them.

---

## Notes and Knowledge Management

### Obsidian + Syncthing

Obsidian is a local-first markdown note-taking app. Your notes are plain markdown files in a folder. No proprietary format, no lock-in, no database. If Obsidian disappeared tomorrow, you'd still have a folder of markdown files readable by any text editor.

The paid feature is Obsidian Sync — cross-device sync of your vault. But you have Syncthing. Point Syncthing at your Obsidian vault folder and you get the same result for free. Notes sync between your laptop, phone, and desktop through your homelab server as the always-on intermediary.

This is not a self-hosted service per se — it's a local app plus the infrastructure you already built. But it's worth mentioning because the combination of Obsidian's excellent editing experience and Syncthing's reliable sync is genuinely better than most cloud note-taking solutions.

### BookStack: Self-Hosted Wiki

BookStack is a self-hosted wiki with a clean, modern UI organized around shelves, books, and chapters. It's excellent for documenting your homelab itself — network diagrams, service configurations, troubleshooting notes, runbooks.

If your notes are primarily personal/professional (journal, project notes, research), Obsidian is probably the better tool. If you're building a shared knowledge base (homelab docs, family reference material, procedures that other people need to follow), BookStack is the better tool.

BookStack requires a MySQL/MariaDB database, so it's a multi-container deploy. Not complex, but not a one-liner either.

### Don't Overthink This

Seriously. The notes/knowledge management space has approximately ten thousand options, each with passionate advocates who will explain at length why their tool is the right one. Pick whatever you'll actually use. The best note-taking system is the one you write notes in. If that's a text file in vim, great.

---

## Serving 418: I'm a Teapot

### The Best Easter Egg in HTTP

RFC 2324 defines HTTP status code 418: "I'm a teapot." It was an April Fools' joke in 1998. It's also a perfect homelab tradition.

Set up your reverse proxy to serve a 418 response on a dedicated subdomain. Put an ASCII teapot on it. Make it the first thing you deploy. It's a smoke test for your entire SWAG + DNS + cert stack in one go, and it's funny every single time.

Here's a minimal nginx config for SWAG:

```nginx
# stacks/swag/config/nginx/proxy-confs/teapot.subdomain.conf
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name teapot.*;

    include /config/nginx/ssl.conf;

    location / {
        default_type text/plain;
        return 418 '
        _______
       |       |
       |       |
       |  418  |
    ___|       |___
   |   |_______|   |-----.
   |               |     |
    \             /      |
     \___________|______/

    I am a teapot.

    This server is a teapot. It cannot brew coffee.
    It can, however, confirm that your DNS, certs,
    and reverse proxy are all working correctly.

    RFC 2324 — https://datatracker.ietf.org/doc/html/rfc2324
';
    }
}
```

If `https://teapot.home.yourdomain.com` returns a 418 with a valid cert and an ASCII teapot, your entire edge stack is working. DNS resolves. Certs are valid. SWAG is proxying. Fail2ban is watching. You can deploy real services with confidence.

It's also a great conversation starter when someone asks what you're running. "Well, first things first — I have a teapot."

> **Note:** Some monitoring tools flag 418 as an error. You can configure Uptime Kuma or Healthchecks.io to accept 418 as a valid response code. This is the correct thing to do. The teapot is not in error. The teapot is performing exactly as designed.

---

## Your Home as a Platform: Hardware, Sensors & Custom Devices

### The Big Picture

Everything up to this point has been software running in containers. That's half the story. The other half is the physical layer — hardware devices, sensors, microcontrollers, and custom builds that turn your house from a place with a server into a genuinely interconnected platform.

Home Assistant is the hub. The rest are the spokes. And once you see how they compose, you'll understand why the "composable primitives" philosophy from Chapter 00 applies to hardware too.

### Shelly Relays: Smart Switches Without the Cloud

Shelly devices are WiFi-based relays, switches, and sensors made by a Bulgarian company that actually respects local control. Every Shelly device works over local HTTP, CoAP, or MQTT — no cloud account required, no app dependency, no telemetry.

Why Shelly specifically:

- **Local API out of the box.** No firmware flashing required (though you can flash ESPHome onto most Shellys if you want to).
- **DIN rail and in-wall form factors.** These aren't smart plugs — they go behind your existing wall switches or in your electrical panel. Your house looks normal. The switches still work manually. But now Home Assistant knows about them.
- **Power monitoring.** Models like the Shelly 1PM and Shelly Pro 4PM report real-time power consumption. You can monitor individual circuits — how much power your server rack draws, whether the dryer is done, if someone left the space heater on.
- **Robust and reliable.** These things just work. They don't need babysitting. Flash them, configure MQTT, and forget about them for years.

Practical applications:

- **Remote power cycling.** Put a Shelly relay on your server's power feed. If the box locks up hard and you're not home, you can power-cycle it from Home Assistant. This sounds paranoid until the first time you need it.
- **Garage door control.** A Shelly 1 wired to your garage door opener gives you open/close/status from Home Assistant. Add a door sensor for confirmation. Automate: close automatically at 10 PM if left open.
- **Holiday lighting.** Control outdoor circuits by schedule, sunset triggers, or manual override. No smart plugs in weatherproof boxes — a DIN rail Shelly in your panel handles it cleanly.
- **Heat monitoring.** Shelly's add-on temperature probes let you monitor enclosure temperatures, server closets, attics, freezers. Alert when thresholds are exceeded.

> **Note:** Shelly devices work on WiFi, so they go on your IoT VLAN. Home Assistant bridges the VLAN gap. The devices can't reach the internet, but HA can still control them locally. This is the architecture working exactly as designed.

### WLED: Addressable LEDs That Actually Slap

WLED is open-source firmware for ESP8266/ESP32 microcontrollers that drives addressable LED strips (WS2812B, SK6812, etc.). It turns cheap LED hardware into something with a genuinely good web UI, preset management, sync groups, and — critically — Home Assistant integration via MQTT or its native API.

What you can do:

- **Permanent holiday lighting.** WS2812B strips in outdoor channels, controlled by WLED. Every holiday, every color, every pattern — no climbing ladders to swap lights. Schedule Christmas colors from November through January, then switch to everyday accent lighting the rest of the year.
- **Bias lighting behind monitors and TVs.** Reduces eye strain, looks great, controllable from Home Assistant.
- **Under-cabinet, stairway, and accent lighting.** Motion-triggered via Home Assistant automation, with WLED handling the rendering.
- **Notification lighting.** Flash a strip red when your backup fails. Pulse blue when the doorbell rings. Use light as an ambient information display.

Hardware you need: an ESP32 board ($5-8), a WS2812B LED strip ($15-40 depending on length and density), a 5V power supply sized for your strip (roughly 60mA per LED at full white), and three wires. Flash WLED via the web installer, configure in the browser, add to Home Assistant.

WLED supports segments (different parts of a strip doing different things), sync groups (multiple controllers synchronized), and presets (save and recall configurations). Multiple WLED instances on your network discover each other automatically for sync.

Scaling up: a serious installation (say, ~1,000 pixels of permanent outdoor lighting) needs proper planning — power injection every 150-200 LEDs, weatherproof connectors, a Dig-Quad or similar multi-output controller, and a dedicated power supply. But you can start with a $20 test strip on your desk to learn the ecosystem before committing to a roofline installation.

### Custom ESP32 Projects with ESPHome

ESPHome is a framework for creating custom firmware for ESP32 and ESP8266 microcontrollers using YAML configuration. Yes, more YAML. But this time the YAML compiles to C++ firmware that runs on a $5 microcontroller, and the result integrates directly with Home Assistant.

This is where your homelab stops being "a server with some containers" and becomes a sensor network:

- **Temperature and humidity sensors** in every room (BME280 sensor + ESP32 = $8, reports to HA over WiFi)
- **Irrigation controllers** — ESP32 + relay board + solenoid valves. Schedule from Home Assistant, adjust based on weather API data, monitor soil moisture. Commercial smart irrigation controllers cost $200+ and require cloud accounts. This costs $30 in parts and runs locally forever.
- **RFID repeaters** — ESP32 + PN532 NFC reader. Scan a tag at the door and Home Assistant knows who's home. Trigger per-person lighting scenes, disable the alarm, send a notification.
- **Air quality monitoring** — PMS5003 particulate sensor + BME280. Know when to run the air purifier, when to open windows, track seasonal trends.
- **Custom control panels** — ESP32 + rotary encoder + small OLED display. A physical knob on your desk that controls volume, lighting, or anything else Home Assistant manages.

The ESPHome workflow:

1. Write a YAML config describing your sensors, outputs, and automations
2. ESPHome compiles it to firmware and flashes it to the device (OTA updates after initial flash)
3. The device appears in Home Assistant automatically
4. Data flows, automations trigger, dashboards update

> **Warning:** Custom hardware is addictive in a different way than software. You'll start with "I just want a temperature sensor in the garage" and end up with a custom PCB, a 3D-printed enclosure, and a twelve-sensor mesh network. Budget accordingly — in both money and time.

### BirdNET-Pi: When Your Homelab Listens to Nature

This one's a wildcard, and it's a perfect example of "things you can do that no cloud service offers."

BirdNET-Pi runs a neural network (Cornell Lab's BirdNET) on a Raspberry Pi with a USB microphone, identifying birds in your yard by their calls in real-time. It builds a database of what species visit, when they're active, seasonal migration patterns, and confidence-scored identifications.

What makes it a homelab project and not just a Raspberry Pi project:

- **Data feeds into Home Assistant.** You can trigger automations on bird detections — turn on a camera when a rare species is identified, log daily species counts, send a notification when the first robin of spring arrives.
- **Long-term data storage.** BirdNET-Pi generates a SQLite database of detections. Back it up with your restic setup. Analyze trends over months and years.
- **The spectrograms are fascinating.** The web UI shows real-time spectrograms with species identification overlays. It's genuinely mesmerizing and a great way to learn bird calls.
- **Pairs with outdoor microphones and your IoT VLAN.** The Pi sits on the IoT network, ships data to Home Assistant, which logs it and triggers automations.

It's a $50 project (Pi Zero 2W + USB mic + case) that produces something no commercial product replicates. And it's a perfect gateway drug to environmental monitoring — add a weather station, an all-sky camera, a lightning detector. Your homelab isn't just serving your digital life; it's observing the world around you.

### The Platform Mindset

Zoom out for a second. Look at what you've built:

- A server running containers (compute)
- A reverse proxy handling traffic (networking)
- Sensors reporting data (observation)
- Actuators controlling devices (action)
- A hub correlating everything (intelligence)
- Backups protecting it all (resilience)

This is a platform. Not in the VC-funded, growth-hacking sense. A platform in the engineering sense: a foundation that you can build arbitrary things on. Want to know when your packages are delivered? Add a camera + object detection. Want to optimize your electricity bill? Add power monitoring + time-of-use rate data. Want to know if your sump pump is running? Add a vibration sensor.

Each new capability is a composable primitive that integrates with the system you've already built. That's the payoff of doing the infrastructure right. The marginal cost of adding "one more sensor" approaches the cost of the hardware itself, because the software layer, the networking, the monitoring, and the backup strategy already exist.

Your home becomes a platform you control, extend, and maintain — not a collection of apps from different companies that may or may not still exist next year.

---

## The "One More Thing" Trap

Here's the danger of this chapter: everything in it is easy to deploy. Every service is a compose file, an `.env` file, and ten minutes. The feedback loop is intoxicating. Deploy a thing, see it work, feel the satisfaction of another green tile on your dashboard. Deploy another. And another.

This is how you end up with 40 containers, 16GB of RAM consumed, and a nagging anxiety that you don't really understand what half of them are doing. You've violated the principle from Chapter 00 — "if you can't explain why it's running, turn it off" — but each individual service seemed so reasonable at the time.

### The Complexity Budget Revisited

Go back to Chapter 00's complexity budget concept. Every service you add costs:

- **Resources**: RAM, CPU, disk space. These are finite.
- **Maintenance time**: Updates, security patches, configuration changes. These compound.
- **Cognitive load**: Another thing to understand, monitor, and troubleshoot when it breaks at 11 PM.
- **Attack surface**: Another service exposed to the network, another set of potential vulnerabilities.

### The Test

Before adding a new service, ask three questions:

1. **What problem does this solve that I'm currently feeling?** Not a hypothetical problem. Not a problem you might have someday. A problem you have right now, that's annoying enough to motivate you to maintain another service.

2. **Does someone in my household actually want this?** If you're the only person who'll use it, that's fine — but be honest about it. Don't deploy a family photo manager that nobody in your family will use just because it fills a tile on your dashboard.

3. **Am I adding this because it solves a problem, or because deploying things is fun?** Deploying things IS fun. That's valid. But recognize the motivation. If you're adding services to fill a dashboard, you've lost the plot.

### What I'd Actually Deploy First

If you're starting from zero and want a practical order:

1. **AdGuard Home** — immediate, network-wide impact, near-zero maintenance
2. **Vaultwarden** — solves a real security problem, used daily by everyone in the household
3. **Homepage** — makes everything else easier to find and monitor
4. **Jellyfin** — the crowd-pleaser, the "oh that's cool" moment for family/friends
5. **Home Assistant** — only if you have smart devices, and only one room at a time

Everything else? Add it when you feel the need. Not before.

---

## The Compose Stacks

This chapter has corresponding compose files for three stacks:

- **`stacks/apps/`** — Jellyfin, Vaultwarden, and Homepage. The core "fun stuff" bundle.
- **`stacks/dns/`** — AdGuard Home. Separate because DNS is infrastructure, not an app, and it has unique port requirements.
- **`stacks/homeassistant/`** — Home Assistant. Separate because it requires host networking and optional USB device passthrough, which makes it architecturally different from everything else.

Each stack follows the same pattern from Chapter 03: `docker-compose.yml` + `.env.example`, named volumes, resource limits, health checks, and SWAG integration where applicable.

Deploy them in order. Get each one working before moving to the next. Resist the urge to `docker compose up -d` all three simultaneously and debug a tangle of errors. Boring, sequential progress beats exciting, parallel confusion.

---

## What's Next

This chapter covered the services that make a homelab worth having. You now have ad blocking, media streaming, home automation, password management, a dashboard, and a clear framework for deciding what to add next.

The rest is up to you. Your homelab is a living system — it'll evolve as your needs change, your skills grow, and new software becomes available. The foundation from Chapters 00-10 gives you a safe, recoverable environment to experiment in. The services from this chapter give you a reason to.

Go build something cool. Just not all of it tonight.
