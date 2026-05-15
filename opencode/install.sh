#!/bin/bash
source <(curl -sL https://raw.githubusercontent.com/rmayobre/shtuff/v1.3.0-beta/shtuff-remote.sh)
shopt -s expand_aliases

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

# ─── Setup Inside Container ───────────────────────────────────────────────────

info "Installing OpenCode in container '$CT_NAME'..."

CONTAINER_SCRIPT
#!/bin/bash
source <(curl -sL https://raw.githubusercontent.com/rmayobre/shtuff/v1.3.0-beta/shtuff-remote.sh)

apt-get update -qq &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Updating packages" \
    --success_msg "Packages updated" --error_msg "Package update failed" || exit 1

apt-get install -y curl ca-certificates &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing dependencies" \
    --success_msg "Dependencies installed" --error_msg "Dependency installation failed" || exit 1

curl -fsSL https://opencode.ai/install | bash &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing OpenCode" \
    --success_msg "OpenCode installed" --error_msg "OpenCode installation failed" || exit 1

cat > /etc/systemd/system/opencode.service <<EOF
[Unit]
Description=OpenCode Web UI
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/opencode web --hostname 0.0.0.0 --port $OC_PORT
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Reloading systemd" \
    --success_msg "systemd reloaded" --error_msg "Failed to reload systemd" || exit 1

systemctl enable --now opencode &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Starting OpenCode service" \
    --success_msg "OpenCode service started" --error_msg "Failed to start OpenCode service" || exit 1
CONTAINER_SCRIPT_EOD

container shell-script --name "$CT_NAME" --path /opt/opencode-setup.sh \
    --style "$SPINNER_LOADING_STYLE" &
monitor $! --style "$SPINNER_LOADING_STYLE" \
    --message "Deploying OpenCode setup script" \
    --success_msg "Setup script deployed" \
    --error_msg "Setup script deployment failed" || exit 1

container exec --name "$CT_NAME" -- /opt/opencode-setup.sh &
monitor $! --style "$SPINNER_LOADING_STYLE" \
    --message "Installing OpenCode" \
    --success_msg "OpenCode ready" \
    --error_msg "OpenCode setup failed" || exit 1

# ─── Host Cleanup ─────────────────────────────────────────────────────────────

clean &
monitor $! --style "$SPINNER_LOADING_STYLE" \
    --message "Cleaning up" \
    --success_msg "Cleanup complete" \
    --error_msg "Cleanup failed"

info "OpenCode installed successfully in container '$CT_NAME'!"
info "Access the web UI at: http://<container-ip>:${OC_PORT}"
