# Chapter 03 — Docker Foundations

You have hardware. You have a network. Now let's talk about how to actually run things.

This chapter establishes the patterns and conventions for running Docker containers in a homelab. These aren't the only way to do it — they're an opinionated set of conventions that optimize for clarity, reproducibility, and not hating your future self when you come back to this setup six months from now.

---

## Compose-First Mindset

Docker Compose is the right abstraction for a homelab. Not `docker run` commands you paste from blog posts and immediately forget. Not Portainer templates that hide what's actually happening. Not Kubernetes manifests that solve distributed systems problems you don't have.

Compose files are:
- **Readable.** A compose file tells you everything about how a service runs. What image, what ports, what volumes, what environment variables, what networks, what depends on what.
- **Versionable.** They're text files. They go in git. You can diff them, review changes, and roll back.
- **Reproducible.** `docker compose up -d` on a fresh machine with the same compose file and env vars produces the same result. Every time.
- **Self-documenting.** A well-written compose file is its own documentation. You shouldn't need a wiki page to explain how a service is configured — the compose file already does.

The `docker run` command is for quick tests and debugging. For anything that persists beyond "let me try this real quick," write a compose file.

---

## Stack Organization

### One Stack Per Logical Service Group

Don't put everything in one giant `docker-compose.yml`. Don't put every single service in its own isolated compose file either. Group services that work together into logical stacks.

Good groupings:

```
stacks/
  networking/          # Traefik + Cloudflare DDNS + Authelia
  dns/                 # Pi-hole or AdGuard Home
  monitoring/          # Prometheus + Grafana + node-exporter + alertmanager
  media/               # Jellyfin + Sonarr + Radarr + Prowlarr + qBittorrent
  cloud/               # Nextcloud + MariaDB + Redis
  homeassistant/       # Home Assistant + MQTT + Zigbee2MQTT
  backups/             # Duplicati or Restic + scheduler
```

Bad groupings:

```
# Too granular — every service is its own stack
stacks/
  traefik/
  cloudflare-ddns/
  authelia/
  prometheus/
  grafana/
  node-exporter/
  ...

# Too monolithic — everything in one file
stacks/
  everything/
    docker-compose.yml  # 500 lines of YAML, good luck
```

The grouping principle is: **services that are deployed together, updated together, and depend on each other belong in the same stack.** Prometheus and Grafana are always deployed together and Grafana reads from Prometheus — same stack. Traefik and your media server are independent — different stacks.

### Why This Matters

When you need to update your monitoring stack, you `cd monitoring && docker compose pull && docker compose up -d`. You don't touch DNS. You don't restart your media server. The blast radius of a failed update is contained to one logical group.

When you need to debug a network issue, you look at the networking stack. When you need to check media service configs, you look at the media stack. Cognitive load stays manageable because each stack is small enough to hold in your head.

---

## The Stack Directory Pattern

Every stack gets its own directory with a consistent structure:

```
stacks/media/
  docker-compose.yml     # The compose file
  .env                   # Actual environment variables (NEVER in git)
  .env.example           # Template with dummy values (in git)
  config/                # Bind-mounted config files (optional)
  README.md              # Stack-specific notes (optional, only if needed)
```

### The .env.example Pattern

This is a critical convention. Your `.env` file contains real credentials, API keys, and paths specific to your machine. It must never be committed to git.

Your `.env.example` file is a template that documents what variables exist and what they're for:

```bash
# .env.example — copy to .env and fill in real values

# Timezone for containers that need it
TZ=America/Chicago

# User/group IDs for file permission mapping
PUID=1000
PGID=1000

# Jellyfin
JELLYFIN_MEDIA_PATH=/path/to/your/media

# Sonarr API key — generate in Sonarr UI under Settings > General
SONARR_API_KEY=your-api-key-here

# qBittorrent
QBIT_WEBUI_PORT=8080
```

And your `.gitignore`:

```
.env
!.env.example
```

When you rebuild from scratch (remember the burn-it-down test from Chapter 00), you clone your repo, copy `.env.example` to `.env`, fill in the values, and `docker compose up -d`. That's the workflow.

---

## Naming Conventions

Consistency in naming prevents confusion, makes log reading easier, and helps with automation. Pick conventions and stick with them.

### Container Names

Use the `container_name` directive in compose. Without it, Docker generates names like `media-jellyfin-1` based on the directory and service name. Explicit names are clearer.

Convention: `stackname-servicename`

```yaml
services:
  jellyfin:
    container_name: media-jellyfin
    image: jellyfin/jellyfin:latest

  sonarr:
    container_name: media-sonarr
    image: linuxserver/sonarr:latest
```

This gives you predictable names in `docker ps` output, log queries, and reverse proxy configs.

### Network Names

Use the `name` property on networks to set explicit names. Without it, Docker prepends the project directory name, giving you `media_frontend` instead of `frontend`.

```yaml
networks:
  proxy:
    name: proxy
    external: true  # Created outside this stack, shared across stacks

  media-internal:
    name: media-internal  # Internal to this stack
```

### Volume Names

Same principle. Name your volumes explicitly:

```yaml
volumes:
  jellyfin-config:
    name: jellyfin-config
  jellyfin-cache:
    name: jellyfin-cache
```

---

## Docker Networks

Docker networking is where most homelab confusion lives. Here's the mental model.

### Bridge Networks

Every Docker installation has a default bridge network. All containers attach to it unless you specify otherwise. Containers on the default bridge can reach each other by IP but not by name (DNS resolution doesn't work on the default bridge).

**Don't use the default bridge.** Create custom bridge networks instead.

Custom bridge networks provide:
- **DNS resolution.** Containers can reach each other by container name or service name.
- **Isolation.** Containers on different custom networks can't communicate unless both are attached to a shared network.
- **Control.** You decide which containers can talk to which.

### The Shared Proxy Network Pattern

Your reverse proxy (Traefik, Caddy, etc.) needs to reach the web-facing containers in every stack. The cleanest way to do this:

1. Create an external network for the proxy:

```bash
docker network create proxy
```

2. In each stack, attach web-facing services to the proxy network:

```yaml
# stacks/media/docker-compose.yml
networks:
  proxy:
    name: proxy
    external: true
  media-internal:
    name: media-internal

services:
  jellyfin:
    container_name: media-jellyfin
    networks:
      - proxy          # Reachable by Traefik
      - media-internal  # Can reach internal services

  sonarr:
    container_name: media-sonarr
    networks:
      - proxy
      - media-internal

  prowlarr:
    container_name: media-prowlarr
    networks:
      - media-internal  # NOT on proxy — no direct web exposure
```

```yaml
# stacks/networking/docker-compose.yml
networks:
  proxy:
    name: proxy
    external: true

services:
  traefik:
    container_name: net-traefik
    networks:
      - proxy  # Can reach all web-facing services
    ports:
      - "80:80"
      - "443:443"
```

This pattern is clean: Traefik sees every service on the `proxy` network. Internal services (databases, internal APIs) live on stack-specific networks and are invisible to Traefik and to other stacks.

### When to Use Overlay Networks

Overlay networks span multiple Docker hosts. In a single-host homelab, you don't need them. If you run two Docker hosts (prod and dev), overlay networks require Docker Swarm mode, which adds complexity.

For multi-host communication in a homelab, it's simpler to expose services on specific ports and connect via the host network. Save overlay networks for when you actually need them (you probably won't).

---

## Volume Management

Volumes are how containers persist data. Get this wrong and you'll lose data or struggle with backups.

### Named Volumes vs Bind Mounts

**Named volumes** are managed by Docker. They live in `/var/lib/docker/volumes/` and Docker handles the filesystem.

```yaml
volumes:
  postgres-data:
    name: postgres-data

services:
  postgres:
    volumes:
      - postgres-data:/var/lib/postgresql/data
```

**Bind mounts** map a specific host directory into the container.

```yaml
services:
  jellyfin:
    volumes:
      - /opt/homelab/media/movies:/media/movies:ro
      - ./config/jellyfin:/config
```

### When to Use Which

**Use named volumes for:**
- Database data (PostgreSQL, MariaDB, SQLite files)
- Application state that you don't need to access from the host
- Anything where Docker managing the filesystem is fine

**Use bind mounts for:**
- Media files and large data sets (you want these on a specific disk/path)
- Configuration files you edit on the host
- Shared data between containers and the host
- Anything you need to back up via host-level tools (rsync, restic)

**The trade-off:** Named volumes are cleaner and more portable. Bind mounts give you more control over location and easier backup access. For most homelab use cases, bind mounts are more practical because you want to control where your data lives and back it up with standard tools.

### Backup Implications

This is why volume strategy matters. Named volumes live deep in Docker's directory structure. To back them up, you need to either:
- Stop the container and copy from `/var/lib/docker/volumes/`
- Use `docker run --volumes-from` to mount the volume in a temporary container
- Use a Docker-aware backup tool

Bind mounts are just directories on your filesystem. `rsync`, `restic`, `borgbackup` — any standard backup tool can handle them without knowing Docker exists.

> **Note:** Whichever you choose, know how to back up and restore your volumes before you have data worth losing. Test it. Actually restore from a backup once. "I have backups" means nothing until you've proven you can restore from them.

---

## Environment Variables

### .env Files in Compose

Docker Compose automatically reads a `.env` file in the same directory as the compose file. Variables defined there are available for interpolation in the compose file:

```bash
# .env
POSTGRES_PASSWORD=supersecretpassword
POSTGRES_DB=nextcloud
TZ=America/Chicago
```

```yaml
# docker-compose.yml
services:
  postgres:
    environment:
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
      TZ: ${TZ}
```

### What Goes in .env

- Passwords and API keys
- Paths specific to your machine
- Configuration that differs between your dev and prod environments
- Timezone, PUID/PGID, and other per-host settings

### What Stays in the Compose File

- Image names and tags
- Port mappings (unless they differ between environments)
- Volume mount paths (the container side — the host side may go in .env)
- Network attachments
- Restart policies
- Resource limits

The principle: **if it's a secret or machine-specific, it goes in .env. If it's structural, it stays in compose.**

> **Warning:** Never commit `.env` files to git. Never. Add `.env` to your `.gitignore` and verify with `git status` before every commit. A leaked database password in git history is there forever, even after you delete the file.

---

## Restart Policies

Docker containers can be configured to restart automatically. The two policies you'll use:

### `unless-stopped`

```yaml
services:
  pihole:
    restart: unless-stopped
```

The container restarts automatically if it crashes or if Docker restarts (system reboot). It does *not* restart if you explicitly stop it with `docker stop` or `docker compose stop`.

This is the right default for most homelab services. If a service crashes, you want it to come back. If you deliberately stop it for maintenance, you don't want it sneaking back.

### `always`

```yaml
services:
  critical-service:
    restart: always
```

The container always restarts, even if you manually stop it (it'll restart when Docker daemon restarts). Use this only for truly critical services where accidental stops are dangerous — and honestly, even then, `unless-stopped` is usually fine.

### The Trade-Off

`unless-stopped` is better for debugging. If a container is crash-looping, you can stop it, investigate, and it stays stopped. With `always`, a crash-looping container keeps restarting, potentially filling logs and consuming resources.

**Recommendation:** Use `unless-stopped` for everything. Use `always` for nothing unless you have a specific reason.

### No Restart Policy

If you omit the restart policy, the container doesn't restart. This is fine for one-off tasks, testing, and dev containers you don't want persisting.

---

## Resource Limits

On a shared machine (and even on a dedicated one), resource limits prevent a misbehaving container from taking down everything else.

### Memory Limits

```yaml
services:
  nextcloud:
    deploy:
      resources:
        limits:
          memory: 1G
        reservations:
          memory: 256M
```

- **limits.memory:** Hard cap. If the container exceeds this, it gets OOM-killed. Set this for every container on shared hardware.
- **reservations.memory:** Soft reservation. Docker uses this for scheduling decisions. Less critical on a single host but good practice.

### CPU Limits

```yaml
services:
  sonarr:
    deploy:
      resources:
        limits:
          cpus: "2.0"
```

This limits the container to 2 CPU cores. Useful for preventing a CPU-intensive process (media transcoding, database imports) from starving other services.

### Practical Guidance

You don't need to set precise limits on day one. But when you notice a container consuming unexpected resources, add a limit. Common offenders:

- **Databases** under heavy load can consume all available memory
- **Media transcoders** will happily use every CPU core
- **Monitoring tools** (especially Prometheus with long retention) can grow memory usage over time
- **AI/ML workloads** on the cortex box — these deserve generous limits but still limits

A good starting approach:

```yaml
# Lightweight services (DNS, small web apps)
deploy:
  resources:
    limits:
      memory: 256M
      cpus: "0.5"

# Medium services (Nextcloud, Sonarr, Radarr)
deploy:
  resources:
    limits:
      memory: 1G
      cpus: "2.0"

# Heavy services (databases, Jellyfin with transcoding)
deploy:
  resources:
    limits:
      memory: 4G
      cpus: "4.0"
```

> **Note:** The `deploy` key technically belongs to Docker Swarm mode, but as of Compose V2, `deploy.resources.limits` works in standard Compose as well. If your version doesn't support it, use the older `mem_limit` and `cpus` top-level keys.

---

## Labels

Labels are key-value pairs attached to containers. They're metadata — they don't affect container behavior directly but are used by other tools.

### Reverse Proxy Configuration

Traefik reads labels to configure routing. This is one of Traefik's killer features — instead of a central config file, each service declares its own routing:

```yaml
services:
  jellyfin:
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.jellyfin.rule=Host(`jellyfin.example.com`)"
      - "traefik.http.routers.jellyfin.tls.certresolver=letsencrypt"
      - "traefik.http.services.jellyfin.loadbalancer.server.port=8096"
```

### Organization and Filtering

You can add custom labels for your own purposes:

```yaml
services:
  jellyfin:
    labels:
      - "homelab.stack=media"
      - "homelab.backup=true"
      - "homelab.public=true"
```

Then filter with:

```bash
docker ps --filter "label=homelab.backup=true"
```

This is useful for backup scripts that need to know which containers have data worth backing up, or monitoring rules that should only alert on production services.

---

## The Base Path Convention

Pick a single base directory for your homelab and use it everywhere. Don't scatter compose files across your home directory, `/srv`, `/opt`, and `/var`.

**Recommendation:** `/opt/homelab/`

```
/opt/homelab/
  stacks/
    networking/
    dns/
    monitoring/
    media/
    cloud/
  data/
    jellyfin/
    nextcloud/
    postgres/
  backups/
    local/
  scripts/
```

- `stacks/` — Your compose files, .env files, and stack configs. This directory is a git repo.
- `data/` — Bind-mounted application data. Not in git (it's in backups).
- `backups/` — Local backup staging area before offsite sync.
- `scripts/` — Utility scripts for maintenance tasks.

### Why This Matters

When everything lives under one path:
- Backups are simple: back up `/opt/homelab/data/`
- Permissions are simple: one ownership scheme for the whole tree
- Navigation is simple: you always know where to look
- The burn-it-down test is simpler: clone the repo to `/opt/homelab/stacks/`, restore data to `/opt/homelab/data/`, done

### Git for Stacks

Your `stacks/` directory should be a git repo. This gives you:
- History of every configuration change
- The ability to diff "what changed since this stopped working"
- A remote copy of your infrastructure definition (push to a private GitHub/Gitea repo)
- The foundation of the burn-it-down test

```bash
cd /opt/homelab/stacks
git init
echo ".env" >> .gitignore
echo "!.env.example" >> .gitignore
git add .
git commit -m "Initial homelab stack configuration"
```

---

## Docker Logging

Docker's default logging driver is `json-file`, which writes container logs to JSON files on disk. Without configuration, these files grow without limit until your disk is full. This is not hypothetical — it will happen, and it will happen at the worst possible time.

### Configure Log Rotation

Set this globally in `/etc/docker/daemon.json`:

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
```

This limits each container to 3 log files of 10MB each — 30MB max per container. For a homelab with 20 containers, that's 600MB max. Manageable.

After changing `daemon.json`, restart Docker:

```bash
sudo systemctl restart docker
```

> **Warning:** This only affects newly created containers. Existing containers keep their original logging configuration. After setting this up, recreate your containers (`docker compose up -d --force-recreate`) to apply the new settings.

### Per-Container Logging Overrides

Some containers are chattier than others. You can override logging per container:

```yaml
services:
  noisy-service:
    logging:
      driver: json-file
      options:
        max-size: "5m"
        max-file: "2"

  important-service:
    logging:
      driver: json-file
      options:
        max-size: "50m"
        max-file: "5"
```

### Viewing Logs

```bash
# Follow logs for a specific service
docker compose logs -f jellyfin

# Last 100 lines
docker compose logs --tail 100 jellyfin

# Logs since a specific time
docker compose logs --since "2024-01-15T10:00:00" jellyfin

# All services in a stack
docker compose logs -f
```

Don't get fancy with centralized logging (Loki, ELK) until you've outgrown `docker compose logs`. For most homelabs, direct log access is sufficient.

---

## Health Checks

Health checks let Docker monitor whether a container is actually working, not just running. A container can be "running" (the process hasn't exited) while being completely non-functional (deadlocked, out of connections, unresponsive).

### Writing Health Checks

```yaml
services:
  postgres:
    image: postgres:16
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s

  nextcloud:
    image: nextcloud:latest
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost/status.php"]
      interval: 60s
      timeout: 10s
      retries: 3
      start_period: 120s
    depends_on:
      postgres:
        condition: service_healthy
```

### Health Check Parameters

- **test:** The command to run. Exit code 0 = healthy, anything else = unhealthy.
- **interval:** How often to run the check. 30-60 seconds is reasonable for most services.
- **timeout:** How long to wait for the check to complete. If the service is healthy, this should be fast.
- **retries:** How many consecutive failures before marking unhealthy. 3 is a good default — avoids false positives from transient issues.
- **start_period:** Grace period after container start during which failed health checks don't count. Set this long enough for the service to initialize. Databases and Java applications need longer start periods.

### Common Health Check Commands

```yaml
# Web services
test: ["CMD", "curl", "-f", "http://localhost:PORT/health"]

# PostgreSQL
test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER}"]

# MariaDB/MySQL
test: ["CMD", "healthcheck.sh", "--connect", "--innodb_initialized"]

# Redis
test: ["CMD", "redis-cli", "ping"]

# Generic TCP port check
test: ["CMD-SHELL", "nc -z localhost PORT || exit 1"]

# DNS resolver
test: ["CMD-SHELL", "nslookup example.com 127.0.0.1 || exit 1"]
```

### Why Health Checks Matter

**Dependency ordering.** With `depends_on: condition: service_healthy`, Docker Compose waits for a dependency to be healthy before starting the dependent service. Without health checks, `depends_on` only waits for the container to start, not for the application inside to be ready. This is the difference between Nextcloud starting before PostgreSQL is ready (crash, restart loop) and Nextcloud waiting until PostgreSQL is actually accepting connections.

**Monitoring integration.** Monitoring tools can scrape Docker's health status. A container marked unhealthy triggers alerts before users notice the problem.

**Restart policies.** Combined with `restart: unless-stopped`, unhealthy containers get automatically restarted. The container stays "running" (Docker doesn't restart it just for being unhealthy by default), but your monitoring can alert you, and you can configure additional automation around health status if needed.

> **Note:** Docker does not automatically restart unhealthy containers. The health check is informational. If you want automatic restarts on unhealthy status, you need an external tool like `autoheal` or `docker-autoheal` — or just set up alerts and handle it manually. For a homelab, manual intervention is often preferable to automatic restarts that might mask underlying problems.

---

## Putting It All Together

Here's a complete example of a well-structured stack following all the conventions in this chapter:

```
/opt/homelab/stacks/media/
  docker-compose.yml
  .env
  .env.example
```

```bash
# .env.example
TZ=America/Chicago
PUID=1000
PGID=1000
MEDIA_PATH=/opt/homelab/data/media
CONFIG_PATH=/opt/homelab/data/media-configs
JELLYFIN_HOST=jellyfin.example.com
```

```yaml
# docker-compose.yml
networks:
  proxy:
    name: proxy
    external: true
  media:
    name: media-internal

services:
  jellyfin:
    image: jellyfin/jellyfin:latest
    container_name: media-jellyfin
    restart: unless-stopped
    networks:
      - proxy
      - media
    environment:
      TZ: ${TZ}
    volumes:
      - ${CONFIG_PATH}/jellyfin:/config
      - ${MEDIA_PATH}/movies:/media/movies:ro
      - ${MEDIA_PATH}/tv:/media/tv:ro
      - ${MEDIA_PATH}/music:/media/music:ro
    deploy:
      resources:
        limits:
          memory: 4G
          cpus: "4.0"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8096/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.jellyfin.rule=Host(`${JELLYFIN_HOST}`)"
      - "traefik.http.routers.jellyfin.tls.certresolver=letsencrypt"
      - "traefik.http.services.jellyfin.loadbalancer.server.port=8096"
      - "homelab.stack=media"
      - "homelab.backup=true"
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"

  sonarr:
    image: linuxserver/sonarr:latest
    container_name: media-sonarr
    restart: unless-stopped
    networks:
      - proxy
      - media
    environment:
      TZ: ${TZ}
      PUID: ${PUID}
      PGID: ${PGID}
    volumes:
      - ${CONFIG_PATH}/sonarr:/config
      - ${MEDIA_PATH}:/media
    deploy:
      resources:
        limits:
          memory: 1G
          cpus: "2.0"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8989/ping"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.sonarr.rule=Host(`sonarr.example.com`)"
      - "traefik.http.routers.sonarr.tls.certresolver=letsencrypt"
      - "traefik.http.services.sonarr.loadbalancer.server.port=8989"
      - "homelab.stack=media"
      - "homelab.backup=true"
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
```

This compose file demonstrates every convention from this chapter:
- Explicit container names with stack prefix
- Named networks (external proxy, internal media)
- Bind mounts with paths from `.env`
- Environment variables from `.env`
- `unless-stopped` restart policy
- Resource limits
- Health checks
- Traefik labels for reverse proxy configuration
- Custom labels for organization
- Log rotation

It's longer than the minimum. It's more verbose than strictly necessary. But six months from now, you (or someone else) can read this file and understand exactly what's running, how it's configured, and why.

That's the point.

---

## Quick Reference

| Convention | Recommendation |
|-----------|---------------|
| Base path | `/opt/homelab/` |
| Stack structure | One directory per logical group |
| Secrets | `.env` file, never committed to git |
| Container names | `stackname-servicename` |
| Network names | Explicit `name:` property |
| Shared proxy network | External `proxy` network |
| Restart policy | `unless-stopped` for everything |
| Logging | `json-file` with `max-size: 10m`, `max-file: 3` |
| Resource limits | Set for every container on shared hardware |
| Health checks | Define for every service with a testable endpoint |
| Version control | `stacks/` directory is a git repo |
| Volumes | Bind mounts for data you need to access/backup |
