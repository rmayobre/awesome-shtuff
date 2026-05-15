#!/bin/bash
source <(curl -sL https://raw.githubusercontent.com/rmayobre/shtuff/v1.3.0-beta/shtuff-remote.sh)
shopt -s expand_aliases

# ─── User Configuration ───────────────────────────────────────────────────────

info "Configuring Plex Media Server (container) installation..."

# Container configuration
question "Container name [plex]"     && CT_NAME="${answer:-plex}"
question "Container hostname [plex]" && CT_HOSTNAME="${answer:-plex}"
question "Memory in MB [2048]"       && CT_MEMORY="${answer:-2048}"
question "CPU cores [2]"             && CT_CORES="${answer:-2}"
question "Disk size in GB [20]"      && CT_DISK="${answer:-20}"

# Plex-specific configuration
question "Plex port [32400]"         && PLEX_PORT="${answer:-32400}"
question "Media library path on host (leave blank to skip bind mount)" \
    && MEDIA_PATH="${answer:-}"

if [[ -z "$CT_NAME" ]]; then
    error "Container name is required."
    exit 1
fi

# ─── Container Creation ───────────────────────────────────────────────────────

info "Creating container for Plex Media Server..."

container create \
    --name "$CT_NAME" \
    --hostname "$CT_HOSTNAME" \
    --memory "$CT_MEMORY" \
    --cores "$CT_CORES" \
    --disk-size "$CT_DISK" \
    --style "$SPINNER_LOADING_STYLE" || exit 1

container start --name "$CT_NAME" --style "$SPINNER_LOADING_STYLE" || exit 1

# ─── Setup Inside Container ───────────────────────────────────────────────────

[[ -z "$MEDIA_PATH" ]] && warn "No media path configured. Mount your library manually at /media inside the container."

info "Installing Plex Media Server..."

CONTAINER_SCRIPT
#!/bin/bash
apt-get update -qq
apt-get install -y curl wget gnupg2 ca-certificates
curl -fsSL https://downloads.plex.tv/plex-keys/PlexSign.key \
    | gpg --dearmor -o /usr/share/keyrings/plex-archive-keyring.gpg
echo 'deb [signed-by=/usr/share/keyrings/plex-archive-keyring.gpg] https://downloads.plex.tv/repo/deb public main' \
    > /etc/apt/sources.list.d/plexmediaserver.list
apt-get update -qq
apt-get install -y plexmediaserver
if [[ -n "${MEDIA_PATH}" ]]; then
    mkdir -p /media
    echo '${MEDIA_PATH} /media none bind,ro 0 0' >> /etc/fstab
fi
systemctl enable --now plexmediaserver
CONTAINER_SCRIPT_EOD

container shell-script --name "$CT_NAME" --path /opt/plex-setup.sh \
    --style "$SPINNER_LOADING_STYLE" &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Deploying Plex setup script" \
    --success_msg "Setup script deployed" --error_msg "Setup script deployment failed" || exit 1

container exec --name "$CT_NAME" -- /opt/plex-setup.sh &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing Plex Media Server" \
    --success_msg "Plex Media Server ready" --error_msg "Plex installation failed" || exit 1

# ─── Host Cleanup ─────────────────────────────────────────────────────────────

clean &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Cleaning up" \
    --success_msg "Cleanup complete" --error_msg "Cleanup failed"

info "Plex Media Server installed successfully in container '$CT_NAME'!"
info "Access the web UI at: http://<container-ip>:${PLEX_PORT}/web"
info "Run 'container exec --name $CT_NAME -- hostname -I' to find the container IP."
