# Chapter 12 — Experimenting on AWS Free Tier

## Your Homelab's Cloud Extension

This might seem contradictory — a self-hosting guide telling you to use AWS. But the AWS Free Tier is too useful to ignore, especially as a learning tool and as a complement (not replacement) for your homelab.

The Free Tier gives you 12 months of access to a staggering number of services at zero cost. Most homelab guides ignore this entirely. That's a mistake. Treat AWS Free Tier as your lab's cloud campus — a place to experiment with things that don't make sense to run at home.

This isn't about migrating your homelab to the cloud. It's about using free cloud resources to extend what your homelab can do and to learn skills that make you a better engineer — at home and at work.

---

## What's Actually Useful on Free Tier

This isn't just about AI/Bedrock. The breadth is the point:

### Compute & Hosting

- **EC2** (750 hrs/month t2.micro or t3.micro) — a small cloud VM. Use it as a VPS relay if you're behind CGNAT, a remote WireGuard endpoint, or a place to test deployments before running them at home.
- **Lambda** (1M requests/month, 400,000 GB-seconds) — serverless functions. Great for webhooks, API integrations, and small automations that don't justify a running container.
- **Lightsail** (first 3 months free) — simpler VPS. Good for a public-facing landing page or status page.

### Storage

- **S3** (5GB, 20,000 GETs, 2,000 PUTs) — object storage. Use it as a restic backend for your off-prem backups, or host a static site.
- **DynamoDB** (25GB, 25 read/write capacity units) — NoSQL database. Experiment with serverless data patterns.

### AI & Machine Learning

- **Bedrock** — managed access to Claude, Llama, and other foundation models. Compare API-based inference to your local Ollama setup.
- **SageMaker** (first 2 months, 250 hours of t3.medium notebook) — ML notebooks. Good for experimenting with model fine-tuning or data processing.
- **Rekognition** (5,000 images/month) — image analysis. Compare to self-hosted alternatives.
- **Transcribe** (60 minutes/month for 12 months) — speech to text.
- **Comprehend** — NLP, sentiment analysis, entity extraction.

### Networking

- **CloudFront** (1TB transfer out, 10M requests) — CDN. Put it in front of a static site or use it as a global cache for your homelab's public-facing services.
- **Route 53** — hosted DNS zones. Alternative to Cloudflare if you want to manage DNS as code with Terraform.
- **API Gateway** (1M API calls/month) — managed API endpoints. Wire up Lambda functions behind a proper API.

### Developer Tools

- **CodeBuild** (100 build minutes/month) — CI/CD. Build your container images in the cloud instead of locally.
- **CodeCommit** (5 active users) — git hosting. Might prefer GitHub, but it exists.
- **SNS** (1M publishes) + **SQS** (1M requests) — messaging and queuing. Experiment with event-driven architectures.

### Email

- **SES** (62,000 emails/month from EC2, 3,000 otherwise) — transactional email. Point your homelab services at SES's SMTP endpoint and stop worrying about deliverability. Covered in detail below.

### Monitoring & Observability

- **CloudWatch** (10 custom metrics, 10 alarms) — use it as an external monitoring layer for your homelab. Alert when your home IP changes, when health checks fail from outside your network, when cert expiry approaches.

---

## Practical Projects: Connecting Cloud to Homelab

The free tier is most valuable when you connect it to your existing infrastructure. Here are concrete projects that bridge the gap:

### S3 as a Backup Target

Your restic backups from Chapter 06 can target S3 directly. The free tier's 5GB is small, but it's enough for your compose files, configs, and database dumps — the critical small stuff. For bulk media and volume data, Backblaze B2 is cheaper at scale.

```bash
# Initialize a restic repo on S3
export AWS_ACCESS_KEY_ID=your-key
export AWS_SECRET_ACCESS_KEY=your-secret
restic init -r s3:s3.amazonaws.com/your-bucket-name
```

### Lambda as a Homelab Webhook Processor

A Lambda function that receives webhooks (from GitHub, Stripe, or whatever) and forwards them to your homelab via Tailscale or a secure tunnel. Your homelab doesn't need to expose any ports — the Lambda is the public-facing endpoint.

### CloudWatch as External Monitoring

Your Healthchecks.io setup (Chapter 05) monitors from the inside. CloudWatch can monitor from the outside:

- A scheduled Lambda checks if your public services respond and pushes a custom metric
- A CloudWatch alarm fires when the metric goes unhealthy
- SNS sends you an email or SMS

This catches problems that internal monitoring misses — ISP outages, DNS failures, external routing issues.

### EC2 as a CGNAT Escape Hatch

If your ISP puts you behind CGNAT (Chapter 10), a free-tier EC2 instance can serve as a WireGuard relay or Cloudflare Tunnel origin, giving you a public IP for pennies.

### API Gateway + Lambda for Public APIs

Want to expose a read-only API for one of your homelab projects without opening your network? API Gateway + Lambda gives you a managed, rate-limited, publicly accessible endpoint that fetches data from your homelab over a secure channel.

---

## The Smart Way to Use Free Tier

Don't try to learn all of AWS. Do this instead:

1. **Pick one project.** "I want to set up an S3 bucket as a restic backup target" or "I want a Lambda function that monitors my homelab's public IP and texts me if it changes."
2. **Build it.** Use the free tier. Stay within limits. Set up billing alerts (seriously — `$1 threshold` billing alarm, day one, no exceptions).
3. **Understand the bill.** Even on free tier, understand what would cost money at scale. AWS pricing is intentionally confusing. Knowing where the costs hide is a skill worth having.
4. **Connect it to your homelab.** S3 as a backup target. CloudWatch as external monitoring. Lambda as a webhook processor. API Gateway as a public endpoint that talks to your home network via Tailscale.

> **Warning:** AWS billing can surprise you. Set up a billing alarm at $1 on day one. Turn it on before you create anything else. Free tier limits are generous but specific — exceed them by one unit and you're paying on-demand rates. Use the AWS Free Tier Usage dashboard to track consumption. If you see charges appearing, stop and investigate immediately.

---

## What Doesn't Make Sense

- Don't run your homelab services on AWS. That defeats the purpose and gets expensive fast.
- Don't use AWS as your primary backup target if Backblaze B2 is cheaper (it usually is for storage-heavy workloads). B2 is $6/TB/month with free egress. S3 charges for egress.
- Don't build on AWS Free Tier services that you'll need to pay for after 12 months unless you've budgeted for it.

---

## Outbound Email — SES and Alternatives

Every homelab eventually needs to send email. Alerts, password resets, notifications, invite links — it all requires outbound SMTP. Running your own mail server is one of the few things in this guide I'll tell you flat out: **don't**. Deliverability is a nightmare. IP reputation management is a full-time job. You'll spend more time fighting spam blacklists than actually using your homelab.

Instead, use a transactional email service. Your homelab services point their SMTP settings at the service, and email just works.

### AWS SES — The One We Use

**[Amazon SES](https://aws.amazon.com/ses/)** (Simple Email Service) is the best deal going for homelabbers:

- **62,000 emails/month free** when sending from an application hosted on EC2 (or 3,000/month on the free tier otherwise). Way more than any homelab needs.
- Dead simple SMTP relay — point your services at SES's SMTP endpoint with IAM credentials and you're done.
- Rock-solid deliverability because you're sending from Amazon's infrastructure.
- Supports DKIM, SPF, and DMARC out of the box — your emails actually land in inboxes, not spam.

Setup is straightforward:

1. Verify your domain in SES (add a few DNS records).
2. Request production access (SES starts in sandbox mode — you have to ask to send to unverified addresses).
3. Create SMTP credentials (IAM user with SES send permissions).
4. Point your services at `email-smtp.<region>.amazonaws.com` on port 587 with those credentials.

Most homelab services (Authentik, Vaultwarden, Healthchecks.io, Gitea, etc.) have SMTP settings right in their config. Set it once, forget it.

### Other Homelab-Friendly Options

If you'd rather not tie email to AWS, these are solid alternatives:

| Service | Free Tier | Notes |
|---------|-----------|-------|
| **[Resend](https://resend.com)** | 3,000 emails/month, 100/day | Developer-focused, clean API, great docs. Built on AWS SES under the hood but with a much nicer interface. |
| **[Brevo](https://brevo.com)** (formerly Sendinblue) | 300 emails/day | Generous daily limit. SMTP relay works well for homelab use. |
| **[Mailgun](https://mailgun.com)** | 1,000 emails/month for 3 months | Industry standard for transactional email. Excellent deliverability. Gets expensive after the trial. |
| **[SMTP2GO](https://smtp2go.com)** | 1,000 emails/month | Straightforward SMTP relay, no nonsense. Good for set-and-forget homelab use. |
| **[Mailpit](https://mailpit.axllent.org)** | Self-hosted, unlimited | Email testing tool — catches all outbound email in a web UI. **Not for production sending.** Perfect for dev/testing when you want to verify your services send email without actually delivering it. |

> **My pick:** AWS SES if you're already in the AWS ecosystem (and if you're reading this chapter, you are). The free tier is absurdly generous for homelab volumes, and you're already managing IAM credentials anyway. Resend is the best alternative if you want something more developer-friendly with less AWS overhead.

### The Anti-Pattern: Self-Hosted SMTP

You'll see guides recommending Postfix, Maddy, or Mail-in-a-Box for self-hosted email. For *receiving* email or running a full mailbox server, those have their place (though I'd still argue against it for most people). For *sending* transactional email from homelab services, they're overkill and fragile. Your home IP will get blacklisted. Your emails will land in spam. You'll spend hours debugging deliverability issues that a managed service solves for free.

Use a service for sending. Save your energy for the parts of your homelab that are actually fun.

---

## The Always-Free Tier

Some AWS services have a permanent free tier that doesn't expire after 12 months. These are worth knowing about:

- **Lambda** — 1M requests/month and 400,000 GB-seconds, forever.
- **DynamoDB** — 25GB storage, 25 read/write capacity units, forever.
- **SNS** — 1M publishes/month, forever.
- **SQS** — 1M requests/month, forever.
- **CloudWatch** — 10 custom metrics, 10 alarms, forever.
- **API Gateway** — 1M REST API calls/month for the first 12 months, but HTTP APIs remain very cheap after.

- **SES** — 62,000 emails/month when sending from EC2, forever. Even without EC2, pricing is $0.10/1,000 emails — essentially free at homelab volumes.

The Lambda + DynamoDB + SES + API Gateway combination is permanently free for small-scale use. You can build lightweight serverless tools that complement your homelab indefinitely without spending a dollar.

---

## The Learning Value

The real value of Free Tier isn't the free compute. It's understanding how cloud infrastructure works — IAM roles, VPCs, security groups, managed services, infrastructure as code. This makes you a better engineer whether you're running a homelab or building production systems at work.

Your homelab teaches you ops from the bottom up — you own the hardware, the OS, the networking, the containers. AWS Free Tier teaches you ops from the top down — managed services, infrastructure as code, pay-per-use economics, IAM, and the shared responsibility model.

Both perspectives make the other more valuable. Understanding how S3 works makes you appreciate (and better configure) your local MinIO. Understanding how VPCs work makes your VLAN design sharper. Running Lambda makes you think differently about what deserves a container vs. what should be a function.

The combination of a homelab and cloud fluency is genuinely rare and genuinely valuable — at work, in interviews, and in your own projects.
