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

## The Always-Free Tier

Some AWS services have a permanent free tier that doesn't expire after 12 months. These are worth knowing about:

- **Lambda** — 1M requests/month and 400,000 GB-seconds, forever.
- **DynamoDB** — 25GB storage, 25 read/write capacity units, forever.
- **SNS** — 1M publishes/month, forever.
- **SQS** — 1M requests/month, forever.
- **CloudWatch** — 10 custom metrics, 10 alarms, forever.
- **API Gateway** — 1M REST API calls/month for the first 12 months, but HTTP APIs remain very cheap after.

The Lambda + DynamoDB + API Gateway combination is permanently free for small-scale use. You can build lightweight serverless tools that complement your homelab indefinitely without spending a dollar.

---

## The Learning Value

The real value of Free Tier isn't the free compute. It's understanding how cloud infrastructure works — IAM roles, VPCs, security groups, managed services, infrastructure as code. This makes you a better engineer whether you're running a homelab or building production systems at work.

Your homelab teaches you ops from the bottom up — you own the hardware, the OS, the networking, the containers. AWS Free Tier teaches you ops from the top down — managed services, infrastructure as code, pay-per-use economics, IAM, and the shared responsibility model.

Both perspectives make the other more valuable. Understanding how S3 works makes you appreciate (and better configure) your local MinIO. Understanding how VPCs work makes your VLAN design sharper. Running Lambda makes you think differently about what deserves a container vs. what should be a function.

The combination of a homelab and cloud fluency is genuinely rare and genuinely valuable — at work, in interviews, and in your own projects.
