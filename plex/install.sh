#!/bin/bash
source <(curl -sL https://raw.githubusercontent.com/rmayobre/shtuff/v1.2.0/shtuff-remote.sh)

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

# ─── Dependencies Inside Container ────────────────────────────────────────────

container exec --name "$CT_NAME" -- apt-get update -qq &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Updating packages in container" \
    --success_msg "Packages updated" --error_msg "Package update failed" || exit 1

container exec --name "$CT_NAME" -- apt-get install -y curl wget gnupg2 ca-certificates &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing dependencies" \
    --success_msg "Dependencies installed" --error_msg "Dependency installation failed" || exit 1

# ─── Plex Repository Setup ────────────────────────────────────────────────────

info "Configuring Plex repository inside container..."

container exec --name "$CT_NAME" -- bash -c \
    "curl -fsSL https://downloads.plex.tv/plex-keys/PlexSign.key \
     | gpg --dearmor -o /usr/share/keyrings/plex-archive-keyring.gpg" &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Adding Plex GPG key" \
    --success_msg "Plex GPG key added" --error_msg "Failed to add Plex GPG key" || exit 1

container exec --name "$CT_NAME" -- bash -c \
    "echo 'deb [signed-by=/usr/share/keyrings/plex-archive-keyring.gpg] https://downloads.plex.tv/repo/deb public main' \
     > /etc/apt/sources.list.d/plexmediaserver.list" &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Adding Plex repository" \
    --success_msg "Plex repository added" --error_msg "Failed to add Plex repository" || exit 1

container exec --name "$CT_NAME" -- apt-get update -qq &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Refreshing package lists" \
    --success_msg "Package lists refreshed" --error_msg "Package list refresh failed" || exit 1

# ─── Plex Installation ────────────────────────────────────────────────────────

info "Installing Plex Media Server..."

container exec --name "$CT_NAME" -- apt-get install -y plexmediaserver &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing Plex Media Server" \
    --success_msg "Plex Media Server installed" --error_msg "Plex installation failed" || exit 1

# ─── Media Library Bind Mount (optional) ──────────────────────────────────────

if [[ -n "$MEDIA_PATH" ]]; then
    info "Configuring media library bind mount: $MEDIA_PATH -> /media"
    container exec --name "$CT_NAME" -- mkdir -p /media
    container exec --name "$CT_NAME" -- bash -c \
        "echo '$MEDIA_PATH /media none bind,ro 0 0' >> /etc/fstab" &
    monitor $! --style "$SPINNER_LOADING_STYLE" --message "Configuring media bind mount" \
        --success_msg "Media bind mount configured" --error_msg "Failed to configure bind mount"
else
    warn "No media path configured. Mount your library manually at /media inside the container."
fi

# ─── Service Setup ────────────────────────────────────────────────────────────

container exec --name "$CT_NAME" -- systemctl enable --now plexmediaserver &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Enabling Plex Media Server service" \
    --success_msg "Plex service enabled and started" --error_msg "Failed to enable Plex service" || exit 1

# ─── Host Cleanup ─────────────────────────────────────────────────────────────

clean &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Cleaning up" \
    --success_msg "Cleanup complete" --error_msg "Cleanup failed"

info "Plex Media Server installed successfully in container '$CT_NAME'!"
info "Access the web UI at: http://<container-ip>:${PLEX_PORT}/web"
info "Run 'container exec --name $CT_NAME -- hostname -I' to find the container IP."
