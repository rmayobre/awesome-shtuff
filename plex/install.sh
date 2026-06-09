#!/bin/bash
source <(curl -sL https://raw.githubusercontent.com/rmayobre/shtuff/main/shtuff-remote.sh)

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

# ─── Network Configuration ────────────────────────────────────────────────────

info "Configuring network for container '$CT_NAME'..."
container network prompt --name "$CT_NAME" || exit 1

# ─── Setup Inside Container ───────────────────────────────────────────────────

[[ -z "$MEDIA_PATH" ]] && warn "No media path configured. Mount your library manually at /media inside the container."

info "Installing Plex Media Server..."

CONTAINER_SCRIPT
source <(wget -qO- https://raw.githubusercontent.com/rmayobre/shtuff/main/shtuff-remote.sh)

update &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Updating packages" \
    --success_msg "Packages updated" --error_msg "Package update failed" || exit 1

install curl wget gnupg2 ca-certificates &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing dependencies" \
    --success_msg "Dependencies installed" --error_msg "Dependency installation failed" || exit 1

curl -fsSL https://downloads.plex.tv/plex-keys/PlexSign.key \
    | gpg --dearmor -o /usr/share/keyrings/plex-archive-keyring.gpg \
    || { error "Failed to add Plex signing key"; exit 1; }

echo 'deb [signed-by=/usr/share/keyrings/plex-archive-keyring.gpg] https://downloads.plex.tv/repo/deb public main' \
    > /etc/apt/sources.list.d/plexmediaserver.list \
    || { error "Failed to add Plex repository"; exit 1; }

update &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Updating package lists" \
    --success_msg "Package lists updated" --error_msg "Package list update failed" || exit 1

install plexmediaserver &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing Plex Media Server" \
    --success_msg "Plex Media Server installed" --error_msg "Plex installation failed" || exit 1

if [[ -n "${MEDIA_PATH}" ]]; then
    mkdir -p /media \
        || { error "Failed to create /media directory"; exit 1; }
    echo '${MEDIA_PATH} /media none bind,ro 0 0' >> /etc/fstab \
        || { error "Failed to configure media bind mount"; exit 1; }
fi

systemctl enable --now plexmediaserver &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Starting Plex Media Server" \
    --success_msg "Plex Media Server started" --error_msg "Failed to start Plex Media Server" || exit 1
CONTAINER_SCRIPT_EOD

container shell-script --name "$CT_NAME" --path /opt/plex-setup.sh \
    --env "MEDIA_PATH=$MEDIA_PATH" \
    --env "SPINNER_LOADING_STYLE=$SPINNER_LOADING_STYLE" \
    --style "$SPINNER_LOADING_STYLE" &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Deploying Plex setup script" \
    --success_msg "Setup script deployed" --error_msg "Setup script deployment failed" || exit 1

container exec --name "$CT_NAME" -- bash /opt/plex-setup.sh &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing Plex Media Server" \
    --success_msg "Plex Media Server ready" --error_msg "Plex installation failed" || exit 1

# ─── Host Cleanup ─────────────────────────────────────────────────────────────

clean &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Cleaning up" \
    --success_msg "Cleanup complete" --error_msg "Cleanup failed"

info "Plex Media Server installed successfully in container '$CT_NAME'!"
info "Access the web UI at: http://<container-ip>:${PLEX_PORT}/web"
info "Run 'container exec --name $CT_NAME -- hostname -I' to find the container IP."
