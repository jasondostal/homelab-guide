# Chapter 07: The AI Dev Stack

You've got a homelab running services, storing data, backing things up. Now you want to bolt an AI development environment onto it. This chapter is about doing that without turning your entire infrastructure into a science experiment.

The core idea: **isolate your AI workloads on a dedicated box.** We call it the "cortex" — a machine whose sole purpose is running AI-related services. It's the box you're allowed to break.

---

## Why a Dedicated "Cortex" Box

AI workloads are different from everything else in your homelab. Here's why they deserve their own hardware:

**Unpredictable resource usage.** Running inference on a 13B parameter model can spike your memory from 2GB to 16GB in seconds. If that box is also running your reverse proxy, your Postgres database, and your media server, you've just taken down your entire stack because you wanted to ask a chatbot about Python decorators.

**Experimental by nature.** You're going to try new models, new tools, new frameworks. You're going to misconfigure things. You're going to run something that eats all available RAM and triggers the OOM killer. That's fine — on a dedicated box. On your production infrastructure, it's a 2am wake-up call.

**Rapid iteration.** AI tooling moves faster than almost anything else in software right now. The container you set up last month might be three versions behind. You want to be able to tear down and rebuild without worrying about side effects.

**GPU passthrough.** If you're running a GPU for inference, the NVIDIA container toolkit and GPU passthrough add complexity to your Docker setup. Keep that complexity contained.

> **The rule:** Your cortex box should be something you can `docker compose down && docker compose up -d` without thinking twice. If you're nervous about restarting it, you've coupled it too tightly to the rest of your stack.

---

## What Runs on the Cortex Box

### Local Inference: Ollama, vLLM, llama.cpp

The first question everyone asks: should I run models locally or just use cloud APIs?

The honest answer: **it depends on how much you're spending and what you're doing.**

#### The Cost Crossover Point

Cloud APIs charge per token. Local inference has fixed costs (hardware) and variable costs (electricity). Here's the rough math:

- **Under $20/month in API costs**: Stick with cloud. The convenience isn't worth the hardware investment.
- **$20-75/month**: You're in the gray zone. If you already have the hardware, local makes sense for some workloads. If you'd need to buy hardware, the payback period is long.
- **Over $75/month**: Start seriously evaluating local inference for your high-volume workloads — embeddings generation, batch processing, iterative coding tasks.

But cost isn't the only factor. **Privacy matters.** If you're feeding proprietary code, internal documents, or client data into an LLM, running locally means that data never leaves your network. That alone can justify the hardware cost.

**Latency matters too.** A local model on a decent GPU responds in milliseconds. Cloud APIs have network latency, rate limits, and occasional outages. For interactive coding workflows where you're making dozens of small requests per minute, local inference feels dramatically faster.

#### Model Size vs. VRAM: Be Realistic

This is where homelab enthusiasm crashes into physics. Here's what consumer GPUs can actually run:

| GPU VRAM | Max Model Size (Q4) | Max Model Size (Q8) | Max Model Size (FP16) |
|----------|---------------------|---------------------|----------------------|
| 8GB      | ~7B parameters      | ~4B parameters      | ~3B parameters       |
| 12GB     | ~13B parameters     | ~7B parameters      | ~5B parameters       |
| 16GB     | ~20B parameters     | ~13B parameters     | ~7B parameters       |
| 24GB     | ~33B parameters     | ~20B parameters     | ~13B parameters      |

These are rough estimates. The actual limits depend on context length, the specific model architecture, and how much VRAM is consumed by KV cache during inference.

**The uncomfortable truth:** A 7B quantized model is useful for many tasks — code completion, simple Q&A, structured output generation — but it's not going to match GPT-4 or Claude on complex reasoning. Know what you're getting. Local inference is a tool, not a replacement for frontier models.

#### Quantization Trade-offs

Quantization compresses model weights to use less memory at the cost of some quality:

- **Q4 (4-bit):** Smallest, fastest, most quality loss. Fine for code completion, structured output, simple chat. You'll notice degradation on nuanced reasoning tasks.
- **Q8 (8-bit):** Good middle ground. Most tasks are nearly indistinguishable from full precision. This is usually the sweet spot for local inference.
- **FP16 (full precision):** Maximum quality, maximum VRAM. Only worth it if you have the headroom and the task demands it (fine-tuning, evaluation benchmarks).

Start with Q8. Drop to Q4 only if you need to fit a larger model. Don't bother with FP16 unless you have a specific reason.

#### Running Ollama in Docker

Ollama is the easiest on-ramp for local inference:

```yaml
services:
  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    restart: unless-stopped
    ports:
      - "11434:11434"
    volumes:
      - ollama_models:/root/.ollama
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]

volumes:
  ollama_models:
```

> **Note:** The `ollama_models` volume will get large. A single 13B Q4 model is ~7GB. Plan for 50-100GB if you're going to experiment with multiple models.

---

### Postgres + pgvector: The Workhorse

Every AI development workflow eventually needs a place to store embeddings, conversation history, structured metadata, and application state. You could run a dedicated vector database (Qdrant, Weaviate, Milvus, Chroma). You shouldn't.

**Why pgvector over dedicated vector databases:**

1. **You're already running Postgres.** Or you should be. It's the most battle-tested database in existence. Adding the pgvector extension is one line in a Dockerfile.
2. **One less service to manage.** Every additional service is a thing that can break, needs updates, needs backups, needs monitoring. A dedicated vector DB adds operational overhead for marginal benefit at homelab scale.
3. **Hybrid queries.** With pgvector, you can combine vector similarity search with traditional SQL filtering in a single query. "Find the 10 most similar documents to this embedding WHERE project_id = 5 AND created_at > '2024-01-01'" — good luck doing that efficiently with a standalone vector DB.
4. **Mature ecosystem.** Postgres has decades of tooling for backup, replication, monitoring, and performance tuning. Your Qdrant instance has... a dashboard.

The trade-off: at massive scale (millions of high-dimensional vectors), dedicated vector databases can outperform pgvector on pure similarity search. You're not at massive scale. You're running a homelab. pgvector is more than enough.

```yaml
services:
  postgres:
    image: pgvector/pgvector:pg16
    container_name: cortex-postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: cortex
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: cortex
    ports:
      - "127.0.0.1:5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    deploy:
      resources:
        limits:
          memory: 2G
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U cortex"]
      interval: 10s
      timeout: 5s
      retries: 5
```

Note the `127.0.0.1` bind on the port. This database should not be accessible from the broader network. If other boxes need access, use SSH tunneling or a properly firewalled connection.

#### Connection Pooling

If you're running multiple AI services that all hit Postgres, consider PgBouncer:

```yaml
  pgbouncer:
    image: edoburu/pgbouncer:latest
    container_name: pgbouncer
    restart: unless-stopped
    environment:
      DATABASE_URL: postgres://cortex:${POSTGRES_PASSWORD}@cortex-postgres:5432/cortex
      POOL_MODE: transaction
      MAX_CLIENT_CONN: 200
      DEFAULT_POOL_SIZE: 20
    ports:
      - "127.0.0.1:6432:6432"
    depends_on:
      postgres:
        condition: service_healthy
```

AI workloads tend to open connections, run a burst of queries, then go idle. Transaction-mode pooling handles this pattern well.

---

### MCP Servers: Tool Use for AI Agents

Model Context Protocol (MCP) is an open standard for giving AI assistants access to tools, data sources, and services. If you're using Claude Code, Cursor, or similar AI coding tools, MCP is how those tools interact with your local environment — reading files, querying databases, searching the web, running code.

**Why MCP matters for AI-assisted development:**

Without MCP, your AI assistant is limited to what's in its context window. With MCP servers, it can query your database, search your codebase, check your monitoring dashboards, read your documentation — all through a standardized protocol. It turns a chatbot into a development partner with access to your actual infrastructure.

#### Running MCP Servers as Containers

MCP servers are typically lightweight processes. Containerizing them gives you the usual benefits: isolation, reproducibility, easy updates.

```yaml
  mcp-filesystem:
    image: your-registry/mcp-filesystem:latest
    container_name: mcp-filesystem
    restart: unless-stopped
    volumes:
      - /home/user/projects:/data/projects:ro
    environment:
      MCP_TRANSPORT: stdio

  mcp-postgres:
    image: your-registry/mcp-postgres:latest
    container_name: mcp-postgres
    restart: unless-stopped
    environment:
      DATABASE_URL: postgres://cortex:${POSTGRES_PASSWORD}@cortex-postgres:5432/cortex
      MCP_TRANSPORT: stdio
    networks:
      - cortex-backend
```

#### Security Considerations: This Is the Scary Part

MCP servers can execute code, read and write files, make network requests, and interact with databases. They are, by design, a bridge between an AI model and your actual systems.

**Scope their permissions aggressively:**

- Mount filesystems read-only unless write access is genuinely needed.
- Use dedicated database users with minimal privileges. The MCP Postgres server does not need `DROP DATABASE` permissions.
- Run MCP servers on isolated Docker networks. They should be able to reach the services they need and nothing else.
- Don't give an MCP server access to your entire home directory. Mount specific project directories.
- Review what tools an MCP server exposes. If it has a "run arbitrary shell command" tool, think very carefully about whether you want an AI model invoking that.

> **Warning:** An MCP server is effectively a remote code execution endpoint controlled by an AI model. Treat it with the same paranoia you'd treat any RCE vector. The AI model is generally trying to be helpful, but it can be confused, hallucinate tool calls, or be prompted maliciously. Defense in depth applies here.

---

### Supporting Services

**Redis** — Use it for caching LLM responses, rate limiting, session state for AI applications, and as a message broker if you're building async AI pipelines:

```yaml
  redis:
    image: redis:7-alpine
    container_name: cortex-redis
    restart: unless-stopped
    command: redis-server --maxmemory 512mb --maxmemory-policy allkeys-lru
    ports:
      - "127.0.0.1:6379:6379"
    volumes:
      - redis_data:/data
```

**MinIO** — S3-compatible object storage. Useful for storing model files, training data, large artifacts, and anything that doesn't belong in a database:

```yaml
  minio:
    image: minio/minio:latest
    container_name: cortex-minio
    restart: unless-stopped
    command: server /data --console-address ":9001"
    environment:
      MINIO_ROOT_USER: ${MINIO_ROOT_USER}
      MINIO_ROOT_PASSWORD: ${MINIO_ROOT_PASSWORD}
    ports:
      - "127.0.0.1:9000:9000"
      - "127.0.0.1:9001:9001"
    volumes:
      - minio_data:/data
```

---

## How the Dev Workflow Connects

You've got services running on the cortex box. Now your development machine — your laptop, your desktop, wherever you actually write code — needs to talk to them.

### SSH Tunneling vs. Direct Network Access

**Direct network access** (your dev machine can reach the cortex box's IP directly):
- Simpler setup. Point your tools at `cortex.local:11434` and go.
- Requires your dev machine to be on the same network (or a routed network/VPN).
- Every port you expose is a port you need to think about securing.

**SSH tunneling** (forward specific ports through an SSH connection):
- Works from anywhere. Coffee shop, office, different VLAN.
- Only one port needs to be reachable: SSH.
- Adds a step to your workflow. You need the tunnel up before you can work.
- Easy to script:

```bash
#!/bin/bash
# tunnel-cortex.sh — open tunnels to cortex services
ssh -N -L 11434:localhost:11434 \
       -L 5432:localhost:5432 \
       -L 6379:localhost:6379 \
       -L 9000:localhost:9000 \
       user@cortex.local
```

**The pragmatic approach:** If your dev machine is always on the same network as your cortex box, use direct access with services bound to `127.0.0.1` on the cortex box and a Tailscale/WireGuard overlay for access. If you're mobile or working from different locations, SSH tunnels are more portable.

### API Key Management

You're probably using a mix of local and cloud LLM providers. That means API keys for OpenAI, Anthropic, Google, etc.

**Don't put API keys in your code.** Don't put them in Docker Compose files. Don't put them in files that get committed to Git.

The `.env` pattern works well for homelab-scale operations:

```bash
# /home/user/cortex/.env
# Cloud LLM providers
ANTHROPIC_API_KEY=sk-ant-...
OPENAI_API_KEY=sk-...

# Local service credentials
POSTGRES_PASSWORD=<generated>
MINIO_ROOT_USER=admin
MINIO_ROOT_PASSWORD=<generated>

# Feature flags
USE_LOCAL_INFERENCE=true
LOCAL_INFERENCE_URL=http://ollama:11434
```

Add `.env` to your `.gitignore`. Use `.env.example` with placeholder values as documentation:

```bash
# .env.example — copy to .env and fill in real values
ANTHROPIC_API_KEY=sk-ant-your-key-here
OPENAI_API_KEY=sk-your-key-here
POSTGRES_PASSWORD=change-me
```

For anything more sophisticated — multiple environments, shared secrets across boxes, rotation policies — look at HashiCorp Vault or even just `pass` (the Unix password manager). But `.env` files are fine for getting started.

---

## Running AI Workloads in Docker

### GPU Passthrough with nvidia-container-toolkit

This is the part that trips people up. Here's the sequence:

1. **Install NVIDIA drivers on the host.** Not in a container. On the actual machine. Use your distro's package manager or NVIDIA's `.run` installer.

2. **Install nvidia-container-toolkit:**

```bash
# Add the NVIDIA container toolkit repository
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
  sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

3. **Verify it works:**

```bash
docker run --rm --gpus all nvidia/cuda:12.3.1-base-ubuntu22.04 nvidia-smi
```

If you see your GPU listed, you're good. If not, check that the NVIDIA driver is loaded (`nvidia-smi` on the host) and that the Docker daemon was restarted after configuring the toolkit.

4. **Use it in Compose:**

```yaml
deploy:
  resources:
    reservations:
      devices:
        - driver: nvidia
          count: all  # or a specific number
          capabilities: [gpu]
```

> **Note:** GPU passthrough is one of the few legitimate use cases for `--privileged` or elevated container capabilities. But the `nvidia-container-toolkit` approach above avoids needing full privileged mode. Don't reach for `--privileged` just because GPU stuff is confusing.

### Memory Limits: Non-Negotiable

AI workloads are memory-hungry and often unpredictable. A model that uses 8GB at idle can spike to 16GB under load due to KV cache growth. Without memory limits, one runaway inference request can OOM your entire box.

```yaml
deploy:
  resources:
    limits:
      memory: 16G    # Hard ceiling
    reservations:
      memory: 8G     # Guaranteed minimum
```

Set these for every AI-related container. Yes, it means you need to think about resource allocation. That's the point. You'd rather a single container get killed by the OOM reaper than have it take down your database.

### Model Storage

AI models are large files. A 7B Q4 model is ~4GB. A 70B Q4 is ~40GB. If you're running Ollama and experimenting with different models, you can easily accumulate 100GB+ of model files.

**Use a dedicated volume or mount point for model storage.** Don't let models fill up your root partition.

```yaml
volumes:
  ollama_models:
    driver: local
    driver_opts:
      type: none
      device: /mnt/models/ollama
      o: bind
```

If multiple containers need access to the same model files (e.g., Ollama and a custom inference server), use a shared volume mounted read-only in the consumers:

```yaml
services:
  ollama:
    volumes:
      - model_storage:/models

  custom-inference:
    volumes:
      - model_storage:/models:ro  # Read-only access
```

---

## Cost Reality Check

Let's talk money, because homelab enthusiasm often outpaces homelab budgets.

### The Budget Tiers

**Tier 1: CPU-Only Inference ($100-200)**

A used mini PC (Lenovo ThinkCentre, HP EliteDesk, Dell OptiPlex) with 32GB RAM. These go for $100-200 on eBay. You can run 7B quantized models at acceptable speeds for non-interactive workloads (batch embedding generation, background summarization). Interactive chat will feel sluggish.

Best for: Embedding generation, offline batch processing, running pgvector + supporting services.

**Tier 2: Entry GPU ($500-800)**

The Tier 1 box plus a used NVIDIA RTX 3060 12GB (~$200) or RTX 3080 10GB (~$300). Or a used workstation with a Quadro card. This gets you real-time inference on 7B-13B models and usable performance on quantized larger models.

Best for: Interactive coding assistance, real-time chat, moderate embedding workloads.

**Tier 3: Serious GPU ($1000-1500)**

A box with an RTX 3090 24GB (~$700 used) or RTX 4090 24GB (~$1200+ used). This runs 33B quantized models and handles multiple concurrent inference requests. This is where local inference starts to genuinely compete with cloud APIs for quality.

Best for: Running larger models locally, multiple concurrent users, heavier workloads.

### Cloud API Costs for Comparison

To calibrate expectations, here's roughly what cloud API spend gets you (prices fluctuate, these are approximate as of the time of writing):

- **$10/month**: Light usage. A few hundred coding questions, some document summarization. Probably enough for casual AI-assisted development.
- **$50/month**: Moderate usage. Regular coding assistance, embedding generation for a few projects, some batch processing. This is where many individual developers land.
- **$150/month**: Heavy usage. Continuous coding assistance, large-scale embedding, multiple projects, automated pipelines hitting the API. At this point, local inference for high-volume workloads starts making strong financial sense.

### The Hybrid Approach (This Is What Most People Should Do)

Don't go all-local or all-cloud. Use each where it makes sense:

| Workload | Run It... | Why |
|----------|-----------|-----|
| Complex reasoning, difficult coding problems | Cloud (frontier models) | Local models can't match frontier model quality on hard tasks |
| Code completion, simple Q&A | Local | High frequency, low complexity — perfect for local |
| Embedding generation | Local | High volume, no quality difference, saves significant API cost |
| Sensitive/proprietary data | Local | Data never leaves your network |
| Experimentation with new models | Local | No per-token cost for playing around |
| Production applications | Cloud | Reliability, uptime guarantees, no hardware maintenance |

The cortex box handles your local workloads. Cloud APIs handle the rest. Your `.env` file and application code switch between them. You get the best of both worlds: privacy and cost savings where they matter, frontier model quality where it matters.

---

## Putting It All Together

Here's a skeleton `docker-compose.yml` for a cortex box:

```yaml
version: "3.8"

services:
  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    restart: unless-stopped
    ports:
      - "${OLLAMA_HOST:-127.0.0.1}:11434:11434"
    volumes:
      - ollama_models:/root/.ollama
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
        limits:
          memory: 16G
    networks:
      - cortex

  postgres:
    image: pgvector/pgvector:pg16
    container_name: cortex-postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: ${POSTGRES_USER:-cortex}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB:-cortex}
    ports:
      - "127.0.0.1:5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    deploy:
      resources:
        limits:
          memory: 2G
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-cortex}"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - cortex

  redis:
    image: redis:7-alpine
    container_name: cortex-redis
    restart: unless-stopped
    command: redis-server --maxmemory 512mb --maxmemory-policy allkeys-lru
    ports:
      - "127.0.0.1:6379:6379"
    volumes:
      - redis_data:/data
    networks:
      - cortex

  minio:
    image: minio/minio:latest
    container_name: cortex-minio
    restart: unless-stopped
    command: server /data --console-address ":9001"
    environment:
      MINIO_ROOT_USER: ${MINIO_ROOT_USER}
      MINIO_ROOT_PASSWORD: ${MINIO_ROOT_PASSWORD}
    ports:
      - "127.0.0.1:9000:9000"
      - "127.0.0.1:9001:9001"
    volumes:
      - minio_data:/data
    networks:
      - cortex

networks:
  cortex:
    driver: bridge

volumes:
  ollama_models:
  postgres_data:
  redis_data:
  minio_data:
```

Start here. Add MCP servers as you need them. Add PgBouncer when connection counts become an issue. Add a second GPU when the first one isn't enough. The cortex box grows with your usage, not ahead of it.

The key insight: **your AI dev stack is infrastructure, not a toy.** Treat it like you'd treat any other piece of your homelab — with proper isolation, resource limits, backup, and monitoring. The "move fast and break things" ethos applies to what you build *on top of* the stack, not to the stack itself.
