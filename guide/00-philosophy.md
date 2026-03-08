# Chapter 00 — Philosophy & Principles

Before you buy hardware, before you pull your first container image, before you touch a single YAML file — you need to decide what you're actually doing here and why.

This chapter is the most important one. Everything else flows from the decisions you make here. Skip it and you'll end up with a tangled mess of containers you're afraid to touch, running services you forgot you started, with no idea how to rebuild any of it.

---

## Why Self-Host at All

Let's be honest: for most things, a cloud service is easier. Someone else handles uptime, backups, security patches, and scaling. You pay a monthly fee and it just works. So why bother running things yourself?

There are exactly four good reasons, and you should know which ones matter to you:

### 1. Ownership

When you self-host, you own your data. Not "own" in the sense of a Terms of Service that says you retain rights while they train models on it. Actually own. On a disk you can hold in your hand.

This matters for things like:
- Family photos and videos
- Personal documents and notes
- Home automation data
- Password vaults
- Communication history

When a cloud provider decides to shut down a service, change pricing, or alter their terms, you're not scrambling. You already have the thing.

### 2. Learning

This is the reason most people start, and it's underrated. Running infrastructure teaches you things that reading documentation never will. You will learn more about DNS in a weekend of debugging split-horizon resolution than in a year of using Cloudflare's dashboard.

If you work in software, a homelab is a low-stakes environment to understand the systems your code runs on. If you don't work in software, it's an excellent way to develop operational thinking.

### 3. Cost

This one is nuanced. Self-hosting is cheaper *at scale* and *over time*, but it's more expensive up front. A $150 mini PC running Jellyfin, Nextcloud, Pi-hole, and a reverse proxy replaces maybe $30-50/month in cloud services. That's a 3-5 month payback period, which is genuinely good.

But if you factor in your time — don't. Seriously. If you're counting your hourly rate against homelab time, you're thinking about it wrong. The time is the learning, and the learning is the point.

### 4. Privacy

You can use a VPN. You can use encrypted services. You can read privacy policies. Or you can just... run it yourself. When your DNS resolver, your file sync, your media server, and your password manager all run on hardware in your house, the attack surface for your personal data shrinks dramatically.

This doesn't mean self-hosted is automatically more secure — a misconfigured Nextcloud is worse than Google Drive. But it means the security is *your responsibility and under your control*, which is a trade-off worth making if you're willing to do the work.

> **Note:** If none of these four reasons resonate with you, that's fine. A homelab isn't morally superior to using cloud services. It's a choice with trade-offs.

---

## What We Optimize For

Every system has implicit priorities. Most people never articulate theirs, and their homelab reflects that — a grab bag of whatever was interesting that week. Here are ours, in order:

### Reliability > Features

A service that runs correctly 99.9% of the time beats a service with twice the features that crashes every other week. This means:

- Pick boring, well-maintained software over shiny new projects
- Don't run beta versions on your prod server
- If something works, resist the urge to replace it with something "better"
- Test changes on your dev box before touching prod

### Understanding > Convenience

You should be able to explain every running container: what it does, why it's there, what depends on it, and what happens if it dies. If you can't, you've added complexity without understanding, and that's technical debt.

This means:
- No "just deploy it and see" on prod
- Read the docs before you `docker compose up`
- Understand the config options you're setting, not just copy-paste from a blog post
- When something breaks, fix it yourself before asking for help — you'll learn more

### Simplicity > Elegance

The clever solution is almost never the right one. Docker Compose is not elegant. It's a YAML file that describes containers. That's it. And that's why it works — there's nothing to misunderstand.

When you're tempted to add Ansible, Terraform, a custom bash framework, or a CI/CD pipeline, ask: "What problem does this solve that I'm currently feeling?" If the answer is "none, but it would be cool," don't do it.

---

## The "Burn It Down" Test

Here's the single most important test for your homelab:

**If your server's SSD died right now, could you rebuild everything from scratch in under an hour?**

Not "recover from backup." Rebuild. From nothing. A fresh OS install, your compose files, your environment variables, your data restored from backup. Everything back to working.

If the answer is no, your setup is too complex, too manual, or too undocumented. This test forces several good practices:

- **Infrastructure as code:** Your compose files and configs live in a git repo. Not on the server. In a repo you can clone from anywhere.
- **Data separation:** Your application data (databases, media, configs) is separate from your infrastructure (compose files, env templates). One is in git, the other is in backups.
- **No snowflakes:** If you hand-edited a config file inside a container, you've created a snowflake. Next rebuild, you'll forget that edit and spend hours debugging.
- **Documented secrets:** You have a system for your passwords, API keys, and certificates. You know where they are and how to recreate them.

Practice this. Seriously. Once a quarter, pretend your server died. Walk through the rebuild mentally. Better yet, actually do it on your dev box. You'll find the gaps.

---

## Pets vs Cattle, But for Homelabs

In the cloud world, "pets vs cattle" is a well-worn metaphor. Pets are servers you name, nurture, and nurse back to health when they get sick. Cattle are interchangeable — if one is unhealthy, you replace it.

In a homelab, the answer is: **lean toward cattle, but acknowledge some pets.**

Your containers should be cattle. If a container is misbehaving, you should be able to `docker compose down && docker compose up -d` without thinking twice. This means:
- No persistent state inside containers (use volumes)
- No manual configuration after startup (use environment variables and config files)
- No fear of destruction (you can always recreate it)

But your hardware is a pet. You probably have one or two boxes. You care about them. You might even name them (go ahead, it's fine — just don't get emotionally attached to the OS install). The hardware itself gets pet treatment: firmware updates, monitoring, dust cleaning, graceful shutdowns.

Your data is a pet too. Databases, photos, documents — these are irreplaceable. Treat them accordingly: backups, integrity checks, redundancy where it matters.

The mental model is:

| Thing | Treatment | Why |
|-------|-----------|-----|
| Containers | Cattle | Rebuildable from compose files |
| Configuration | Cattle | Stored in git, reproducible |
| Hardware | Pet | Physical, limited, expensive to replace |
| Data | Pet | Irreplaceable, must be backed up |
| OS Install | Cattle-ish | Reinstallable, but annoying |

---

## Why Docker Compose Specifically

There are many ways to run services at home. Here's why we use Docker Compose and not the alternatives:

### Not Kubernetes

Kubernetes is designed for orchestrating containers across multiple nodes with automatic scaling, rolling deployments, and service discovery. It's extraordinary technology for running production services at scale.

You are not at scale. You have one or two boxes. Kubernetes adds massive operational complexity — etcd clusters, control planes, networking overlays, RBAC, CRDs — to solve problems you don't have. Running k3s or microk8s "because it's simpler" is still running Kubernetes. You're still learning Kubernetes concepts, debugging Kubernetes networking, and reading Kubernetes error messages.

If you want to learn Kubernetes, learn Kubernetes. Do it on your dev box. But don't run your home infrastructure on it unless you genuinely enjoy Kubernetes operations as a hobby.

### Not Bare Metal

Installing services directly on the host OS (apt install, systemd units, manual compilation) works. People did it for decades. But it creates a tangle of dependencies, version conflicts, and configuration spread across the filesystem. Uninstalling something cleanly is nearly impossible.

Docker gives you isolation. Each service gets its own filesystem, its own dependencies, its own network. You can run two services that need different versions of the same library. You can remove a service completely with `docker compose down -v`. That isolation is worth the (minimal) overhead.

### Not Proxmox-First

Proxmox is excellent virtualization software. If you need full VMs — for running Windows, for testing different Linux distros, for true isolation — Proxmox is great.

But for running homelab services, a VM per service is overkill. VMs consume more resources, take longer to start, and add a layer of management. The sweet spot is: bare metal Linux (Debian or Ubuntu Server) running Docker directly. If you later need VMs for specific use cases, you can add Proxmox or run QEMU/KVM alongside Docker.

### Why Compose Works

Docker Compose hits the sweet spot for homelabs:

- **Declarative:** Your infrastructure is described in YAML files. What you see is what you get.
- **Portable:** Compose files work on any machine with Docker installed.
- **Simple:** The learning curve is maybe a weekend. The concepts map directly to what's happening.
- **Sufficient:** For single-node deployments (which is what a homelab is), Compose does everything you need — networking, volumes, environment variables, dependencies, health checks, restart policies.
- **Ecosystem:** Almost every self-hosted application provides a docker-compose.yml example. The community has standardized on it.

---

## The Cost/Complexity Spectrum

Every piece of technology you add to your homelab sits on a spectrum:

```
Simple                                                    Complex
|----|----|----|----|----|----|----|----|----|----|----|----|
Docker    Compose    Traefik    Monitoring    Ansible    K8s
```

The rule is: **start at the left and move right only when you feel the pain that the next thing solves.**

Don't set up Prometheus and Grafana until you've been bitten by not knowing a container was down. Don't write Ansible playbooks until you've manually configured two servers and felt the pain of keeping them in sync. Don't even set up a reverse proxy until you're tired of remembering port numbers.

This isn't laziness — it's discipline. Every tool you add is a tool you have to maintain, update, debug, and understand. Complexity compounds. A homelab with 5 well-understood services beats one with 30 services you half-understand.

### The Complexity Budget

Think of your homelab as having a complexity budget. You have a limited amount of time and mental energy. Every service, every integration, every automation costs some of that budget.

When you're starting out, your budget is small. Spend it on the things that matter:
1. A working Docker setup
2. A reverse proxy with TLS
3. DNS that works
4. Backups that you've tested

That's it. That's your minimum viable homelab. Everything else is a luxury you add when the foundation is solid and you have budget to spare.

---

## "If You Can't Explain Why It's Running, Turn It Off"

This is the most important operational rule in this guide. Internalize it.

Homelabs accumulate cruft. You try a service, it's neat, you leave it running. Six months later you have 40 containers and you're not sure what half of them do. Your server is using 12GB of RAM and you don't know why.

The fix is simple and ruthless: **if you cannot, right now, explain what a container does and why you need it, stop it.** Not remove — stop. Leave it stopped for a week. If nothing breaks and you don't miss it, remove it entirely.

Regularly audit your running services:

```bash
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
```

Go through the list. For each one, answer:
- What does this do?
- Who or what uses it?
- What breaks if I stop it?
- When did I last look at it?

If you can't answer these questions, the container is dead weight. It's consuming resources, increasing your attack surface, and adding to the cognitive load of your setup.

### The Homelab Graveyard

Keep a note somewhere — a text file, a wiki page, whatever — of services you tried and removed, with a one-line note on why. This prevents the "ooh, this looks cool" cycle where you install the same thing for the third time, rediscover the same dealbreaker, and remove it again.

---

## Safety Enables Speed

This is the actual thesis of this guide. Everything else — the VLANs, the box separation, the backups, the defense in depth — exists in service of this idea:

**The point of guardrails is not to slow you down. It's to let you move fast.**

When you know your prod DNS won't go down because you tried a weird model on the cortex box, you experiment more freely. When you know restic has a verified backup from two hours ago, you `docker compose down && rm -rf` without hesitation. When you know your network segmentation means a compromised IoT device can't reach your dev box, you sleep better and tinker more.

Fear kills experimentation. A well-structured homelab removes the fear.

This is especially true for AI-assisted development. You're pulling new models, spinning up MCP servers, running inference workloads that eat RAM, connecting tools that can execute code and hit APIs. This is inherently experimental, unpredictable work. If every experiment carries the risk of breaking your home infrastructure, you'll stop experimenting. That defeats the entire purpose.

### The Composable Primitives Mindset

The tools in this guide are deliberately simple, open, and composable. A backup script is just bash. A health check is just `curl`. A compose file is just YAML. An `.env.example` is just documentation with structure.

This is the Unix philosophy applied to homelab: small, sharp tools that do one thing and interoperate freely. `restic backup && curl -fsS healthchecks.io/ping/$UUID` — that's a monitored encrypted backup in one line. No platform. No vendor lock-in. No orchestration framework.

Simple things that can interoperate become rich. A bash script that stops a container, runs a backup, restarts the container, and pings a monitoring endpoint is four primitives composed into a reliable system. Each piece is understandable, testable, and replaceable independently.

When you reach for a tool, ask: "Is this a composable primitive, or is it a platform that wants to own the whole workflow?" Prefer the primitive. You'll be able to adapt it, debug it, and teach it to someone else.

### Fail Fast, Safely

The goal is to remove friction from experimentation while containing the blast radius of failure. Every architectural decision in this guide serves one of those two purposes:

- **Remove friction:** Compose files are fast to iterate on. `.env.example` files make setup repeatable. Scripts are copy-edit-run.
- **Contain blast radius:** VLANs isolate network segments. Separate boxes isolate workloads. Backups make destruction reversible. Fail2ban and SWAG contain external threats.

If you set this up right, the cost of a failed experiment approaches zero. Try a thing. If it doesn't work, burn it down. Your data is backed up, your prod services are untouched, and you learned something. That's the whole game.

---

## Principles Summary

Before we move on to hardware, networks, and actually running things, here's the distilled version:

1. **Safety enables speed.** Guardrails aren't restrictions — they're what let you move fast.
2. **Own your reasons.** Know why you're self-hosting. Let that guide your decisions.
3. **Reliability over features.** Boring is good. Stable is good. "It just works" is the goal.
4. **Understand everything you run.** No cargo-cult configurations. No mystery containers.
5. **Pass the burn-it-down test.** If you can't rebuild in an hour, simplify until you can.
6. **Prefer composable primitives.** Simple tools that interoperate beat platforms that own the workflow.
7. **Complexity is a cost.** Add it only when you feel the pain it solves.
8. **Containers are cattle, data is pets.** Design accordingly.
9. **Audit ruthlessly.** If you can't explain why it's running, turn it off.

These aren't aspirational. They're operational. Come back to them when you're tempted to add that seventeenth monitoring dashboard or that Kubernetes cluster you definitely don't need.

Now let's talk about what to run all this on.
