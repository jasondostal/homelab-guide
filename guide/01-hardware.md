# Chapter 01 — Hardware & Box Separation

The single best hardware decision you can make for your homelab is to run two boxes instead of one. Not because one box can't handle it — it almost certainly can — but because the failure modes, update cadences, and resource profiles of "home infrastructure" and "dev/AI experimentation" are fundamentally incompatible.

This chapter covers why, what hardware to buy, and how to think about the upgrade path.

---

## The Two-Box Philosophy

Your homelab will naturally develop two categories of workloads:

**Production infrastructure** — the stuff your household actually depends on. DNS resolution, ad blocking, reverse proxy, media server, file sync, Home Assistant, backups. These services need to be boring, stable, and always running. Nobody wants to hear "the internet is broken" because you were experimenting with a new container runtime.

**Dev/AI workloads** — the stuff you're actively tinkering with. Local LLM inference, code experiments, AI tooling, development environments, testing new services before promoting them to prod. These workloads are spiky, unpredictable, and occasionally crash hard.

Running both on the same box works until it doesn't. And when it doesn't, it fails in the most annoying possible way: your spouse can't watch Plex because you're running a 13B parameter model, or your DNS stops resolving because an OOM killer took out your Pi-hole alongside your runaway Python script.

### The Cortex Box

This is your dev and AI machine. Call it whatever you want — cortex, devbox, skynet, HAL. The name doesn't matter. What matters is its role:

- **Unpredictable load.** LLM inference pegs the GPU and sometimes the CPU. Training runs consume all available memory. You want this machine to be free to eat every resource it has without affecting anything else.
- **Frequent changes.** You're pulling new images, trying new tools, changing configurations constantly. This is where things break, and that's fine — breaking things is learning.
- **Acceptable downtime.** If this box is off for a day while you swap a GPU or reinstall the OS, nothing critical goes down. Your household doesn't notice.
- **GPU home.** If you have or plan to get a GPU for local inference, it lives here. Full stop.

### The Prod Utility Server

This is your infrastructure backbone. It runs the things your network depends on:

- DNS (Pi-hole, AdGuard Home)
- Reverse proxy (Traefik, Caddy, nginx-proxy-manager)
- Monitoring and alerting
- Backup orchestration
- Home automation (Home Assistant)
- Media services (Jellyfin/Plex, *arr stack)
- File sync (Nextcloud, Syncthing)

This box should be boring. You should feel mildly anxious about making changes to it. It should have scheduled maintenance windows, not yolo deployments. Its uptime target is "always" and its change velocity is "slow and deliberate."

---

## Why Separate Them

The theoretical argument is about blast radius and separation of concerns. But let's make it concrete:

### Resource Contention

A local LLM inference request can consume 8-16GB of VRAM, saturate your CPU, and spike memory usage to near-maximum. If your DNS resolver, reverse proxy, and media server are on the same box, they're competing for resources with a workload that has no concept of "sharing."

Docker resource limits help but don't fully solve this. A container limited to 4GB of RAM can still cause memory pressure that affects other containers through page cache eviction and swap thrashing. Two physical boxes eliminate this problem entirely.

### Different Update Cadences

Your prod server should be updated carefully, with tested versions, during planned windows. Your dev box should track latest, experiment freely, and break without consequences.

Trying to maintain two different update philosophies on one machine is an exercise in discipline you'll eventually fail at. It's easier when the machines are physically separate and you can't accidentally `docker compose pull && docker compose up -d` the wrong stack.

### Blast Radius

When (not if) something goes catastrophically wrong on your dev box — a kernel panic from a bad GPU driver, a runaway process that fills the disk, an experiment that corrupts the Docker daemon — your home infrastructure is unaffected. Your family can still resolve DNS, stream media, and access files.

This is the real argument. Not "if" something breaks, but "when." And when it does, you want the damage contained.

### Different Security Profiles

Your dev box might run arbitrary code, expose experimental services, and have relaxed security. Your prod server should be locked down — minimal attack surface, firewall rules, no unnecessary exposure.

Putting these on separate VLANs (covered in Chapter 02) gives you network-level isolation on top of physical separation.

---

## Minimum Viable Hardware

You don't need server-grade hardware. The entire used enterprise mini PC market exists to serve homelabbers, and it's excellent.

### The Prod Utility Server

For running Docker containers — which is mostly what a homelab does — your bottleneck is almost always RAM, not CPU. A reverse proxy, DNS resolver, media server, and a dozen other services will barely register on a modern CPU. But they will happily eat 8-16GB of RAM.

**Recommended starting point:**
- Used Dell OptiPlex Micro, Lenovo ThinkCentre Tiny, or HP EliteDesk Mini
- Intel i5 (8th gen or newer) — anything modern enough to support hardware transcoding
- 16GB RAM minimum, 32GB preferred
- 256GB SSD for OS and containers
- Price: $100-200 on eBay, r/homelabsales, or local classifieds

These mini PCs are ideal because:
- **Low power consumption:** 10-35W typical. Your electricity bill won't notice.
- **Silent or near-silent:** Important when this lives in your house, not a datacenter.
- **Small footprint:** Fits on a shelf, behind a monitor, in a closet.
- **Reliable:** Enterprise hardware that's been running 24/7 for years already. If it was going to fail, it probably would have.

> **Note:** 16GB is livable but tight once you start running more services. If the price difference is modest, go straight to 32GB. RAM upgrades on mini PCs are usually straightforward (SO-DIMM slots), so you can also start with 16GB and upgrade later.

**What about a Raspberry Pi?**

A Pi 4 or 5 with 8GB of RAM can work as a very lightweight prod server. The Pi 5 in particular is reasonably capable. But ARM architecture means some Docker images aren't available or are poorly maintained, and the SD card storage is a reliability concern (use an SSD via USB or NVMe hat).

If you already have a Pi, use it. If you're buying something, a used mini PC is a better value.

### The Cortex Box

This depends entirely on whether you want to run local AI models. Two paths:

**Without GPU (dev only):**
- Same class of mini PC as the prod server
- 32GB RAM (you'll be running dev environments, databases, testing services)
- Larger SSD (512GB+) for container images and project files
- Price: $150-250

**With GPU (local inference):**
- This is a different beast. You need a desktop-class machine with a PCIe slot.
- Used Dell OptiPlex Tower, Lenovo ThinkStation, or a custom build
- 32-64GB RAM
- NVIDIA GPU with sufficient VRAM for your target models (see GPU section below)
- 500GB+ NVMe SSD
- Price: $300-600 for the base system, plus GPU cost

---

## When and Why to Add a GPU

GPUs are expensive. A used NVIDIA RTX 3090 with 24GB VRAM — the sweet spot for local inference right now — runs $600-900. That's real money. Don't buy one speculatively.

**Buy a GPU when:**
- You've tried local inference via CPU (using llama.cpp or Ollama) and decided the speed is unacceptable for your use case
- You have a specific, ongoing use case: coding assistant, local chat, image generation, embeddings for RAG
- You've done the math on API costs vs hardware and the hardware wins for your volume

**Don't buy a GPU when:**
- "It would be cool to have"
- You want to "play with AI" (use API credits — much cheaper for experimentation)
- You think you might need it someday

### GPU Selection

For local LLM inference, VRAM is the only spec that matters. The model needs to fit in VRAM (or mostly fit, with some layers offloaded to CPU). Speed is secondary to "does it fit?"

| VRAM | What You Can Run | Typical Card |
|------|-----------------|--------------|
| 8GB | 7B models quantized (Q4), small embedding models | RTX 3060/4060 |
| 12GB | 7-13B quantized, most embedding models | RTX 3060 12GB/4070 |
| 16GB | 13B quantized comfortably, some 30B at low quant | RTX 4060 Ti 16GB |
| 24GB | 30B quantized, 70B at very low quant, most use cases | RTX 3090/4090 |
| 48GB | 70B at good quality, multiple models simultaneously | Two 3090s or A6000 |

> **Warning:** NVIDIA only. AMD ROCm support for inference is improving but still has enough rough edges that you'll spend more time debugging drivers than running models. Apple Silicon is excellent for inference but lives in a laptop, not a homelab.

The used RTX 3090 remains the best value proposition for homelab inference: 24GB VRAM, widely available, well-supported by all inference frameworks, $600-900 depending on market conditions. It's power-hungry (350W TDP) and loud, but in a dedicated box that's acceptable.

---

## Storage Considerations

Storage in a homelab splits into three tiers, and conflating them is a common mistake.

### Tier 1: OS and Containers (SSD, NVMe)

Your operating system and Docker storage (images, container layers, named volumes) should live on fast solid-state storage. This doesn't need to be large — 256-512GB is plenty for most setups. Container images are typically small, and application data should live separately.

The important thing is reliability, not performance. Any modern SSD will be fast enough. Enterprise SSDs (pulled from servers) are often cheaper per GB than consumer drives and have higher endurance ratings.

### Tier 2: Application Data (SSD or HDD)

Database files, configuration data, application state. This is the stuff that lives in your Docker volumes. Performance requirements vary — a database wants SSD, a media server's metadata is fine on spinning rust.

For most homelabs, keeping this on the same SSD as the OS is fine when you're starting out. As you grow, you might separate it to a dedicated data SSD for easier backup management.

### Tier 3: Bulk Storage (HDD, NAS)

Media libraries, backups, photos, documents. This is where large spinning drives shine. A 4-8TB drive is cheap ($80-150) and provides massive storage.

**NAS vs Direct-Attached:**

A NAS (Synology, TrueNAS, or a custom build) is excellent if you need storage shared across multiple machines, RAID redundancy, and centralized backup targets. But it's another device to manage, another thing that can fail, and another cost.

Starting out, a USB-attached external drive for backups and a large internal drive for media is simpler and cheaper. Graduate to a NAS when you feel the pain of not having one.

> **Note:** RAID is not a backup. RAID protects against disk failure. Backups protect against everything else: accidental deletion, ransomware, software bugs, your own mistakes. You need both, but backups are more important.

---

## Power Consumption and Heat

Your homelab runs 24/7 in your house. Unlike a datacenter, you pay the electricity bill and live with the heat output.

### Power Math

A mini PC draws 10-35W. Over a year at $0.12/kWh:
- 15W continuous = ~$16/year
- 35W continuous = ~$37/year

A desktop with a GPU draws 100-400W under load, but maybe 50-80W at idle:
- 60W idle continuous = ~$63/year
- Under heavy load for 4 hours/day + idle = ~$120-200/year

This is real but manageable. Two mini PCs cost less per year in electricity than a single streaming subscription.

### Heat

Every watt consumed becomes a watt of heat. A mini PC puts out negligible heat. A desktop with a GPU under load puts out as much heat as a small space heater. In winter, this is a feature. In summer, it's a problem if your server lives in a small room.

Solutions:
- Keep servers in a ventilated area (not a closed closet)
- The cortex box can be powered off when not in use — it doesn't need to run 24/7
- Consider seasonal GPU use if your cooling situation is marginal

### Noise

Mini PCs are silent or near-silent. Desktop GPUs are not. A 3090 under load sounds like a small aircraft. If your server lives anywhere you can hear it, this matters.

Aftermarket GPU coolers, undervolting, and fan curve adjustments can help. Or just put the cortex box in the basement/garage and run an Ethernet cable.

---

## The Upgrade Path

You don't need to buy everything at once. Here's the recommended order:

### Phase 1: One Box, Start Learning ($100-200)

Buy a used mini PC. Install Ubuntu Server or Debian. Install Docker. Run your first services — Pi-hole, a reverse proxy, maybe Jellyfin. Learn Docker Compose, learn to manage a Linux server, learn the basics.

This single box is both dev and prod. That's fine for now. You'll feel the pain of mixed workloads eventually, and that's when you split.

### Phase 2: Split to Two Boxes ($200-400 total)

Buy a second mini PC. Migrate your production services to the new, dedicated box. The original becomes your dev machine. Now you can experiment freely without risking your infrastructure.

Set up proper backups. Get a USB drive or a cheap cloud storage account (Backblaze B2 is ~$5/month for reasonable amounts of data). Test restoring from backup at least once.

### Phase 3: Add GPU if Needed ($600-1000)

If you're doing local AI work and CPU inference isn't cutting it, build or buy a desktop-class machine with a GPU. The old dev mini PC becomes a spare, a dedicated backup server, or gets repurposed.

### Phase 4: Add a NAS if Needed ($300-800)

When your storage needs outgrow direct-attached drives, add a NAS. A used Synology 4-bay or a custom TrueNAS build with a couple of 8TB drives gives you centralized storage with redundancy.

### Phase 5: There Is No Phase 5

Seriously. Two compute boxes, a NAS, and a managed switch is a homelab that can run virtually anything you'd want at home. Resist the urge to keep adding hardware. Each device is something you have to maintain, update, monitor, and power.

> **Warning:** The homelab hardware acquisition instinct is real. You will see a deal on a rack server and feel a primal urge to buy it. Ask yourself: "What problem does this solve that I'm currently experiencing?" If the answer is "none," close the browser tab.

---

## Hardware Summary

| Role | Recommendation | Budget | Priority |
|------|---------------|--------|----------|
| Prod server | Used mini PC, 16-32GB RAM, 256GB SSD | $100-200 | Buy first |
| Dev box | Used mini PC or desktop, 32GB RAM | $150-300 | Buy second |
| GPU | NVIDIA, 24GB VRAM (RTX 3090) | $600-900 | Only if needed |
| Backup storage | USB external drive, 2-4TB | $60-100 | Buy with first server |
| NAS | Used Synology or custom TrueNAS | $300-800 | Buy when you feel the pain |
| Network gear | Managed switch, see Chapter 02 | $50-200 | Buy when ready for VLANs |

Start with the prod server and a backup drive. That's $150-300 and gets you running. Everything else comes when you need it, not before.

The next chapter covers how to network all of this properly, which is at least as important as the hardware itself.
