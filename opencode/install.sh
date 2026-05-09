#!/bin/bash
source <(curl -sL https://raw.githubusercontent.com/rmayobre/shtuff/v1.2.0/shtuff-remote.sh)

# ─── User Configuration ───────────────────────────────────────────────────────

info "Configuring OpenCode installation..."

# Distribution
options "Select distribution" \
    --choice "debian" \
    --choice "ubuntu" \
    && CT_DIST="$answer"

case "$CT_DIST" in
    debian)
        options "Select Debian release" \
            --choice "bullseye" \
            --choice "bookworm" \
            && CT_RELEASE="$answer"
        ;;
    ubuntu)
        options "Select Ubuntu release" \
            --choice "focal" \
            --choice "jammy" \
            --choice "noble" \
            && CT_RELEASE="$answer"
        ;;
esac

# Container configuration
question "Container name [opencode]"     && CT_NAME="${answer:-opencode}"
question "Container hostname [opencode]" && CT_HOSTNAME="${answer:-opencode}"
question "Memory in MB [512]"            && CT_MEMORY="${answer:-512}"
question "CPU cores [1]"                 && CT_CORES="${answer:-1}"
question "Disk size in GB [8]"           && CT_DISK="${answer:-8}"

# OpenCode configuration
question "Web UI port [4096]"            && OC_PORT="${answer:-4096}"

# ─── Container Creation ───────────────────────────────────────────────────────

info "Creating container for OpenCode..."

container create \
    --name "$CT_NAME" \
    --hostname "$CT_HOSTNAME" \
    --memory "$CT_MEMORY" \
    --cores "$CT_CORES" \
    --disk-size "$CT_DISK" \
    --dist "$CT_DIST" \
    --release "$CT_RELEASE" \
    --style "$SPINNER_LOADING_STYLE" || exit 1

container start --name "$CT_NAME" --style "$SPINNER_LOADING_STYLE" || exit 1

# ─── Dependencies Inside Container ────────────────────────────────────────────

container exec --name "$CT_NAME" -- apt-get update -qq &
monitor $! --style "$SPINNER_LOADING_STYLE" \
    --message "Updating packages in container" \
    --success_msg "Packages updated" \
    --error_msg "Package update failed" || exit 1

container exec --name "$CT_NAME" -- apt-get install -y curl ca-certificates &
monitor $! --style "$SPINNER_LOADING_STYLE" \
    --message "Installing dependencies" \
    --success_msg "Dependencies installed" \
    --error_msg "Dependency installation failed" || exit 1

# ─── OpenCode Installation ────────────────────────────────────────────────────

info "Installing OpenCode in container '$CT_NAME'..."

container exec --name "$CT_NAME" -- bash -c "curl -fsSL https://opencode.ai/install | bash" &
monitor $! --style "$SPINNER_LOADING_STYLE" \
    --message "Installing OpenCode" \
    --success_msg "OpenCode installed" \
    --error_msg "OpenCode installation failed" || exit 1

# ─── Service Setup ────────────────────────────────────────────────────────────

container exec --name "$CT_NAME" -- bash -c \
    "printf '[Unit]\nDescription=OpenCode Web UI\nAfter=network.target\n\n[Service]\nType=simple\nExecStart=/usr/local/bin/opencode web --hostname 0.0.0.0 --port ${OC_PORT}\nRestart=on-failure\nRestartSec=5\n\n[Install]\nWantedBy=multi-user.target\n' \
    > /etc/systemd/system/opencode.service" &
monitor $! --style "$SPINNER_LOADING_STYLE" \
    --message "Creating OpenCode systemd service" \
    --success_msg "Service created" \
    --error_msg "Service creation failed" || exit 1

container exec --name "$CT_NAME" -- systemctl daemon-reload &
monitor $! --style "$SPINNER_LOADING_STYLE" \
    --message "Reloading systemd" \
    --success_msg "Systemd reloaded" \
    --error_msg "Systemd reload failed" || exit 1

container exec --name "$CT_NAME" -- systemctl enable --now opencode &
monitor $! --style "$SPINNER_LOADING_STYLE" \
    --message "Enabling OpenCode service" \
    --success_msg "OpenCode service enabled and started" \
    --error_msg "Failed to enable OpenCode service" || exit 1

# ─── Host Cleanup ─────────────────────────────────────────────────────────────

clean &
monitor $! --style "$SPINNER_LOADING_STYLE" \
    --message "Cleaning up" \
    --success_msg "Cleanup complete" \
    --error_msg "Cleanup failed"

info "OpenCode installed successfully in container '$CT_NAME'!"
info "Access the web UI at: http://<container-ip>:${OC_PORT}"
