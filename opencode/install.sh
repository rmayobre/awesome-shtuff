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

# ─── Dependencies Inside Container ────────────────────────────────────────────

CONTAINER_SCRIPT
#!/bin/bash
apt-get update -qq
apt-get install -y curl ca-certificates
CONTAINER_SCRIPT_EOD

container shell-script --name "$CT_NAME" --path /opt/opencode-deps.sh \
    --style "$SPINNER_LOADING_STYLE" &
monitor $! --style "$SPINNER_LOADING_STYLE" \
    --message "Deploying dependency script" \
    --success_msg "Dependency script deployed" \
    --error_msg "Dependency script deployment failed" || exit 1

container exec --name "$CT_NAME" -- /opt/opencode-deps.sh &
monitor $! --style "$SPINNER_LOADING_STYLE" \
    --message "Installing dependencies" \
    --success_msg "Dependencies installed" \
    --error_msg "Dependency installation failed" || exit 1

# ─── OpenCode Installation ────────────────────────────────────────────────────

info "Installing OpenCode in container '$CT_NAME'..."

CONTAINER_SCRIPT
#!/bin/bash
curl -fsSL https://opencode.ai/install | bash
CONTAINER_SCRIPT_EOD

container shell-script --name "$CT_NAME" --path /opt/opencode-install.sh \
    --style "$SPINNER_LOADING_STYLE" &
monitor $! --style "$SPINNER_LOADING_STYLE" \
    --message "Deploying OpenCode installer" \
    --success_msg "Installer deployed" \
    --error_msg "Installer deployment failed" || exit 1

container exec --name "$CT_NAME" -- /opt/opencode-install.sh &
monitor $! --style "$SPINNER_LOADING_STYLE" \
    --message "Installing OpenCode" \
    --success_msg "OpenCode installed" \
    --error_msg "OpenCode installation failed" || exit 1

# ─── Service Setup ────────────────────────────────────────────────────────────

CONTAINER_SCRIPT
#!/bin/bash
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
systemctl daemon-reload
systemctl enable --now opencode
CONTAINER_SCRIPT_EOD

container shell-script --name "$CT_NAME" --path /opt/opencode-service.sh \
    --style "$SPINNER_LOADING_STYLE" &
monitor $! --style "$SPINNER_LOADING_STYLE" \
    --message "Deploying service setup script" \
    --success_msg "Service setup script deployed" \
    --error_msg "Service setup script deployment failed" || exit 1

container exec --name "$CT_NAME" -- /opt/opencode-service.sh &
monitor $! --style "$SPINNER_LOADING_STYLE" \
    --message "Configuring OpenCode service" \
    --success_msg "OpenCode service enabled and started" \
    --error_msg "Failed to configure OpenCode service" || exit 1

# ─── Host Cleanup ─────────────────────────────────────────────────────────────

clean &
monitor $! --style "$SPINNER_LOADING_STYLE" \
    --message "Cleaning up" \
    --success_msg "Cleanup complete" \
    --error_msg "Cleanup failed"

info "OpenCode installed successfully in container '$CT_NAME'!"
info "Access the web UI at: http://<container-ip>:${OC_PORT}"
