# Chapter 06 — Backups with Restic

## The Rule

3-2-1. Three copies of your data. Two different storage media. One copy off-site.

This isn't a suggestion. It's the minimum viable backup strategy. Anything less and you're rolling dice with your data.

- **Three copies:** The original data, a local backup, and a remote backup.
- **Two media types:** Your server's SSD and a cloud storage provider (or a USB drive, or a NAS, or a friend's server). The point is that a single hardware failure mode can't wipe both copies.
- **One off-site:** If your house floods, catches fire, or gets robbed, the backup that's in the same building is worthless. Off-site means geographically separated.

Most homelabbers know this rule. Most homelabbers also don't follow it. They have one backup to an external drive sitting next to the server. That covers "my SSD died" but not "my house had a water leak" or "there was a power surge that fried everything plugged in."

Do it right. It's cheap and it's not hard. That's what this chapter is for.

## Why Restic

There are plenty of backup tools. BorgBackup, Duplicati, Kopia, rsync, plain old `tar`. Restic is the recommendation here, and here's why:

### Encrypted at Rest by Default

Every Restic repository is encrypted. You don't have to remember to enable it, configure it, or think about it. Your backups are encrypted with a password you choose during `restic init`. Without that password, the data is unreadable.

This matters because your off-site backup is on someone else's computer. That's what "the cloud" means. Backblaze, Amazon, your buddy's NAS — you don't control the physical hardware. Encryption means it doesn't matter. Even if the storage provider is compromised, your data is safe.

### Deduplication

Restic deduplicates at the block level. If you back up a 10GB volume and only 50MB changed since yesterday, Restic only uploads 50MB (approximately — it's block-level, not file-level, so the actual numbers depend on what changed and where).

This makes daily backups practical even with a slow upload connection. The first backup is large. Every subsequent backup is incremental in storage cost, even though each snapshot is a complete, restorable point-in-time copy.

### Multiple Backends

Restic natively supports:

- **Local filesystem** — for local backups to an attached drive
- **SFTP** — for backing up to any server you have SSH access to
- **Amazon S3** — and any S3-compatible storage (Backblaze B2, Wasabi, MinIO)
- **Backblaze B2** — native support, not just through the S3 compatibility layer
- **Azure Blob Storage, Google Cloud Storage** — if you're in those ecosystems
- **rclone** — as a backend, giving you access to dozens of additional storage providers

### Single Binary, No Server Component

Restic is one binary. No daemon, no server process, no database. It runs when you tell it to run, does its thing, and exits. This means there's nothing to maintain between backups — no background process consuming resources, no database that can corrupt, no service that can crash.

Compare this to Duplicati (web UI, background service, SQLite database that occasionally corrupts) or enterprise tools that require a backup server. Restic is refreshingly simple.

### Fast and Well-Maintained

Restic is written in Go, which means it's fast, cross-platform, and produces static binaries. The project is actively maintained with regular releases. The community is large and helpful. Documentation is excellent.

## What to Back Up

Not everything on your server needs backing up. Be deliberate about what goes into your backup set. More data means slower backups, higher storage costs, and longer restores.

### Back Up These Things

**Docker volumes — your actual data.** This is the stuff that matters. Your Gitea repositories, your Vaultwarden vault, your Nextcloud files, your Jellyfin metadata and configuration. If you lost these, you'd lose real data that can't be recreated.

```bash
# Typical volume locations
/opt/docker/gitea/data
/opt/docker/vaultwarden/data
/opt/docker/nextcloud/data
/opt/docker/jellyfin/config
```

**Compose files and stack configurations.** These are your infrastructure-as-code. They define how your services are deployed, what environment variables they use, what networks they're on, what volumes they mount. Losing these means rebuilding your entire stack from memory.

```bash
/opt/docker/docker-compose.yml
/opt/docker/*/docker-compose.yml
```

**`.env.example` files.** Template files that show what environment variables each service needs, without containing the actual secrets. These are documentation for future-you.

> **Warning:** Do NOT back up `.env` files to a remote target. They contain passwords, API keys, and other secrets. Even with Restic's encryption, practicing defense in depth means not sending secrets to third-party storage if you can avoid it. Keep your `.env` files in a password manager or a separate, high-security backup process.

**Cron jobs and scripts.** Your backup scripts, monitoring scripts, maintenance scripts. All the glue that holds your homelab together.

```bash
/etc/cron.d/homelab
/opt/scripts/
```

**System configs you've customized.** SSH config, firewall rules, Docker daemon config, sysctl tweaks. Anything you've changed from defaults that you'd need to redo on a fresh install.

```bash
/etc/docker/daemon.json
/etc/ssh/sshd_config
/etc/sysctl.d/
```

### Don't Back Up These Things

**Container images.** They're pulled from registries. `docker compose pull` gets them back. Backing them up wastes storage and bandwidth.

**Build caches, temporary files, logs.** Anything that's regenerated automatically. Your Docker log files (assuming you have rotation configured) don't need off-site backup.

**Anything easily reproducible.** If you can get it back with a single command or a download, don't back it up. The goal is to back up things that are *yours* — data you created, configuration you wrote, state that accumulated over time.

**Large media libraries** (sometimes). If you have 10TB of media files that exist elsewhere (ripped from your own discs, available from other sources), think carefully about whether they need off-site backup. A local backup to an attached drive? Sure. Uploading 10TB to B2 and paying monthly storage fees? Probably not worth it. Back up the metadata and configuration instead — those are what take time to rebuild.

## Repository Setup

### Choosing a Backend

**Backblaze B2** is the recommendation for most homelabbers. $6/TB/month for storage, $0.01/GB for downloads. For a homelab backup set of 50-100GB, you're looking at under a dollar a month. It's reliable, well-documented, and Restic supports it natively.

**S3-compatible storage** (AWS S3, Wasabi, MinIO) works if you're already in that ecosystem. Wasabi is interesting — no egress fees, flat $7/TB/month, but has a 90-day minimum storage duration policy.

**SFTP to a friend's server** is the homelab equivalent of off-site backup. You back up to their server, they back up to yours. Both encrypted, of course. Zero cost if you have a willing friend with spare disk space. The risk is availability — if your friend's server goes down when you need to restore, that's a problem.

### Initializing the Repository

```bash
# For Backblaze B2
export B2_ACCOUNT_ID="your-account-id"
export B2_ACCOUNT_KEY="your-account-key"
restic -r b2:your-bucket-name:homelab init

# For S3
export AWS_ACCESS_KEY_ID="your-key"
export AWS_SECRET_ACCESS_KEY="your-secret"
restic -r s3:s3.amazonaws.com/your-bucket init

# For SFTP
restic -r sftp:user@host:/path/to/repo init

# For local filesystem
restic -r /mnt/backup-drive/restic-repo init
```

Restic will prompt you for a repository password. This password encrypts your entire repository. Choose a strong one and store it safely (more on this later — it's critical enough to get its own section).

### Multiple Repositories

Consider separate repositories for different retention needs:

- **Critical data** (Vaultwarden, Gitea) — longer retention, more frequent backups
- **Bulk data** (Nextcloud files, configs) — shorter retention, daily backups
- **System configs** — long retention, infrequent backups

Or keep it simple: one repository, one backup script, one retention policy. Complexity is the enemy of reliability. A simple backup that runs every day is better than an elaborate system that breaks and nobody notices for two weeks.

## Backup Scripts

Here's a practical backup script that handles the full lifecycle:

```bash
#!/bin/bash
set -euo pipefail

# ============================================================
# Configuration
# ============================================================
export B2_ACCOUNT_ID="your-account-id"
export B2_ACCOUNT_KEY="your-account-key"
export RESTIC_REPOSITORY="b2:your-bucket:homelab"
export RESTIC_PASSWORD_FILE="/root/.restic-password"

HEALTHCHECK_URL="https://hc-ping.com/your-uuid-here"
BACKUP_PATHS=(
    "/opt/docker"
    "/opt/scripts"
    "/etc/docker/daemon.json"
    "/etc/cron.d/homelab"
)
EXCLUDE_PATTERNS=(
    "*.log"
    "*.tmp"
    "**/cache/**"
    "**/.env"
    "**/node_modules/**"
)

# ============================================================
# Pre-backup: stop containers that need filesystem consistency
# ============================================================
echo "$(date): Stopping database containers for consistent backup..."
docker stop gitea-db 2>/dev/null || true
docker stop nextcloud-db 2>/dev/null || true

# ============================================================
# Run the backup
# ============================================================
echo "$(date): Starting backup..."
EXCLUDE_FLAGS=""
for pattern in "${EXCLUDE_PATTERNS[@]}"; do
    EXCLUDE_FLAGS="$EXCLUDE_FLAGS --exclude $pattern"
done

restic backup \
    --tag homelab \
    --tag "$(date +%A)" \
    $EXCLUDE_FLAGS \
    "${BACKUP_PATHS[@]}"

backup_exit=$?

# ============================================================
# Post-backup: restart containers
# ============================================================
echo "$(date): Restarting database containers..."
docker start gitea-db 2>/dev/null || true
docker start nextcloud-db 2>/dev/null || true

# ============================================================
# Apply retention policy
# ============================================================
echo "$(date): Applying retention policy..."
restic forget \
    --keep-daily 7 \
    --keep-weekly 4 \
    --keep-monthly 6 \
    --prune

# ============================================================
# Verify repository integrity (weekly — this is slow)
# ============================================================
if [ "$(date +%u)" -eq 7 ]; then
    echo "$(date): Running weekly integrity check..."
    restic check
fi

# ============================================================
# Report status
# ============================================================
if [ $backup_exit -eq 0 ]; then
    echo "$(date): Backup completed successfully."
    curl -fsS -m 10 --retry 5 "$HEALTHCHECK_URL"
else
    echo "$(date): Backup FAILED with exit code $backup_exit"
    curl -fsS -m 10 --retry 5 "$HEALTHCHECK_URL/fail"
fi
```

Let's break down the important parts.

### Pre-Backup Hooks: Stop What Needs Stopping

Databases are the main concern. If you back up a database's data files while it's actively writing, you might get a corrupted snapshot. The data files are internally consistent only from the database's perspective — at the filesystem level, you might capture a half-written transaction.

The safe approach: stop the container, back up, start the container. The downtime is usually seconds to minutes. For a homelab, that's fine.

```bash
docker stop gitea-db 2>/dev/null || true
```

The `2>/dev/null || true` pattern means "try to stop this container, and if it's not running or doesn't exist, continue anyway." Your backup script should never fail because a container was already stopped.

An alternative for databases that support it: use `pg_dump` or `mysqldump` to create a logical backup before the Restic run. This avoids any downtime but adds complexity and another set of files to manage.

> **Note:** Not everything needs stopping. Services that store data in files (Gitea repositories, Nextcloud user files, config files) are generally safe to back up live. It's specifically database engines with write-ahead logs and multi-file transaction state that need quiescing.

### Tags

```bash
restic backup --tag homelab --tag "$(date +%A)"
```

Tags help you identify and filter snapshots later. The day-of-week tag makes it easy to find "last Tuesday's backup" without doing date math. The `homelab` tag distinguishes these snapshots from any other backups in the same repository.

### Retention Policy

```bash
restic forget \
    --keep-daily 7 \
    --keep-weekly 4 \
    --keep-monthly 6 \
    --prune
```

This keeps:

- The last 7 daily snapshots (one week of daily recovery points)
- The last 4 weekly snapshots (one month of weekly recovery points)
- The last 6 monthly snapshots (six months of monthly recovery points)

Everything older gets pruned. The `--prune` flag actually deletes the unreferenced data — without it, `forget` just removes the snapshot metadata but leaves the data blobs, which still consume storage.

This is a starting point. Adjust based on:

- **How much data changes daily** — high-churn data might warrant keeping fewer snapshots to control storage costs.
- **How far back you might need to restore** — if you might not notice a problem for months, keep monthly snapshots longer.
- **Your storage budget** — B2 is cheap, but 6 months of daily snapshots for 500GB of data isn't free.

### Pruning Considerations

`restic prune` is the most expensive operation in terms of time and bandwidth. It repacks data blobs, uploads repacked packs, and deletes old ones. On a large repository over a slow connection, this can take hours.

Options for managing prune cost:

- Don't prune every run. Prune weekly or monthly instead of daily. Snapshots still get forgotten (metadata removed), but the underlying data sticks around until the next prune.
- Use `--max-unused 5%` to leave up to 5% unused space in the repository rather than repacking everything. Trades storage cost for prune speed.

```bash
# Less aggressive pruning — faster, uses slightly more storage
restic forget \
    --keep-daily 7 \
    --keep-weekly 4 \
    --keep-monthly 6 \
    --prune --max-unused 5%
```

## Scheduling

Cron is the scheduler. Healthchecks.io is the monitor. Together, they ensure backups happen and you know about it when they don't.

```cron
# /etc/cron.d/homelab-backup
# Run backup daily at 3am
0 3 * * * root /opt/scripts/backup.sh >> /var/log/homelab-backup.log 2>&1
```

The log file gives you a local record for debugging. The Healthchecks.io ping gives you remote confirmation that it completed. If the cron entry breaks, or the cron daemon isn't running, or the server is down at 3am — Healthchecks.io will notice the missing ping and alert you.

> **Note:** Redirect both stdout and stderr to the log file (`2>&1`). If you only redirect stdout, errors disappear silently and you're left wondering why the backup "ran" but nothing is in the repository.

## Restore Testing

### This Is the Most Important Section in This Chapter

If you haven't restored from your backups, you don't have backups. You have hope. Hope is not a strategy.

Every backup system in the world is useless if you can't restore from it. Backups can be corrupted, encryption keys can be wrong, restore procedures can have undocumented steps, and your scripts might be backing up the wrong directories. The only way to know your backups work is to test them.

### Schedule Quarterly Restore Drills

Put it on your calendar. Every three months, do a full restore test. Not "I'll get to it eventually" — a calendar event with a reminder.

The drill:

```bash
# 1. List available snapshots
restic snapshots

# 2. Pick one (not the latest — test an older one too)
# 3. Restore to a temporary directory
restic restore latest --target /tmp/restore-test

# 4. Verify the data
diff -r /tmp/restore-test/opt/docker/gitea/data /opt/docker/gitea/data
ls -la /tmp/restore-test/opt/docker/
du -sh /tmp/restore-test/

# 5. Spot-check specific files
cat /tmp/restore-test/opt/docker/docker-compose.yml
# Does this look right? Is it complete?

# 6. Clean up
rm -rf /tmp/restore-test
```

What you're checking:

- Does the restore complete without errors?
- Are the files present and the right size?
- Can you read the data? (If your encryption is broken, you'll find out here, not during a real disaster.)
- Is the data current? (If your backup paths are wrong, you might be backing up an empty directory.)
- Is everything you need included? (Are there config files you forgot to add to the backup set?)

### Document the Restore Procedure

Future-you, at 2am, with your server dead and your heart rate elevated, should not be figuring out the restore procedure from first principles. Write it down.

The document should answer:

1. Where is the Restic repository? (Backend, bucket name, path)
2. Where is the repository password? (Password manager entry, physical location)
3. What environment variables are needed? (B2 credentials, etc.)
4. What's the exact restore command?
5. After restoring files, what else needs to happen? (Re-pull container images, restart services, re-apply permissions)
6. What order do things need to come up in? (Database before application, reverse proxy last)

Print this document. Put it somewhere you can find it when your server is down and you can't access your wiki or notes app that was running on that server.

### The House Fire Test

Ask yourself: if both my servers, my laptop, and my USB drives are gone — fire, flood, theft — can I rebuild?

What you need that probably isn't in your Restic backup:

- **The Restic password itself.** If it's only on the server or on your laptop, and both are gone, your encrypted backups are permanently inaccessible.
- **Cloud storage credentials.** B2 account ID and key, AWS credentials. Without these, you can't reach the repository.
- **2FA recovery codes.** For your Cloudflare account, your domain registrar, your cloud storage provider. Without these, you can't log in to retrieve credentials to access your backups.
- **Domain registrar access.** Your DNS settings need to be recreated. Can you log into your registrar?
- **SSH keys.** If you use SFTP as a backend, you need the SSH key.
- **The restore documentation.** See above.

All of these need to exist somewhere that survives the same disaster that takes out your servers. A password manager with cloud sync (Bitwarden, 1Password) is the practical answer. Some people print critical recovery info and keep it in a safe deposit box or with a trusted person. Both are valid.

## Encryption Key Management

Your Restic repository password is the single most critical piece of your backup strategy. Without it, your backups are random bytes. Restic uses AES-256 encryption. There is no backdoor, no recovery option, no "I forgot my password" flow. If the password is lost, the data is lost. Period.

### Where to Store the Password

**In a password manager with cloud sync.** Bitwarden, 1Password, KeePassXC with synced database. This is the primary storage location. It survives device loss and is accessible from any device.

**On paper in a secure location.** A safety deposit box, a fireproof safe, a sealed envelope with a trusted person. This is the disaster recovery option. If your password manager is somehow inaccessible (account locked, service down, 2FA device lost), this is your fallback.

**In the password file on the server** (`/root/.restic-password`). This is the operational copy that scripts use. It's protected by filesystem permissions (`chmod 600`). It's not a backup of the password — it's a convenience copy.

```bash
# Create the password file
echo "your-very-strong-repository-password" > /root/.restic-password
chmod 600 /root/.restic-password
```

### What NOT to Do

- Don't store the password only on the server being backed up. If the server dies, the password dies with it.
- Don't use a password derived from something guessable or reconstructable. Use a random, high-entropy password.
- Don't share the password over unencrypted channels. Don't email it, don't put it in a Slack message, don't commit it to a git repo.
- Don't use the same password for multiple repositories unless you want a single compromise to expose all your backups.

### Key Rotation

Restic supports changing the repository password with `restic key passwd`. Do this if you suspect the password has been compromised. But note: this doesn't re-encrypt existing data with the new key. It changes the key that encrypts the master key. Existing data remains accessible. This is by design — re-encrypting a multi-terabyte repository would be impractical.

```bash
# Change the repository password
restic -r b2:your-bucket:homelab key passwd
# You'll be prompted for the current password, then the new one
```

After changing the password, update it everywhere: the password file on the server, your password manager, your printed copy.

## A Complete Backup Strategy

Putting it all together for a practical homelab:

1. **Restic repository on Backblaze B2** — encrypted, deduplicated, off-site.
2. **(Optional) Local Restic repository on an attached drive** — fast restores, second copy.
3. **Daily backup script** running at 3am via cron.
4. **Healthchecks.io integration** — alerts if the backup doesn't complete.
5. **Retention: 7 daily, 4 weekly, 6 monthly** — six months of recovery points.
6. **Quarterly restore drills** — calendared, non-negotiable.
7. **Repository password** in password manager + printed in secure location.
8. **Restore documentation** written, printed, accessible offline.

Total cost: under $1/month for B2 storage for a typical homelab. The time investment is an afternoon to set up and an hour per quarter for restore testing.

That's it. Not glamorous. Not complex. But when your SSD fails at 11pm on a Saturday — and it will, eventually — you'll have your entire homelab back up and running from a fresh drive in hours, not days. That's what backups are for.

> **Warning:** The most common backup failure mode isn't technical. It's human. You set it up, it runs for months, something changes (a new service, a moved directory, a changed credential), the backup silently starts failing, and you don't notice for weeks because you didn't have monitoring. Healthchecks.io plus quarterly restore testing closes this gap. Do both.
