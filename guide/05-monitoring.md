# Chapter 05 — Monitoring & Observability

## Right-Sizing Your Monitoring

There's a seductive trap in homelabbing: building monitoring infrastructure that's more complex than the thing it monitors. You spin up Prometheus, Grafana, Alertmanager, node-exporter, cAdvisor, and Loki — and now you have six more services to maintain, all so you can see a pretty graph of your Jellyfin container's CPU usage.

Before you install anything, ask yourself: what would actually wake me up at 3am? Not "what's interesting to look at" — what genuinely needs my attention?

For most homelabs, the answer is short:

- Is my stuff running?
- Did my backups complete?
- Are my certificates about to expire?
- Is my disk getting full?

You don't need a time-series database and a query language to answer those questions. You need something much simpler.

## Why NOT Prometheus/Grafana (For Most Homelabs)

This is going to be controversial, so let me be clear: Prometheus and Grafana are excellent tools. They're industry standard for good reason. But "industry standard" means they're designed for teams running hundreds of microservices across multiple clusters, not one person running Jellyfin and Nextcloud on a single box.

The costs:

- **Resource overhead.** Prometheus is hungry. It scrapes metrics from every target at regular intervals, stores them in a time-series database, and retains them for weeks or months. On a homelab where every gigabyte of RAM matters, this isn't free.
- **Complexity overhead.** PromQL is its own query language. Grafana dashboards require real investment to build well. Alertmanager rules need careful tuning. That's hours of configuration work.
- **Maintenance overhead.** Prometheus storage grows. Retention policies need managing. Grafana gets updated and occasionally breaks dashboards. Alert rules need updating when you add or remove services.
- **The dashboard trap.** You'll spend a weekend building beautiful dashboards. You'll look at them every day for a week. Then every few days. Then never. Meanwhile, Prometheus is still scraping metrics every 15 seconds, writing them to disk, and consuming resources for data nobody looks at.

The root issue: Prometheus solves the "I need to understand trends over time across many services" problem. If you're running 5-10 containers on one server, you don't have that problem.

## When Prometheus/Grafana IS Justified

All that said, there's a threshold where Prometheus starts making sense:

- **20+ containers** and you need to understand resource contention — which services are fighting for CPU, where memory pressure is coming from.
- **Multiple hosts** where you need a central view across machines.
- **Capacity planning** where you genuinely need to see trends — "at this growth rate, I'll need more storage in 3 months."
- **You enjoy it.** Seriously. If building dashboards and writing PromQL queries is fun for you, that's a valid reason. This is a homelab. Having fun is allowed. Just don't confuse "fun project" with "necessary infrastructure."

If you hit that threshold, set it up. But start with everything else in this chapter first, because you'll want it regardless.

## Healthchecks.io — The Right Tool for the Job

Healthchecks.io is the monitoring tool that most homelabbers should start with and many will never outgrow. It solves the most important monitoring problem — "did the thing that was supposed to happen actually happen?" — with zero infrastructure on your end.

### What It Is

Healthchecks.io is a dead man's switch service. You create checks, each with a unique ping URL. Your scripts and cron jobs hit that URL when they succeed. If the ping doesn't arrive within the expected window, Healthchecks.io alerts you.

Read that again: it alerts on the *absence* of a signal, not the presence of a problem. This is a fundamental design difference from most monitoring tools, and it's what makes it so powerful for homelab use.

Traditional monitoring: "Watch for errors and tell me when one happens."
Dead man's switch: "I expect to hear from you every hour. If I don't, something is wrong."

The dead man's switch approach catches everything — the script failing, the cron daemon crashing, the server going offline, a network partition, a DNS failure. If the ping doesn't arrive for *any* reason, you get alerted. You don't need to anticipate every failure mode.

### Why It Works for Homelabs

- **Zero infrastructure to maintain.** It's a hosted service. It doesn't run on your server. When your server is down, your monitoring is still up — which is exactly when you need monitoring the most.
- **Free tier is generous.** 20 checks with email, Discord, Slack, and Telegram integrations. That's enough for most homelabs.
- **Five-minute setup.** Create an account, create a check, add a `curl` to the end of your scripts. Done.
- **It monitors the important stuff.** Not CPU utilization — whether your backups ran, whether your certs renewed, whether your containers are healthy.

### What to Monitor

Here's a practical list of checks worth setting up:

**Backup jobs** — The most important check. Your backup script should ping Healthchecks.io on success. If the backup doesn't complete (for any reason), you know about it within hours, not weeks.

```bash
#!/bin/bash
# At the end of your backup script:
restic backup /data/volumes && \
  curl -fsS -m 10 --retry 5 https://hc-ping.com/your-uuid-here
```

**Certificate renewal** — Let's Encrypt certs expire every 90 days and auto-renew. But "auto" doesn't mean "guaranteed." Check that renewal actually happened.

```bash
# Weekly check — does the cert expire more than 30 days from now?
expiry=$(openssl x509 -enddate -noout -in /path/to/cert.pem | cut -d= -f2)
expiry_epoch=$(date -d "$expiry" +%s)
now_epoch=$(date +%s)
days_left=$(( (expiry_epoch - now_epoch) / 86400 ))

if [ $days_left -gt 30 ]; then
    curl -fsS -m 10 --retry 5 https://hc-ping.com/your-uuid-here
fi
```

**Container health** — A simple script that checks if your critical containers are running:

```bash
#!/bin/bash
all_healthy=true

for container in swag gitea vaultwarden jellyfin; do
    status=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null)
    if [ "$status" != "running" ]; then
        all_healthy=false
        echo "Container $container is $status"
    fi
done

if $all_healthy; then
    curl -fsS -m 10 --retry 5 https://hc-ping.com/your-uuid-here
fi
```

**Disk space** — Alert before you hit 90%:

```bash
usage=$(df / | tail -1 | awk '{print $5}' | tr -d '%')
if [ "$usage" -lt 90 ]; then
    curl -fsS -m 10 --retry 5 https://hc-ping.com/your-uuid-here
fi
```

**DNS resolution** — Make sure your domain still points to the right place:

```bash
expected_ip="your.public.ip"
actual_ip=$(dig +short yourdomain.com @1.1.1.1)
if [ "$actual_ip" = "$expected_ip" ]; then
    curl -fsS -m 10 --retry 5 https://hc-ping.com/your-uuid-here
fi
```

**Update checks** — Not a heartbeat, but a periodic "are there updates I should know about" check. Run weekly, ping on completion, review the output in the Healthchecks.io dashboard.

### Configuring Checks

Each check in Healthchecks.io has a few key settings:

- **Period** — How often you expect a ping. Daily backup? Set it to 24 hours. Hourly container health check? Set it to 1 hour.
- **Grace period** — How long to wait after a missed ping before alerting. If your backup usually takes 20 minutes but sometimes takes 40, set a grace period that accommodates the slow case. An hour is usually fine for daily jobs.
- **Tags** — Group related checks. "backups", "certs", "containers". Useful once you have more than a handful.

### Alerting Integrations

Healthchecks.io can alert via:

- **Email** — The default. Fine for non-urgent checks.
- **Slack/Discord** — Good for a dedicated "homelab" channel you keep an eye on.
- **Telegram** — Push notifications to your phone. Good for urgent checks (backups, disk space).
- **Webhooks** — Hit an arbitrary URL. Can trigger downstream automation.
- **Many more** — PagerDuty, OpsGenie, Pushover, Matrix, etc.

My recommendation: email for everything as a baseline, Telegram or Discord for the critical stuff (backups, cert expiry, disk space). You want the important alerts to reach you even if you're not checking email.

### Self-Hosted Option

If the idea of a third-party service monitoring your infrastructure bothers you, Healthchecks.io is open source. You can self-host it. But think carefully about where you host it — if it runs on the same server it's monitoring, it can't alert you when that server goes down. The whole point is that the monitor is independent of the monitored.

If you self-host, run it on a different machine, a cheap VPS, or even a Raspberry Pi on a different network segment.

## Uptime Kuma — The Local Complement

Uptime Kuma fills a different niche than Healthchecks.io. Where Healthchecks.io monitors whether your scheduled jobs complete, Uptime Kuma actively probes your services and checks if they're responding.

### What It Does

- **HTTP monitoring** — Hit a URL, check for a 200 status code (or whatever you expect).
- **TCP monitoring** — Check if a port is open and accepting connections.
- **DNS monitoring** — Verify DNS resolution returns expected results.
- **Docker container monitoring** — Check container status via the Docker socket.
- **Ping monitoring** — Basic ICMP connectivity checks.

It runs inside your network, so it can monitor internal services that aren't exposed to the internet. It checks every 60 seconds (configurable) and shows you uptime history, response times, and certificate expiry.

### When to Use It

Uptime Kuma is optional. Healthchecks.io covers the critical stuff. But Uptime Kuma adds value if:

- You want a **status page** — a single dashboard showing the health of all your services at a glance. Uptime Kuma has a beautiful public status page feature.
- You want to monitor **response times** — not just "is it up" but "is it slow." If your Nextcloud starts responding in 5 seconds instead of 200ms, Uptime Kuma will show the trend.
- You want **internal monitoring** — checking services that aren't exposed to the internet and that Healthchecks.io can't reach.

### The Setup

```yaml
services:
  uptime-kuma:
    image: louislam/uptime-kuma:latest
    container_name: uptime-kuma
    volumes:
      - ./uptime-kuma/data:/app/data
    restart: unless-stopped
    networks:
      - proxy
```

No published ports — it goes behind SWAG like everything else. Add monitors for each service through the web UI. It's point-and-click, no config files to write.

> **Note:** Uptime Kuma monitors your services from inside your network. It will happily tell you everything is fine while your ISP is down and nothing is reachable from outside. That's why Healthchecks.io (or any external monitor) remains valuable — it sees what the outside world sees.

## Docker Health Checks

Docker has a built-in health check mechanism that most people ignore. It's worth using because it feeds into everything else.

A health check is a command that Docker runs periodically inside the container. If it exits 0, the container is "healthy." If it exits 1, the container is "unhealthy." If it fails several times in a row, Docker marks the container as unhealthy.

```yaml
services:
  gitea:
    image: gitea/gitea:latest
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/api/healthz"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
```

What this gets you:

- `docker ps` shows health status — you can see at a glance if something is wrong.
- Your container health monitoring script (the one that pings Healthchecks.io) can check `docker inspect --format='{{.State.Health.Status}}'` instead of just checking if the container is "running." A container can be running but broken.
- Docker Compose `depends_on` with `condition: service_healthy` ensures services start in the right order based on actual readiness, not just container creation.

The `start_period` is important — it gives the container time to initialize before Docker starts counting health check failures. Without it, slow-starting services (Java apps, databases) will be marked unhealthy during normal startup.

### Health Checks for Common Services

Not every container image includes `curl` or `wget`. Here are patterns for different situations:

```yaml
# For containers with curl
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:8080/health"]

# For containers with wget but not curl
healthcheck:
  test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:8080/health"]

# For containers with neither — check if a port is listening
healthcheck:
  test: ["CMD-SHELL", "nc -z localhost 8080 || exit 1"]

# For databases — use the client tool
healthcheck:
  test: ["CMD", "pg_isready", "-U", "postgres"]
  # or
  test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
```

## The "Monitor the Monitor" Problem

If your monitoring goes down, who monitors the monitoring?

This isn't a theoretical concern. If you run Uptime Kuma on the same server as your services, and that server goes down, Uptime Kuma goes down with it. Your status page shows green because it stopped updating, not because everything is fine.

Solutions, in order of practicality:

1. **Healthchecks.io as your primary monitor.** It runs externally. Your server going down doesn't affect it. It alerts on the absence of pings, so "server went down and nothing is reporting" triggers alerts automatically. This is the simplest and most robust approach.

2. **A daily heartbeat you eyeball.** Set up a daily summary — Healthchecks.io sends a daily digest email showing all your check statuses. Spend 30 seconds looking at it with your morning coffee. If you don't get the email, your monitoring might be broken.

3. **Cross-monitoring between machines.** If you have multiple servers, have each one monitor the others. Server A checks if Server B's services are responding, and vice versa. This only works if you have multiple machines.

The elegant thing about Healthchecks.io is that it naturally solves this problem. If your server is down, your scripts don't run, the pings don't arrive, and you get alerted. No additional infrastructure needed. The monitor monitors itself by virtue of its design.

## What Not to Monitor

Alert fatigue is real and it will wreck your monitoring culture faster than anything. When every alert is urgent, none of them are. You'll start ignoring alerts, and then the one that matters gets lost in the noise.

Rules:

**If you won't act on it, don't alert on it.** Your Plex container restarted at 3am and was back up in 10 seconds? That's a log entry, not an alert. Your CPU hit 95% for 30 seconds during a transcode? Normal. Don't alert.

**Monitor outcomes, not metrics.** "The backup succeeded" is actionable. "Disk I/O is 85%" is not, unless you've established a threshold that meaningfully correlates with user-visible problems.

**Start with fewer alerts and add more.** It's much easier to add a new alert when you discover a gap than to dial back a system that's crying wolf. Start with: backups, disk space, cert expiry, and critical container health. That's it. Add more only when you find yourself thinking "I wish I'd known about that sooner."

**Schedule, don't alert, for non-urgent things.** OS updates available? Don't alert — run a weekly check and review the output at your leisure. Container images have new versions? Same thing. These are maintenance tasks, not emergencies.

## Log Aggregation

### Keep It Simple

Docker's default `json-file` logging driver writes container logs to JSON files on disk. With rotation configured, this is sufficient for most homelabs:

```yaml
# In your docker daemon config (/etc/docker/daemon.json)
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
```

This keeps at most 30MB of logs per container (3 files of 10MB each). That's enough history for troubleshooting without eating your disk.

To read logs:

```bash
# Recent logs from a specific container
docker logs --tail 100 gitea

# Follow logs in real time
docker logs -f gitea

# Logs since a specific time
docker logs --since "2024-01-15T10:00:00" gitea

# Grep through logs
docker logs gitea 2>&1 | grep "error"
```

This covers 99% of homelab log analysis needs. Something broke, you check the logs, you find the error, you fix it.

### What About ELK / Loki / etc.?

Elasticsearch + Logstash + Kibana (ELK) is the enterprise standard for log aggregation. Loki + Grafana is the lighter-weight alternative. Both are powerful tools for searching and analyzing logs across many services.

For a homelab, they're almost certainly overkill. Here's the test:

- Are you running **20+ containers** and need to correlate logs across services? Consider it.
- Are you doing **compliance or audit work** that requires centralized, searchable log retention? Consider it.
- Do you just want to **see what's happening when things break**? `docker logs` is fine.

If you do decide you need centralized logging, Loki is the lighter option. It doesn't index log contents (like Elasticsearch does), it indexes metadata (labels). This makes it dramatically less resource-intensive. But even Loki is another service to run, store data for, and maintain.

My recommendation: `docker logs` with rotation. If and when that stops being enough, you'll know, because you'll find yourself frustrated by the limitations. That's the time to upgrade, not before.

## Putting It All Together

A practical monitoring setup for a homelab with 5-15 services:

1. **Healthchecks.io** (free tier) — 5-10 checks covering backups, cert renewal, disk space, container health, DNS.
2. **Cron scripts** that run your checks and ping Healthchecks.io on success.
3. **Docker health checks** on all containers so `docker ps` gives you meaningful status.
4. **Docker log rotation** configured in daemon.json.
5. **(Optional) Uptime Kuma** if you want a status page or response time tracking.

Total resource cost: Uptime Kuma uses maybe 100MB of RAM. Everything else runs externally or as lightweight cron jobs. Compare that to a Prometheus + Grafana + Alertmanager + exporters stack that easily consumes 1-2GB of RAM.

You can always add more later. Start simple, add complexity only when the simple approach fails you. That's the homelab way.
