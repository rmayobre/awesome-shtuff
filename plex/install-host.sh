#!/bin/bash
source <(curl -sL https://raw.githubusercontent.com/rmayobre/shtuff/main/shtuff-remote.sh)

# ─── User Configuration ───────────────────────────────────────────────────────

info "Configuring Plex Media Server (host) installation..."

question "Plex port [32400]" && PLEX_PORT="${answer:-32400}"
question "Media library path (leave blank to configure later)" \
    && MEDIA_PATH="${answer:-}"

if ! confirm "Plex will be installed directly on this host. Continue?"; then
    info "Aborted."
    exit 0
fi

# ─── Dependencies ─────────────────────────────────────────────────────────────

update &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Updating packages" \
    --success_msg "Packages updated" --error_msg "Package update failed" || exit 1

install curl wget gnupg2 ca-certificates &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing dependencies" \
    --success_msg "Dependencies installed" --error_msg "Dependency installation failed" || exit 1

# ─── Plex Repository Setup ────────────────────────────────────────────────────

info "Configuring Plex repository..."

curl -fsSL https://downloads.plex.tv/plex-keys/PlexSign.key \
    | gpg --dearmor -o /usr/share/keyrings/plex-archive-keyring.gpg &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Adding Plex GPG key" \
    --success_msg "Plex GPG key added" --error_msg "Failed to add Plex GPG key" || exit 1

echo "deb [signed-by=/usr/share/keyrings/plex-archive-keyring.gpg] https://downloads.plex.tv/repo/deb public main" \
    > /etc/apt/sources.list.d/plexmediaserver.list &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Adding Plex repository" \
    --success_msg "Plex repository added" --error_msg "Failed to add Plex repository" || exit 1

update &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Refreshing package lists" \
    --success_msg "Package lists refreshed" --error_msg "Package list refresh failed" || exit 1

# ─── Plex Installation ────────────────────────────────────────────────────────

info "Installing Plex Media Server..."

install plexmediaserver &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing Plex Media Server" \
    --success_msg "Plex Media Server installed" --error_msg "Plex installation failed" || exit 1

# ─── Media Library Permissions (optional) ─────────────────────────────────────

if [[ -n "$MEDIA_PATH" ]]; then
    if [[ ! -d "$MEDIA_PATH" ]]; then
        warn "Media path '$MEDIA_PATH' does not exist. Skipping permission setup."
    else
        chown -R plex:plex "$MEDIA_PATH" &
        monitor $! --style "$SPINNER_LOADING_STYLE" --message "Setting media library permissions" \
            --success_msg "Media permissions set" --error_msg "Failed to set media permissions"
    fi
else
    warn "No media path provided. Grant the 'plex' user access to your library manually."
fi

# ─── Service Setup ────────────────────────────────────────────────────────────

systemctl enable --now plexmediaserver &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Enabling Plex Media Server service" \
    --success_msg "Plex service enabled and started" --error_msg "Failed to enable Plex service" || exit 1

# ─── Host Cleanup ─────────────────────────────────────────────────────────────

clean &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Cleaning up" \
    --success_msg "Cleanup complete" --error_msg "Cleanup failed"

info "Plex Media Server installed successfully on this host!"
info "Access the web UI at: http://localhost:${PLEX_PORT}/web"
