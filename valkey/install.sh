#!/bin/bash
source <(curl -sL https://raw.githubusercontent.com/rmayobre/shtuff/v1.2.0/shtuff-remote.sh)

# ─── User Configuration ───────────────────────────────────────────────────────

info "Configuring Valkey installation..."

# Container configuration
question "Container name [valkey]"     && CT_NAME="${answer:-valkey}"
question "Container hostname [valkey]" && CT_HOSTNAME="${answer:-valkey}"
question "Memory in MB [512]"          && CT_MEMORY="${answer:-512}"
question "CPU cores [1]"               && CT_CORES="${answer:-1}"
question "Disk size in GB [4]"         && CT_DISK="${answer:-4}"

# Valkey-specific configuration
question "Valkey port [6379]"          && VALKEY_PORT="${answer:-6379}"
question "Valkey password (leave blank for no auth)" && VALKEY_PASSWORD="${answer:-}"

options "Persistence mode" \
    --choice "rdb" \
    --choice "aof" \
    --choice "none" \
    && VALKEY_PERSISTENCE="$answer"

# ─── Container Creation ───────────────────────────────────────────────────────

info "Creating container for Valkey..."

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

container exec --name "$CT_NAME" -- apt-get install -y curl gpg &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing dependencies" \
    --success_msg "Dependencies installed" --error_msg "Dependency installation failed" || exit 1

# ─── Add Valkey Repository ────────────────────────────────────────────────────

info "Adding Valkey package repository..."

VALKEY_REPO_SETUP="curl -fsSL https://packages.valkey.io/valkey-signing.gpg \
    | gpg --dearmor -o /usr/share/keyrings/valkey-archive-keyring.gpg && \
    echo 'deb [signed-by=/usr/share/keyrings/valkey-archive-keyring.gpg] https://packages.valkey.io/apt stable main' \
    | tee /etc/apt/sources.list.d/valkey.list"

container exec --name "$CT_NAME" -- bash -c "$VALKEY_REPO_SETUP" &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Adding Valkey repository" \
    --success_msg "Valkey repository added" --error_msg "Failed to add Valkey repository" || exit 1

container exec --name "$CT_NAME" -- apt-get update -qq &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Refreshing package lists" \
    --success_msg "Package lists refreshed" --error_msg "Package list refresh failed" || exit 1

# ─── Installation ─────────────────────────────────────────────────────────────

container exec --name "$CT_NAME" -- apt-get install -y valkey &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing Valkey" \
    --success_msg "Valkey installed" --error_msg "Valkey installation failed" || exit 1

# ─── Valkey Configuration ─────────────────────────────────────────────────────

info "Configuring Valkey..."

# Build the sed commands to configure valkey.conf
VALKEY_CONF_CMDS="sed -i 's/^port .*/port $VALKEY_PORT/' /etc/valkey/valkey.conf"

# Bind to all interfaces so the container is reachable
VALKEY_CONF_CMDS="$VALKEY_CONF_CMDS && sed -i 's/^bind .*/bind 0.0.0.0/' /etc/valkey/valkey.conf"

# Configure authentication
if [[ -n "$VALKEY_PASSWORD" ]]; then
    VALKEY_CONF_CMDS="$VALKEY_CONF_CMDS && sed -i 's/^# requirepass .*/requirepass $VALKEY_PASSWORD/' /etc/valkey/valkey.conf"
    VALKEY_CONF_CMDS="$VALKEY_CONF_CMDS && sed -i 's/^requirepass .*/requirepass $VALKEY_PASSWORD/' /etc/valkey/valkey.conf"
fi

# Configure persistence
case "$VALKEY_PERSISTENCE" in
    rdb)
        VALKEY_CONF_CMDS="$VALKEY_CONF_CMDS && sed -i 's/^appendonly .*/appendonly no/' /etc/valkey/valkey.conf"
        ;;
    aof)
        VALKEY_CONF_CMDS="$VALKEY_CONF_CMDS && sed -i 's/^appendonly .*/appendonly yes/' /etc/valkey/valkey.conf"
        ;;
    none)
        VALKEY_CONF_CMDS="$VALKEY_CONF_CMDS && sed -i 's/^save /#save /' /etc/valkey/valkey.conf"
        VALKEY_CONF_CMDS="$VALKEY_CONF_CMDS && sed -i 's/^appendonly .*/appendonly no/' /etc/valkey/valkey.conf"
        ;;
esac

container exec --name "$CT_NAME" -- bash -c "$VALKEY_CONF_CMDS" &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Applying Valkey configuration" \
    --success_msg "Valkey configured" --error_msg "Valkey configuration failed" || exit 1

# ─── Service Setup ────────────────────────────────────────────────────────────

container exec --name "$CT_NAME" -- systemctl enable --now valkey &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Enabling Valkey service" \
    --success_msg "Valkey service enabled" --error_msg "Failed to enable Valkey service" || exit 1

# ─── Host Cleanup ─────────────────────────────────────────────────────────────

clean &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Cleaning up" \
    --success_msg "Cleanup complete" --error_msg "Cleanup failed"

info "Valkey installed successfully in container '$CT_NAME'!"
info "Valkey is listening on port $VALKEY_PORT."
if [[ -n "$VALKEY_PASSWORD" ]]; then
    info "Authentication is enabled. Connect with: valkey-cli -h <container-ip> -p $VALKEY_PORT -a <password>"
else
    warn "No password set. Consider enabling authentication for production use."
fi
