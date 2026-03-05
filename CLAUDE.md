# CLAUDE.md

## Project Overview

`awesome-shtuff` is a collection of install scripts for self-hosting projects. Each script automates the installation and configuration of a self-hosted application inside a **container** on the target system.

## Script Framework

All install scripts **must** use [rmayobre/shtuff](https://github.com/rmayobre/shtuff) as the scripting framework. Always use the **latest release** (currently `v1.2.0`).

Source shtuff at the top of every script:

```bash
source <(curl -sL https://raw.githubusercontent.com/rmayobre/shtuff/v1.2.0/shtuff-remote.sh)
```

When a new shtuff release is published, update the version tag across all scripts and this file.

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

Every script must begin with:

```bash
#!/bin/bash
source <(curl -sL https://raw.githubusercontent.com/rmayobre/shtuff/v1.2.0/shtuff-remote.sh)
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

Every install script **must** create an LXC container to host the installed software. Prompt the user for container configuration before creating it.

```bash
# Collect container configuration
question "Container name [<project>]"   && CT_NAME="${answer:-<project>}"
question "Container hostname [<project>]" && CT_HOSTNAME="${answer:-<project>}"
question "Memory in MB [512]"           && CT_MEMORY="${answer:-512}"
question "CPU cores [1]"               && CT_CORES="${answer:-1}"
question "Disk size in GB [8]"         && CT_DISK="${answer:-8}"

# Create the container
lxc_create \
    --name "$CT_NAME" \
    --hostname "$CT_HOSTNAME" \
    --dist "debian" \
    --release "trixie" \
    --memory "$CT_MEMORY" \
    --cores "$CT_CORES" \
    --disk-size "$CT_DISK" \
    --style "$SPINNER_LOADING_STYLE" || exit 1

# Start the container
lxc_start --name "$CT_NAME" --style "$SPINNER_LOADING_STYLE" || exit 1
```

For Proxmox VE environments, use `pct_create` instead of `lxc_create`:

```bash
pct_create \
    --vmid "$CT_VMID" \
    --template "$CT_TEMPLATE" \
    --hostname "$CT_HOSTNAME" \
    --memory "$CT_MEMORY" \
    --cores "$CT_CORES" \
    --disk-size "$CT_DISK" \
    --style "$SPINNER_LOADING_STYLE" || exit 1
```

### 4. Software Installation Inside the Container

After creating the container, install the project's dependencies and software **inside** it using `lxc_exec`:

```bash
# Update packages inside the container
lxc_exec --name "$CT_NAME" --cmd "apt-get update -qq" \
    --style "$SPINNER_LOADING_STYLE" --message "Updating packages" || exit 1

# Install dependencies inside the container
lxc_exec --name "$CT_NAME" --cmd "apt-get install -y curl wget <dep1> <dep2>" \
    --style "$SPINNER_LOADING_STYLE" --message "Installing dependencies" || exit 1

# Push configuration files into the container
lxc_push --name "$CT_NAME" --source "./config.yml" --dest "/etc/<project>/config.yml"
```

### 5. Logging

Use shtuff's logging functions throughout:

- `info "message"` — green, normal status
- `warn "message"` — yellow, non-fatal warnings
- `error "message"` — red, fatal errors (follow with `exit 1`)
- `debug "message"` — verbose output (shown when `LOG_LEVEL=DEBUG`)

### 6. Cleanup (Required)

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
source <(curl -sL https://raw.githubusercontent.com/rmayobre/shtuff/v1.2.0/shtuff-remote.sh)

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

lxc_create \
    --name "$CT_NAME" \
    --hostname "$CT_HOSTNAME" \
    --dist "debian" \
    --release "trixie" \
    --memory "$CT_MEMORY" \
    --cores "$CT_CORES" \
    --disk-size "$CT_DISK" \
    --style "$SPINNER_LOADING_STYLE" || exit 1

lxc_start --name "$CT_NAME" --style "$SPINNER_LOADING_STYLE" || exit 1

# ─── Dependencies Inside Container ────────────────────────────────────────────

lxc_exec --name "$CT_NAME" --cmd "apt-get update -qq" \
    --style "$SPINNER_LOADING_STYLE" --message "Updating packages in container" || exit 1

lxc_exec --name "$CT_NAME" --cmd "apt-get install -y <dep1> <dep2>" \
    --style "$SPINNER_LOADING_STYLE" --message "Installing dependencies" || exit 1

# ─── Installation Steps ───────────────────────────────────────────────────────

info "Installing <project-name>..."
# ... project-specific installation logic inside the container ...
# lxc_exec --name "$CT_NAME" --cmd "<install command>"
# lxc_push --name "$CT_NAME" --source "./config.yml" --dest "/etc/<project>/config.yml"

# ─── Service Setup (if applicable) ────────────────────────────────────────────

# lxc_exec --name "$CT_NAME" --cmd "systemctl enable --now <project>"

# ─── Host Cleanup ─────────────────────────────────────────────────────────────

clean &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Cleaning up" \
    --success_msg "Cleanup complete" --error_msg "Cleanup failed"

info "<project-name> installed successfully in container '$CT_NAME'!"
```

## Updating shtuff Version

When a new shtuff release is published:
1. Update the version tag in the `source` line of every script (`v1.2.0` → new version)
2. Update the version reference in this CLAUDE.md
3. Test all affected scripts after updating
