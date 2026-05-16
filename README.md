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

Prepares a Linux server to run LXC containers. Configures the network bridge (`lxcbr0`), IP forwarding, NAT, AppArmor profiles, and UID/GID mapping — the settings most likely to block container deployment on a fresh host.

```bash
bash <(curl -sL https://raw.githubusercontent.com/rmayobre/awesome-shtuff/main/lxc/setup.sh)
```

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
