# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## [0.4.2] - 2026-03-09

### Added
- Chapter 12: Outbound Email section — AWS SES as the recommended transactional email service, comparison table of homelab-friendly alternatives (Resend, Brevo, Mailgun, SMTP2GO, Mailpit), anti-pattern callout for self-hosted SMTP
- Chapter 12: SES added to "What's Actually Useful" service list and always-free tier breakdown

## [0.4.1] - 2026-03-08

### Added
- Screenshots from a live homelab: Homepage dashboard (README + Ch11), SWAG dashboard (Ch04), Cairn MCP memory UI (Ch07)
- images/ directory for guide assets

## [0.4.0] - 2026-03-08

### Added
- Chapter 12: AWS Free Tier — broken out from Ch11 into a dedicated chapter with expanded content (practical project examples, always-free tier breakdown, S3/Lambda/CloudWatch homelab integration patterns)
- Chapter 05: What's Up Docker (WUD) section — container update awareness without auto-updating, WUD vs Watchtower philosophy, setup example
- Chapter 11: Jellyfin ecosystem — Jellyseerr (media request management) and jellyfin-accounts-go (invite-based user management) as companion tools that make Jellyfin a polished multi-user platform

### Changed
- Chapter 11: Removed AWS Free Tier section (moved to dedicated Ch12)

## [0.3.1] - 2026-03-08

### Changed
- Chapter 11: Ad blocking — added author's note on running Pi-hole despite recommending AdGuard Home for new setups (authenticity over dogma)
- Chapter 11: Home Assistant — added "The Iron Rule" section: everything must work without HA. Shelly relays behind physical switches as the reference pattern. HA is the brain, not the spine.
- Chapter 11: Homepage dashboard — rewrote "Why Bother" as "Blinkenlights" — the aquarium metaphor, passive monitoring value, containers-are-cattle-but-you-still-love-them energy
- Chapter 04: Added 418 teapot response for geo-blocked requests

## [0.3.0] - 2026-03-08

### Added
- Chapter 11: "Serving 418" section — teapot smoke test for your edge stack, with nginx config
- Chapter 11: "Your Home as a Platform" section — Shelly relays (power monitoring, remote reboot, garage doors), WLED (addressable LEDs, permanent holiday lighting, ambient notifications), custom ESP32 with ESPHome (temp sensors, irrigation, RFID, air quality), BirdNET-Pi (neural network bird identification), and the platform mindset
- Chapter 11: "Experimenting on AWS Free Tier" section — practical free tier services for homelab use (S3 as backup target, Lambda for webhooks, CloudWatch for external monitoring, Bedrock for AI, and more), billing safety, and the learning value argument
- This CHANGELOG

## [0.2.0] - 2026-03-08

### Added
- Chapter 10: Domains, Certificates, Dynamic DNS & Remote Access
- Chapter 11: The Fun Stuff — ad blocking, Jellyfin, Home Assistant, Vaultwarden, file sync, dashboards, bookmarks, notes
- Stack: `stacks/apps/` — Jellyfin, Vaultwarden, Homepage dashboard
- Stack: `stacks/dns/` — AdGuard Home
- Stack: `stacks/homeassistant/` — Home Assistant with host networking and USB passthrough
- Resources & References section in README

## [0.1.0] - 2026-03-08

### Added
- Initial release: README, guiding principles, "safety enables speed" thesis
- Chapters 00-09: Philosophy, Hardware, Network Segmentation, Docker Foundations, Reverse Proxy, Monitoring, Backups, AI Dev Stack, Security Hardening, Day Two Ops
- Stacks: core, swag, monitoring, data, ai-cortex, backups
- Scripts: backup.sh, restore-test.sh, healthcheck-ping.sh
- .gitignore
