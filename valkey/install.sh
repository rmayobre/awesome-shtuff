#!/bin/bash
source <(curl -sL https://raw.githubusercontent.com/rmayobre/shtuff/main/shtuff-remote.sh)

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

# ─── Network Configuration ────────────────────────────────────────────────────

info "Configuring network for container '$CT_NAME'..."
container network prompt --name "$CT_NAME" || exit 1

# ─── Setup Inside Container ───────────────────────────────────────────────────

info "Installing and configuring Valkey..."

CONTAINER_SCRIPT
#!/bin/bash
source <(wget -qO- https://raw.githubusercontent.com/rmayobre/shtuff/main/shtuff-remote.sh)

update &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Updating packages" \
    --success_msg "Packages updated" --error_msg "Package update failed" || exit 1

install curl gpg &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing dependencies" \
    --success_msg "Dependencies installed" --error_msg "Dependency installation failed" || exit 1

curl -fsSL https://packages.valkey.io/valkey-signing.gpg \
    | gpg --dearmor -o /usr/share/keyrings/valkey-archive-keyring.gpg \
    || { error "Failed to add Valkey signing key"; exit 1; }

echo 'deb [signed-by=/usr/share/keyrings/valkey-archive-keyring.gpg] https://packages.valkey.io/apt stable main' \
    | tee /etc/apt/sources.list.d/valkey.list \
    || { error "Failed to add Valkey repository"; exit 1; }

update &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Updating package lists" \
    --success_msg "Package lists updated" --error_msg "Package list update failed" || exit 1

install valkey &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing Valkey" \
    --success_msg "Valkey installed" --error_msg "Valkey installation failed" || exit 1

sed -i 's/^port .*/port ${VALKEY_PORT}/' /etc/valkey/valkey.conf \
    || { error "Failed to configure Valkey port"; exit 1; }
sed -i 's/^bind .*/bind 0.0.0.0/' /etc/valkey/valkey.conf \
    || { error "Failed to configure Valkey bind address"; exit 1; }

if [[ -n "${VALKEY_PASSWORD}" ]]; then
    sed -i 's/^# requirepass .*/requirepass ${VALKEY_PASSWORD}/' /etc/valkey/valkey.conf \
        || { error "Failed to configure Valkey password"; exit 1; }
    sed -i 's/^requirepass .*/requirepass ${VALKEY_PASSWORD}/' /etc/valkey/valkey.conf \
        || { error "Failed to configure Valkey password"; exit 1; }
fi

case "${VALKEY_PERSISTENCE}" in
    rdb)
        sed -i 's/^appendonly .*/appendonly no/' /etc/valkey/valkey.conf \
            || { error "Failed to configure Valkey persistence"; exit 1; }
        ;;
    aof)
        sed -i 's/^appendonly .*/appendonly yes/' /etc/valkey/valkey.conf \
            || { error "Failed to configure Valkey persistence"; exit 1; }
        ;;
    none)
        sed -i 's/^save /#save /' /etc/valkey/valkey.conf \
            || { error "Failed to configure Valkey persistence"; exit 1; }
        sed -i 's/^appendonly .*/appendonly no/' /etc/valkey/valkey.conf \
            || { error "Failed to configure Valkey persistence"; exit 1; }
        ;;
esac

systemctl enable --now valkey &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Starting Valkey service" \
    --success_msg "Valkey service started" --error_msg "Failed to start Valkey service" || exit 1
CONTAINER_SCRIPT_EOD

container shell-script --name "$CT_NAME" --path /opt/valkey-setup.sh \
    --env "VALKEY_PORT=$VALKEY_PORT" \
    --env "VALKEY_PASSWORD=$VALKEY_PASSWORD" \
    --env "VALKEY_PERSISTENCE=$VALKEY_PERSISTENCE" \
    --env "SPINNER_LOADING_STYLE=$SPINNER_LOADING_STYLE" \
    --style "$SPINNER_LOADING_STYLE" &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Deploying Valkey setup script" \
    --success_msg "Setup script deployed" --error_msg "Setup script deployment failed" || exit 1

container exec --name "$CT_NAME" -- /opt/valkey-setup.sh &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing and configuring Valkey" \
    --success_msg "Valkey ready" --error_msg "Valkey setup failed" || exit 1

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
