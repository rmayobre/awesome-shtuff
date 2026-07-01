# CLAUDE.md

## Project Overview

`awesome-shtuff` is a collection of install scripts for self-hosting projects. Each script automates the installation and configuration of a self-hosted application inside a **container** on the target system.

## Script Framework

All install scripts **must** use [rmayobre/shtuff](https://github.com/rmayobre/shtuff) as the scripting framework. Always source the `main` branch to track the latest changes.

Source shtuff at the top of every host script:

```bash
source <(curl -sL https://raw.githubusercontent.com/rmayobre/shtuff/main/shtuff-remote.sh)
```

Inside embedded `CONTAINER_SCRIPT` blocks, use `wget` instead (containers may not have `curl` pre-installed):

```bash
source <(wget -qO- https://raw.githubusercontent.com/rmayobre/shtuff/main/shtuff-remote.sh)
```

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
source <(curl -sL https://raw.githubusercontent.com/rmayobre/shtuff/main/shtuff-remote.sh)
```

### 2. User Input for Configuration

Scripts **must** prompt the user for all project-specific configuration values. Never hardcode configuration. Use shtuff's form functions — all store the user's response in `$answer`:

```bash
# Free-text input
question "Container name [my-app]" && CT_NAME="${answer:-my-app}"

# Numbered menu
options "Select distribution" "debian" "ubuntu" "alpine" && CT_DIST="$answer"

# Yes/No confirmation (returns 0 for yes, 1 for no; sets $answer to "yes"/"no")
if confirm "Enable HTTPS?"; then
    ENABLE_HTTPS="yes"
fi
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

# Configure container network
container network prompt --name "$CT_NAME" || exit 1
```

### 4. Software Installation Inside the Container

After creating the container, deploy a `CONTAINER_SCRIPT` block that runs inside the container. Use shtuff's `update`, `install`, and `clean` functions directly — they handle backgrounding and `monitor` internally. Pass `--success_msg` and `--error_msg` to customize messages; omit `--style` and `--message` to use shtuff's defaults:

```bash
CONTAINER_SCRIPT
#!/bin/bash
source <(wget -qO- https://raw.githubusercontent.com/rmayobre/shtuff/main/shtuff-remote.sh)

update --success_msg "Packages updated" --error_msg "Package update failed" || exit 1

install curl wget <dep1> <dep2> --success_msg "Dependencies installed" --error_msg "Dependency installation failed" || exit 1

# Non-shtuff commands still require manual & + monitor
systemctl enable --now <project> &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Starting service" \
    --success_msg "Service started" --error_msg "Failed to start service" || exit 1
CONTAINER_SCRIPT_EOD

container shell-script --name "$CT_NAME" --path /opt/<project>-setup.sh \
    --env "SPINNER_LOADING_STYLE=$SPINNER_LOADING_STYLE" \
    --style "$SPINNER_LOADING_STYLE" &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Deploying setup script" \
    --success_msg "Setup script deployed" --error_msg "Setup script deployment failed" || exit 1

container exec --name "$CT_NAME" -- /opt/<project>-setup.sh &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing <project>" \
    --success_msg "<project> ready" --error_msg "<project> setup failed" || exit 1
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
clean --success_msg "Cleanup complete" --error_msg "Cleanup failed"
```

This removes orphaned packages and clears the package manager cache on the host after the container is created.

## Script Template

```bash
#!/bin/bash
source <(curl -sL https://raw.githubusercontent.com/rmayobre/shtuff/main/shtuff-remote.sh)

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
if confirm "Enable HTTPS?"; then ENABLE_HTTPS="yes"; else ENABLE_HTTPS="no"; fi
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

# ─── Network Configuration ────────────────────────────────────────────────────

info "Configuring network for container '$CT_NAME'..."
container network prompt --name "$CT_NAME" || exit 1

# ─── Setup Inside Container ───────────────────────────────────────────────────

info "Installing <project-name>..."

CONTAINER_SCRIPT
#!/bin/bash
source <(wget -qO- https://raw.githubusercontent.com/rmayobre/shtuff/main/shtuff-remote.sh)

update --success_msg "Packages updated" --error_msg "Package update failed" || exit 1

install <dep1> <dep2> --success_msg "Dependencies installed" --error_msg "Dependency installation failed" || exit 1

# ... project-specific installation logic ...

# container push --name "$CT_NAME" --source "./config.yml" --dest "/etc/<project>/config.yml"
# systemctl enable --now <project> &
# monitor $! --style "$SPINNER_LOADING_STYLE" --message "Starting service" \
#     --success_msg "Service started" --error_msg "Failed to start service" || exit 1
CONTAINER_SCRIPT_EOD

container shell-script --name "$CT_NAME" --path /opt/<project>-setup.sh \
    --env "SPINNER_LOADING_STYLE=$SPINNER_LOADING_STYLE" \
    --style "$SPINNER_LOADING_STYLE" &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Deploying setup script" \
    --success_msg "Setup script deployed" --error_msg "Setup script deployment failed" || exit 1

container exec --name "$CT_NAME" -- /opt/<project>-setup.sh &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing <project-name>" \
    --success_msg "<project-name> ready" --error_msg "<project-name> setup failed" || exit 1

# ─── Host Cleanup ─────────────────────────────────────────────────────────────

clean --success_msg "Cleanup complete" --error_msg "Cleanup failed"

info "<project-name> installed successfully in container '$CT_NAME'!"
```

## Updating shtuff

Scripts source the `main` branch directly, so they always pick up the latest shtuff changes without any version bumps needed.
