# Chapter 09: Day Two Operations

Day one is when you set everything up. Day two is every day after that. And day two is where homelabs go to die.

The setup is the fun part. You're learning, building, watching things come online. There's a dopamine hit every time a new service starts working. Then a month passes. You haven't checked your backups. Two containers have pending updates. Your disk is 87% full because Docker logs have been accumulating unchecked. You notice because something breaks, not because you were watching.

This chapter is about not letting that happen. It's the least exciting chapter in this guide, and arguably the most important one.

---

## Update Strategy

Updates are the core maintenance task. Get this right and you'll avoid most of the "surprise, everything's broken" moments.

### Host OS Updates

**Security patches: automate them.**

You configured `unattended-upgrades` in the last chapter. It handles security patches automatically. That's the boring, critical stuff — OpenSSL vulnerabilities, kernel security fixes, libc patches. You do not want to be manually applying these.

**Kernel and major version updates: do them manually.**

A kernel update might change behavior that affects your containers. A major version upgrade (Ubuntu 22.04 to 24.04, for example) is a significant operation. These deserve your attention:

```bash
# Check available updates
sudo apt update && apt list --upgradable

# Review what's pending
sudo apt upgrade --dry-run

# Apply non-security updates during a maintenance window
sudo apt upgrade -y

# Kernel updates require a reboot — schedule it
sudo reboot
```

Pick a regular time for this. Sunday morning. Wednesday evening. Whatever works for your schedule. The specific time doesn't matter; having a specific time does.

### Container Updates

Container updates are trickier than host updates because there's no built-in mechanism for "security patches only." When you pull a new image, you get whatever the maintainer put in it — could be a minor security fix, could be a breaking database migration.

**The process that actually works:**

1. **Watchtower monitors and notifies** (monitor-only mode, configured in the last chapter). You get a notification when updates are available.

2. **You read the changelog.** Go to the image's GitHub page or Docker Hub listing. See what changed. Especially for databases — Postgres, MariaDB, Redis — a major version bump can require migration steps.

3. **You update during a maintenance window:**

```bash
# Pull the new image
docker compose pull <service-name>

# Recreate the container with the new image
docker compose up -d <service-name>

# Check it's healthy
docker compose ps
docker compose logs <service-name> --tail 50
```

4. **If something breaks, roll back:**

```bash
# Check what image was running before
docker images | grep <service-name>

# Pin to the previous version in docker-compose.yml
# image: service:latest  ->  image: service:1.2.3
docker compose up -d <service-name>
```

**Cadence:** Review container updates weekly or biweekly. Don't let them pile up — updating from three versions behind is scarier than updating from one version behind.

> **Warning:** Be especially careful with database container updates. Postgres, MariaDB, and similar services store data in a specific format that may not be forward-compatible. Always snapshot/backup before updating a database container. Read the release notes. "I updated Postgres and now it won't start" is a real and common homelab horror story.

### The Changelog Habit

Every time you update a service, spend two minutes skimming the changelog. You're looking for:

- **Breaking changes.** Configuration format changes, removed features, changed defaults.
- **Migration requirements.** Database schema changes, new required environment variables.
- **Security fixes.** These tell you how urgently the update should be applied.
- **Deprecation notices.** Things that will break in the *next* version, giving you time to prepare.

This feels tedious. It is tedious. It's also the difference between a smooth update and a Sunday afternoon spent debugging why your authentication system stopped working.

---

## Maintenance Routines

Routines prevent decay. Put these in your calendar. Set reminders. Treat them like any other recurring task.

### Weekly (15-20 minutes)

**Check your monitoring dashboard.**

Open Uptime Kuma, Healthchecks.io, or whatever you're using. Are all services green? Were there any blips during the week? Investigate anything that went amber, even if it recovered on its own — intermittent problems become permanent problems.

**Review fail2ban logs.**

```bash
# See who's been banned
sudo fail2ban-client status sshd
sudo fail2ban-client status nginx-http-auth

# Quick overview of ban activity
sudo zgrep "Ban" /var/log/fail2ban.log | tail -20
```

You're looking for patterns. A handful of random IPs getting banned is normal. The same IP range hitting you repeatedly might indicate targeted scanning. An internal IP getting banned means someone (or something) is misconfigured.

**Check disk space.**

```bash
# Host disk usage
df -h

# Docker disk usage
docker system df

# Top 10 largest containers by disk usage
docker ps --size --format "table {{.Names}}\t{{.Size}}"
```

If any filesystem is over 80%, investigate now. At 90%, it's urgent. At 95%, things start breaking in weird ways.

### Monthly (30-45 minutes)

**Review Docker resource usage.**

```bash
# CPU and memory usage by container
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"
```

Are any containers using more resources than expected? Memory leaks accumulate over time — a container using 200MB at startup that's now using 1.2GB might have a leak.

**Prune unused Docker resources.**

```bash
# Remove dangling images (untagged, not used by any container)
docker image prune -f

# Remove stopped containers
docker container prune -f

# Remove unused networks
docker network prune -f

# DO NOT blindly run: docker volume prune
# This deletes named volumes not attached to a running container
# If a container is stopped, its volumes are "unused"
```

> **Warning:** `docker system prune` is useful but dangerous with the `--volumes` flag. Without `--volumes`, it cleans up dangling images, stopped containers, and unused networks — generally safe. With `--volumes`, it also removes any named volume not currently attached to a running container. If you stopped a database container to update it and then run `docker system prune --volumes`, you just deleted your database. Don't use `--volumes` unless you're absolutely sure.

**Check backup sizes and verify a backup exists.**

```bash
# If using restic
restic -r /path/to/repo snapshots
restic -r /path/to/repo stats
```

Backup sizes should grow predictably. A sudden jump might mean you're backing up something new (good, if intentional) or something has generated a lot of unexpected data (investigate). A backup that hasn't changed in weeks when data should be changing means the backup job is probably failing silently.

### Quarterly (1-2 hours)

**Restore drill.**

Actually restore a backup. Not "I'm pretty sure it would work." Actually do it. Pick a non-critical service, stop it, delete its data, restore from backup, verify it works. Document any issues.

If you can't restore, you don't have backups. You have a false sense of security.

**Review network configuration.**

```bash
# List all Docker networks and connected containers
docker network ls
for net in $(docker network ls --format '{{.Name}}'); do
  echo "=== $net ==="
  docker network inspect "$net" --format '{{range .Containers}}{{.Name}} {{end}}'
  echo
done
```

Are containers on networks they shouldn't be? Are there orphaned networks from old services? Does your network segmentation still match your intended architecture?

**Audit exposed services.**

```bash
# What ports are exposed on the host?
sudo ss -tlnp

# What containers have port mappings?
docker ps --format "table {{.Names}}\t{{.Ports}}"
```

Every exposed port should be intentional and documented. If you see something you don't recognize, investigate immediately.

**Update documentation.**

Go through your docker-compose files, your notes, your network diagram. Does the documentation still match reality? If you made changes during the quarter and didn't update the docs, do it now before you forget why you made those changes.

---

## Docker Housekeeping

Docker is not self-cleaning. Left unattended, it will consume disk space until something breaks.

### Image Cleanup

Every time you pull a new version of an image, the old version becomes "dangling" — it's still on disk but nothing references it.

```bash
# See how much space images are using
docker image ls --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" | sort -k3 -h

# Remove dangling images (safe)
docker image prune -f

# Remove ALL unused images, not just dangling (more aggressive)
# This removes images not used by any existing container
docker image prune -a -f
```

The `-a` flag is more aggressive — it removes any image not currently used by a container, including tagged images you might want to use later. Use it when you're sure you want a clean slate.

### Volume Cleanup

Volumes require more caution than images because they hold actual data.

```bash
# List all volumes with their size
docker system df -v | grep "VOLUME NAME" -A 1000

# Find volumes not attached to any container
docker volume ls -f dangling=true
```

Before removing any volume, verify it's genuinely unused:

```bash
# Check what (if anything) uses a volume
docker ps -a --filter volume=<volume-name>
```

Only remove volumes you're confident are orphaned. When in doubt, leave it. Disk space is cheaper than lost data.

### Log Rotation

Docker container logs grow without limit by default. A chatty service can produce gigabytes of logs. Configure log rotation in your Docker daemon config:

```json
// /etc/docker/daemon.json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
```

This limits each container to 3 log files of 10MB each — 30MB max per container. Restart the Docker daemon after changing this:

```bash
sudo systemctl restart docker
```

> **Note:** This only applies to containers created after the change. Existing containers keep their old log settings. To apply the new settings, recreate the container: `docker compose up -d --force-recreate <service>`.

You can also set log options per-container in your Compose file:

```yaml
services:
  chatty-service:
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
```

---

## Growing the Lab

At some point, you'll want to add more. Here's how to think about it without creating a maintenance nightmare.

### When to Add a New Service

Ask yourself three questions before deploying anything new:

1. **Does it solve a real problem I have right now?** Not "might be useful someday." Not "looks cool on r/selfhosted." A real, current problem.

2. **Is the maintenance cost worth the benefit?** Every service needs updates, monitoring, backup consideration, and mental overhead. That monitoring dashboard is nice, but is it worth an extra container to maintain?

3. **Can an existing service handle this?** Before adding a dedicated wiki, can your existing note-taking app do the job? Before adding a dedicated dashboard, can Grafana (which you're already running) cover it?

The temptation to add services is strong. Resist it. The best homelab is the one with the fewest services that still does everything you need.

> **The "shiny new thing" test:** If you're excited about deploying it, wait a week. If you still want it after a week, and you can articulate the specific problem it solves, go ahead. If you've already forgotten about it, you didn't need it.

### When to Add a New Box

Physical hardware should be added when:

- **Resource contention is measurable, not theoretical.** "My containers might compete for resources" is not a reason. "My database queries are 3x slower when the AI inference server is under load" is a reason.
- **Workload isolation is required.** GPU workloads and storage-heavy workloads have fundamentally different hardware requirements. This is a legitimate reason for separate boxes.
- **Availability requirements differ.** If your core services (DNS, reverse proxy) need to stay up while you experiment on the AI stack, separate hardware makes sense.

Don't buy hardware for problems you might have. Buy it for problems you do have.

### When to Add Complexity

More VLAN rules, more authentication layers, more automation, more monitoring — each one adds operational overhead.

Add complexity when **the pain of not having it is real and recurring:**

- You've been manually checking for updates for six months and keep forgetting: add Watchtower in monitor mode.
- You've had two incidents where you couldn't figure out what was wrong because you lacked metrics: add Prometheus and Grafana.
- You've locked yourself out of a service twice because of misconfigured auth: simplify your auth setup, don't add another layer.

If you're adding complexity preemptively, you're probably creating more problems than you're solving.

---

## Incident Response for Homelabs

Things will break. Having a mental framework for responding to incidents saves time and prevents panic-driven bad decisions.

### Something's Down

Follow this order. Don't skip steps.

**1. Check monitoring.** What does Uptime Kuma / Healthchecks.io show? When did the service go down? Did anything else go down at the same time? Correlated failures point to shared infrastructure (network, host, storage).

**2. Check logs.**

```bash
# Recent logs for the service
docker compose logs <service-name> --tail 100

# If the container isn't running
docker logs <container-name> --tail 100

# System logs
journalctl -u docker --since "1 hour ago"
```

Error messages are your friend. Read them. Google them. They usually tell you exactly what's wrong.

**3. Check resources.**

```bash
# Host resources
free -h
df -h
top -bn1 | head -20

# Docker resources
docker stats --no-stream
```

Out of memory? Out of disk? CPU pegged? These are the most common causes of unexplained failures.

**4. Check network.**

```bash
# Can the container resolve DNS?
docker exec <container> nslookup google.com

# Can it reach its dependencies?
docker exec <container> ping -c 1 <dependency-container>

# Are the Docker networks healthy?
docker network ls
docker network inspect <network-name>
```

**5. Restart.** If logs and resources don't reveal the issue, restart the container. If that doesn't fix it, restart the Docker daemon. If that doesn't fix it, you have a deeper problem.

```bash
# Restart the container
docker compose restart <service-name>

# Restart Docker daemon (affects all containers)
sudo systemctl restart docker
```

### Something's Been Compromised

If you suspect a container or host has been compromised:

**1. Isolate.** Disconnect the affected machine from the network. If it's a container, stop it and disconnect it from all Docker networks. Don't delete anything yet — you might need it for forensics.

```bash
# Stop the container
docker stop <container-name>

# Disconnect from all networks
docker network disconnect <network> <container-name>
```

**2. Assess.** What was the container's access? What networks was it on? What volumes did it have? What credentials did it have access to? Assume any credential the compromised container could access has been stolen.

**3. Rebuild, don't repair.** You cannot trust a compromised system. Don't try to "clean" it. Rebuild the container from a known-good image. If the host was compromised, reinstall the OS and restore from a backup that predates the compromise.

**4. Rotate credentials.** Every password, API key, and certificate that the compromised container could have accessed needs to be changed.

**5. Understand how it happened.** Check logs, review your configuration, figure out the entry point. If you don't understand how the breach happened, you can't prevent it from happening again.

### You Locked Yourself Out

This happens to everyone. You changed SSH config and can't log in. You misconfigured the reverse proxy and can't reach any web services. You set up firewall rules that block your own access.

**The prevention is documentation.** Before you change any access configuration, write down the recovery procedure. Specifically:

- **Physical access plan.** Can you plug a keyboard and monitor into the server? Is it in a closet you can get to? For a headless mini PC, do you have a crash cart (portable keyboard/monitor)?
- **Out-of-band access.** Does your server have IPMI/iDRAC/iLO? Is it configured? Can you access it from another device?
- **Serial console.** Some servers support serial console access. Configure it before you need it.
- **Recovery boot.** Can you boot from a USB drive to fix the filesystem?

Document these procedures in a place you can access when the server itself is unreachable. A note on your phone. A printed sheet. A file in your cloud storage. Not on the server you just locked yourself out of.

---

## Documentation

"I'll remember why I did this." You won't. Document it now.

### The CHANGELOG

Keep a `CHANGELOG.md` in your homelab repository. Every change gets an entry:

```markdown
# Homelab Changelog

## 2025-03-15
- Updated Postgres from 15.4 to 16.2. Required data directory migration.
  Followed: https://www.postgresql.org/docs/16/upgrading.html
- Added memory limits to all AI stack containers after OOM incident.

## 2025-03-08
- Added Authelia for SSO. Configured for TOTP 2FA.
- Moved all web services behind Authelia authentication.
- Disabled basic auth on services that now use Authelia.

## 2025-02-20
- Replaced Watchtower auto-update with monitor-only mode after
  unattended MariaDB update caused 2-hour outage.
```

This is the single most useful document you'll maintain. When something breaks and you think "did I change something recently?", the changelog answers that question instantly.

### Document Non-Obvious Decisions

Code comments, but for infrastructure. When you do something that future-you will question, explain why:

```yaml
services:
  dns-server:
    network_mode: host
    # HOST NETWORKING REQUIRED: Pi-hole needs to bind to the host's
    # actual IP for DHCP to work. Docker's NAT breaks DHCP relay.
    # See: https://github.com/pi-hole/docker-pi-hole/issues/1234
```

```yaml
  media-server:
    # Pinned to 1.32.x because 1.33 changed the transcoding pipeline
    # and broke hardware acceleration on our GPU. Revisit when
    # https://github.com/example/issue/5678 is resolved.
    image: media-server:1.32.8
```

The "why" is always more important than the "what." Anyone can see *what* you did by reading the config. Only documentation tells them *why*.

### Network Diagrams

You don't need Visio. You don't need a fancy diagramming tool. An ASCII diagram in a markdown file is infinitely better than nothing:

```
                        Internet
                            |
                      [Router/Firewall]
                            |
                    --------+--------
                    |                |
              VLAN 10 (Home)   VLAN 20 (Lab)
                    |                |
              Home devices     [Lab Switch]
                                    |
                        +-----------+-----------+
                        |           |           |
                    [NAS/Storage] [App Server] [Cortex]
                        |           |           |
                     Backups     SWAG/Apps    AI Stack
                     Media       Postgres     Ollama
                     Shares      Monitoring   pgvector
```

Update it when you add or remove hardware. Keep it in your homelab repo. It will save you (or whoever inherits your lab) hours of "wait, what's plugged into what?"

### The Bus Factor Test

Could someone else maintain your homelab if you were unavailable for a month? Not rebuild it from scratch — just keep it running. Apply updates. Fix basic problems. Know where the backups are.

If the answer is no, your documentation is insufficient. This isn't about handing off your hobby. It's about resilience. What if you're sick? On vacation? What if your family needs to access files on the NAS and you're not around to troubleshoot?

Write the documentation that makes this possible:

- Where are the servers physically located?
- How do you log in?
- Where are the passwords stored?
- What's the backup situation?
- What do the monitoring alerts mean?
- Who to contact if something is truly broken?

---

## The Sustainability Mindset

Your homelab exists to make your life easier. The moment it becomes a second job, something has gone wrong.

### The 30-Minute Rule

If routine maintenance takes more than 30 minutes a week, your lab is too complex for its current level of automation. Either:

- **Automate more.** Set up the monitoring, the notifications, the log rotation. Let machines do machine work.
- **Simplify.** Remove services you're not using. Consolidate where possible. Fewer moving parts means less maintenance.
- **Accept the complexity.** If you genuinely need everything you're running, the maintenance time is the cost. Budget for it explicitly.

### Automate the Boring Stuff (But Understand It First)

Automation is powerful. Blind automation is dangerous. Before you automate something:

1. Do it manually at least three times. Understand the process, the edge cases, the failure modes.
2. Write a script that does it. Test the script. Test the failure cases.
3. Schedule the script. Monitor its output. Check that it's actually running.
4. Trust but verify. Periodically do the task manually to confirm the automation is still working correctly.

Don't automate something you don't understand. You'll end up with a system that works great until it doesn't, and you won't know how to fix it because you never learned how it works.

### It's Okay to Turn Things Off

Not every service needs to run 24/7. That AI inference server you use during work hours? Shut it down at night. That development database? It doesn't need to run on weekends.

```bash
# Simple cron job to stop the AI stack outside work hours
# crontab -e
0 22 * * * cd /home/user/cortex && docker compose stop
0 7 * * 1-5 cd /home/user/cortex && docker compose start
```

This saves electricity, reduces wear on hardware, and simplifies your security surface. A powered-off machine can't be compromised.

### The Services Audit

Once a quarter, go through your running services and ask:

- **When did I last use this?** If the answer is "I don't remember," it's a candidate for removal.
- **What would happen if I turned it off?** If the answer is "nothing," turn it off.
- **Is there a simpler alternative?** Could two services be replaced by one? Could a self-hosted service be replaced by a managed one that's less maintenance?

Homelabs have a natural tendency toward accumulation. Fight it. Every service you remove is a service you don't have to update, monitor, back up, or troubleshoot.

---

## The Long Game

A homelab that survives past the initial enthusiasm is one that's been designed for the long game. That means:

- **Consistent configuration.** Use the same patterns across all services. Same logging config, same network naming, same volume mount conventions. Consistency reduces cognitive load.
- **Version control everything.** Every `docker-compose.yml`, every config file, every script. If your server dies, you should be able to rebuild from your Git repo and your backups.
- **Incremental improvement.** Don't try to build the perfect lab in a weekend. Add one service, get it stable, document it, then consider the next one. Rushing leads to technical debt that compounds.
- **Know when to stop.** Your homelab doesn't need to do everything. It needs to do the things that matter to you, reliably, with minimal ongoing effort. That's success.

The best homelab isn't the one with the most services or the most hardware. It's the one that runs quietly in the background, doing its job, requiring minimal attention, and reliably being there when you need it.

That's the goal of day two operations: make the boring parts boring, so the interesting parts stay interesting.
