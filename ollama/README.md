# Ollama

Install scripts for [Ollama](https://ollama.com) — a tool for running large language models locally.

## Scripts

| Script | Description |
|---|---|
| `install.sh` | Creates an LXC/PCT container and installs Ollama inside it |
| `install-host.sh` | Installs Ollama directly on the host system |

---

## Container Install (`install.sh`)

Provisions a new container (Proxmox PCT or LXC, auto-detected) and installs Ollama inside it. Best for isolating Ollama from the host.

### Prompts

| Prompt | Default | Description |
|---|---|---|
| Distribution | — | `debian` or `ubuntu` |
| Release | — | e.g. `bookworm`, `noble` |
| Container name | `ollama` | Name for the container |
| Container hostname | `ollama` | Hostname inside the container |
| Memory (MB) | `2048` | RAM allocated to the container |
| CPU cores | `2` | vCPU count |
| Disk size (GB) | `20` | Disk space for the container |
| Ollama port | `11434` | Port Ollama listens on |
| GPU passthrough | — | Pass a host GPU into the container |
| Pull model | _(blank)_ | Optionally pull a model (e.g. `llama3`) after install |

### Run

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/rmayobre/awesome-shtuff/master/ollama/install.sh)
```

---

## Host Install (`install-host.sh`)

Installs Ollama directly on the host system. Suitable for bare-metal machines or VMs where containerization is not needed.

### Prompts

| Prompt | Default | Description |
|---|---|---|
| Ollama port | `11434` | Port Ollama listens on |
| Listen address | `0.0.0.0` | Network interface to bind (use `127.0.0.1` for local-only) |
| Pull model | _(blank)_ | Optionally pull a model (e.g. `mistral`) after install |

### Run

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/rmayobre/awesome-shtuff/master/ollama/install-host.sh)
```

---

## Notes

- **GPU support**: Ollama automatically detects NVIDIA and AMD GPUs. For the container install, enable GPU passthrough when prompted and ensure the host has the appropriate drivers installed.
- **Models**: After install, pull any model with `ollama pull <model>`. Browse available models at [ollama.com/library](https://ollama.com/library).
- **API**: The Ollama REST API is available at `http://<host>:<port>` (default port `11434`). See the [Ollama API docs](https://github.com/ollama/ollama/blob/main/docs/api.md) for usage.
