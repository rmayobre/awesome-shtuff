# CLAUDE.md

## Project Overview

`awesome-shtuff` is a collection of install scripts for self-hosting projects. Each script automates the installation and configuration of a self-hosted application inside a **container** on the target system.

## Script Framework

All install scripts **must** use [rmayobre/shtuff](https://github.com/rmayobre/shtuff) as the scripting framework. Always use the **latest release** (currently `v1.2.0`).

Download the shtuff release tarball and source it locally at the top of every script:

```bash
SHTUFF_VERSION="1.2.0"
SHTUFF_TARBALL="/tmp/shtuff-${SHTUFF_VERSION}.tar.gz"
SHTUFF_DIR="/tmp/shtuff-${SHTUFF_VERSION}"

curl -fsSL "https://github.com/rmayobre/shtuff/archive/refs/tags/v${SHTUFF_VERSION}.tar.gz" \
    -o "$SHTUFF_TARBALL"
tar -xzf "$SHTUFF_TARBALL" -C /tmp/
source "${SHTUFF_DIR}/shtuff.sh"
```

This downloads the release once, extracts it to `/tmp/`, and sources the local `shtuff.sh` entry point. The `$SHTUFF_DIR` variable is reused later to push shtuff into the container.

When a new shtuff release is published, update `SHTUFF_VERSION` across all scripts and this file.

## Repository Structure

Organize scripts by project name:

```
awesome-shtuff/
├── CLAUDE.md
├── README.md
├── <project-name>/
│   ├── install.sh       # Primary install script
│   └── update.sh        # Optional update script
└── <another-project>/
    ├── install.sh
    └── update.sh
```

- Directory names: lowercase, hyphenated (e.g., `nextcloud/`, `home-assistant/`, `immich/`)
- Script files: `install.sh`, `update.sh`

## Install Script Requirements

### 1. Shebang and shtuff Source

Every script must begin with the shebang followed by the shtuff release download and local source block:

```bash
#!/bin/bash

SHTUFF_VERSION="1.2.0"
SHTUFF_TARBALL="/tmp/shtuff-${SHTUFF_VERSION}.tar.gz"
SHTUFF_DIR="/tmp/shtuff-${SHTUFF_VERSION}"

curl -fsSL "https://github.com/rmayobre/shtuff/archive/refs/tags/v${SHTUFF_VERSION}.tar.gz" \
    -o "$SHTUFF_TARBALL"
tar -xzf "$SHTUFF_TARBALL" -C /tmp/
source "${SHTUFF_DIR}/shtuff.sh"
```

### 2. User Input for Configuration

Scripts **must** prompt the user for all project-specific configuration values. Never hardcode configuration. Use shtuff's form functions — all store the user's response in `$answer`:

```bash
# Free-text input
question "Container name [my-app]" && CT_NAME="${answer:-my-app}"

# Numbered menu
options "Select distribution" "debian" "ubuntu" "alpine" && CT_DIST="$answer"

# Yes/No confirmation
confirm "Enable HTTPS?" && ENABLE_HTTPS="$answer"
```

Validate required inputs and exit with an error if they are missing or invalid.

### 3. Container Creation

Every install script **must** create a container to host the installed software. Use the unified `container` command, which automatically selects PCT (Proxmox) or LXC based on the host environment. Prompt the user for container configuration before creating it.

```bash
# Collect container configuration
question "Container name [<project>]"     && CT_NAME="${answer:-<project>}"
question "Container hostname [<project>]" && CT_HOSTNAME="${answer:-<project>}"
question "Memory in MB [512]"             && CT_MEMORY="${answer:-512}"
question "CPU cores [1]"                  && CT_CORES="${answer:-1}"
question "Disk size in GB [8]"            && CT_DISK="${answer:-8}"

# Create the container
container create \
    --name "$CT_NAME" \
    --hostname "$CT_HOSTNAME" \
    --memory "$CT_MEMORY" \
    --cores "$CT_CORES" \
    --disk-size "$CT_DISK" \
    --style "$SPINNER_LOADING_STYLE" || exit 1

# Start the container
container start --name "$CT_NAME" --style "$SPINNER_LOADING_STYLE" || exit 1
```

### 4. Copy shtuff Into the Container

After starting the container, push the locally downloaded shtuff directory into it. This allows all subsequent `container exec` commands to source shtuff and use its functions (e.g., `install`, `update`) inside the container.

```bash
container push --name "$CT_NAME" --source "$SHTUFF_DIR" --dest "/opt/shtuff"
```

### 5. Software Installation Inside the Container

After copying shtuff, install the project's dependencies and software **inside** the container using `container exec`. Prefix each exec call with `source /opt/shtuff/shtuff.sh &&` to use shtuff's package management functions. Run commands in the background and monitor them with `monitor`:

```bash
# Update packages inside the container
container exec --name "$CT_NAME" -- bash -c "source /opt/shtuff/shtuff.sh && update" &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Updating packages in container" \
    --success_msg "Packages updated" --error_msg "Package update failed" || exit 1

# Install dependencies inside the container
container exec --name "$CT_NAME" -- bash -c "source /opt/shtuff/shtuff.sh && install curl wget <dep1> <dep2>" &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing dependencies" \
    --success_msg "Dependencies installed" --error_msg "Dependency installation failed" || exit 1

# Push configuration files into the container
container push --name "$CT_NAME" --source "./config.yml" --dest "/etc/<project>/config.yml"
```

Use shtuff's `install` and `update` functions rather than bare `apt-get` calls — they auto-detect the container's package manager and work across distributions.

### 6. Logging

Use shtuff's logging functions throughout:

- `info "message"` — green, normal status
- `warn "message"` — yellow, non-fatal warnings
- `error "message"` — red, fatal errors (follow with `exit 1`)
- `debug "message"` — verbose output (shown when `LOG_LEVEL=DEBUG`)

### 7. Cleanup (Required)

Every install script **must** end with a dependency cleanup step on the **host** system:

```bash
clean &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Cleaning up" \
    --success_msg "Cleanup complete" --error_msg "Cleanup failed"
```

This removes orphaned packages and clears the package manager cache on the host after the container is created.

## Script Template

```bash
#!/bin/bash

# ─── Download & Source shtuff ─────────────────────────────────────────────────

SHTUFF_VERSION="1.2.0"
SHTUFF_TARBALL="/tmp/shtuff-${SHTUFF_VERSION}.tar.gz"
SHTUFF_DIR="/tmp/shtuff-${SHTUFF_VERSION}"

curl -fsSL "https://github.com/rmayobre/shtuff/archive/refs/tags/v${SHTUFF_VERSION}.tar.gz" \
    -o "$SHTUFF_TARBALL"
tar -xzf "$SHTUFF_TARBALL" -C /tmp/
source "${SHTUFF_DIR}/shtuff.sh"

# ─── User Configuration ───────────────────────────────────────────────────────

info "Configuring <project-name> installation..."

# Container configuration
question "Container name [<project>]"     && CT_NAME="${answer:-<project>}"
question "Container hostname [<project>]" && CT_HOSTNAME="${answer:-<project>}"
question "Memory in MB [512]"             && CT_MEMORY="${answer:-512}"
question "CPU cores [1]"                  && CT_CORES="${answer:-1}"
question "Disk size in GB [8]"            && CT_DISK="${answer:-8}"

# Project-specific configuration
question "Application port [8080]"        && APP_PORT="${answer:-8080}"
confirm "Enable HTTPS?"                   && ENABLE_HTTPS="$answer"
# Add more prompts as needed for the project

# ─── Container Creation ───────────────────────────────────────────────────────

info "Creating container for <project-name>..."

container create \
    --name "$CT_NAME" \
    --hostname "$CT_HOSTNAME" \
    --memory "$CT_MEMORY" \
    --cores "$CT_CORES" \
    --disk-size "$CT_DISK" \
    --style "$SPINNER_LOADING_STYLE" || exit 1

container start --name "$CT_NAME" --style "$SPINNER_LOADING_STYLE" || exit 1

# ─── Copy shtuff Into Container ───────────────────────────────────────────────

container push --name "$CT_NAME" --source "$SHTUFF_DIR" --dest "/opt/shtuff"

# ─── Dependencies Inside Container ────────────────────────────────────────────

container exec --name "$CT_NAME" -- bash -c "source /opt/shtuff/shtuff.sh && update" &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Updating packages in container" \
    --success_msg "Packages updated" --error_msg "Package update failed" || exit 1

container exec --name "$CT_NAME" -- bash -c "source /opt/shtuff/shtuff.sh && install <dep1> <dep2>" &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing dependencies" \
    --success_msg "Dependencies installed" --error_msg "Dependency installation failed" || exit 1

# ─── Installation Steps ───────────────────────────────────────────────────────

info "Installing <project-name>..."
# ... project-specific installation logic inside the container ...
# container exec --name "$CT_NAME" -- <install command>
# container push --name "$CT_NAME" --source "./config.yml" --dest "/etc/<project>/config.yml"

# ─── Service Setup (if applicable) ────────────────────────────────────────────

# container exec --name "$CT_NAME" -- systemctl enable --now <project>

# ─── Host Cleanup ─────────────────────────────────────────────────────────────

clean &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Cleaning up" \
    --success_msg "Cleanup complete" --error_msg "Cleanup failed"

info "<project-name> installed successfully in container '$CT_NAME'!"
```

## Updating shtuff Version

When a new shtuff release is published:
1. Update `SHTUFF_VERSION` in every script (`1.2.0` → new version, without the `v` prefix)
2. Update the version reference in this CLAUDE.md
