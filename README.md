# awesome-shtuff

A collection of interactive install scripts for self-hosting. Each script prompts for configuration and automates setup inside a container or directly on the host.

## Requirements

- Debian-based host (Ubuntu, Debian, Proxmox, etc.)
- `curl` and `bash` available
- Root or sudo access

Scripts that create containers require a supported container runtime (Proxmox LXC or system LXC).

---

## Container Tools

### LXC Host Setup

Prepares a Linux server to run LXC containers. Prompts for a bridge IP address and applies all configurations required to deploy multiple containers on a single host.

```bash
bash <(curl -sL https://raw.githubusercontent.com/rmayobre/awesome-shtuff/main/lxc/setup.sh)
```

| Configuration | Why it blocks multiple containers without it |
|---|---|
| `lxcbr0` bridge + `lxc-net` | Containers have no network interface — every deployment fails or is unreachable |
| `/etc/lxc/default.conf` with `lxcbr0` | Without this, newly created containers have no NIC at all |
| `net.ipv4.ip_forward = 1` | Containers can ping the bridge but can't reach the internet — silently breaks all outbound traffic |
| `apparmor.profile = generated` + `allow_nesting = 1` | Default strict AppArmor profile blocks container start on many distros; nesting is required for containers running systemd |
| `root:100000:65536` in `subuid`/`subgid` | `lxc-usernsexec` fails — no unprivileged container can start at all |
| `kernel.unprivileged_userns_clone = 1` | On pre-24.04 Ubuntu this sysctl is `0` by default, blocking all unprivileged container creation (silently skipped on kernels that don't expose it) |

### Create Container

Interactively create and provision a bare distro container with base utilities.

```bash
bash <(curl -sL https://raw.githubusercontent.com/rmayobre/awesome-shtuff/main/container/create_container.sh)
```

---

## Databases

### MariaDB

Installs MariaDB in a new container. Prompts for root password, optional database name, user, and password.

```bash
bash <(curl -sL https://raw.githubusercontent.com/rmayobre/awesome-shtuff/main/mariadb/install.sh)
```

### MySQL

Installs MySQL in a new container. Prompts for root password, optional database name, user, and password.

```bash
bash <(curl -sL https://raw.githubusercontent.com/rmayobre/awesome-shtuff/main/mysql/install.sh)
```

### PostgreSQL

Installs PostgreSQL in a new container. Prompts for database name, user, and password.

```bash
bash <(curl -sL https://raw.githubusercontent.com/rmayobre/awesome-shtuff/main/postgres/install.sh)
```

### Redis

Installs Redis in a new container. Prompts for port, optional password, and persistence mode (RDB, AOF, or none).

```bash
bash <(curl -sL https://raw.githubusercontent.com/rmayobre/awesome-shtuff/main/redis/install.sh)
```

### Valkey

Installs Valkey in a new container. Prompts for port, optional password, and persistence mode (RDB, AOF, or none).

```bash
bash <(curl -sL https://raw.githubusercontent.com/rmayobre/awesome-shtuff/main/valkey/install.sh)
```

---

## AI / LLM

### Ollama (container)

Installs Ollama in a new container with optional GPU passthrough. Prompts for distribution, resources, listen port, GPU settings, and an optional model to pull after install.

```bash
bash <(curl -sL https://raw.githubusercontent.com/rmayobre/awesome-shtuff/main/ollama/install.sh)
```

### Ollama (host)

Installs Ollama directly on the host. Prompts for listen port, bind address, and an optional model to pull after install.

```bash
bash <(curl -sL https://raw.githubusercontent.com/rmayobre/awesome-shtuff/main/ollama/install-host.sh)
```

### OpenCode (container)

Installs OpenCode and runs it as a systemd service inside a new container. Prompts for distribution, resources, and web UI port.

```bash
bash <(curl -sL https://raw.githubusercontent.com/rmayobre/awesome-shtuff/main/opencode/install.sh)
```

---

## CI/CD

### Woodpecker CI (container)

Installs Woodpecker CI server and agent in a new container. Prompts for resources, web UI/gRPC ports, external URL, forge integration (GitHub, Gitea, GitLab, or Bitbucket), admin users, open registration, and the agent's pipeline backend (local or Docker).

```bash
bash <(curl -sL https://raw.githubusercontent.com/rmayobre/awesome-shtuff/main/woodpecker/install.sh)
```

---

## Media

### Plex Media Server (container)

Installs Plex Media Server in a new container. Prompts for resources and an optional host media path to bind-mount into the container.

```bash
bash <(curl -sL https://raw.githubusercontent.com/rmayobre/awesome-shtuff/main/plex/install.sh)
```

### Plex Media Server (host)

Installs Plex Media Server directly on the host. Prompts for port and an optional media library path to set permissions on.

```bash
bash <(curl -sL https://raw.githubusercontent.com/rmayobre/awesome-shtuff/main/plex/install-host.sh)
```
