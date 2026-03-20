# Plex Media Server

Install scripts for [Plex Media Server](https://www.plex.tv/) — a self-hosted media platform for streaming your personal movie, TV, and music library.

Two install options are available:

| Script | Description |
|---|---|
| `install.sh` | Installs Plex inside a new **container** (recommended) |
| `install-host.sh` | Installs Plex directly on the **host** system |

---

## Container Install (Recommended)

Spins up a dedicated container and installs Plex inside it. Keeps Plex isolated from the host system.

**Requirements:** Proxmox or an LXC-capable Linux host.

```bash
bash <(curl -sL https://raw.githubusercontent.com/rmayobre/awesome-shtuff/master/plex/install.sh)
```

### Prompts

| Prompt | Default | Description |
|---|---|---|
| Container name | `plex` | Name of the container |
| Container hostname | `plex` | Hostname inside the container |
| Memory in MB | `2048` | RAM allocated to the container |
| CPU cores | `2` | vCPU cores allocated |
| Disk size in GB | `20` | Disk space for the container |
| Plex port | `32400` | Port Plex listens on |
| Media library path | _(blank)_ | Host path to bind-mount into `/media` inside the container |

After install, open the Plex web UI at:

```
http://<container-ip>:32400/web
```

---

## Host Install

Installs Plex directly on the current machine. Use this if you are not running a container-based environment.

**Requirements:** Debian or Ubuntu-based host with `apt`.

```bash
bash <(curl -sL https://raw.githubusercontent.com/rmayobre/awesome-shtuff/master/plex/install-host.sh)
```

### Prompts

| Prompt | Default | Description |
|---|---|---|
| Plex port | `32400` | Port Plex listens on |
| Media library path | _(blank)_ | Path to your media library (grants `plex` user access) |

After install, open the Plex web UI at:

```
http://localhost:32400/web
```

---

## Notes

- Both scripts add the official [Plex APT repository](https://downloads.plex.tv/repo/deb) and install `plexmediaserver`.
- The Plex service is enabled and started automatically via `systemctl`.
- For the container install, if you do not provide a media path, mount your library inside the container manually after creation.
- Built with [rmayobre/shtuff](https://github.com/rmayobre/shtuff) `v1.2.0`.
