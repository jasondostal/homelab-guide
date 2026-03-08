# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

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
