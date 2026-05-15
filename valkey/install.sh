#!/bin/bash
source <(curl -sL https://raw.githubusercontent.com/rmayobre/shtuff/v1.3.0-beta/shtuff-remote.sh)
shopt -s expand_aliases

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

# ─── Setup Inside Container ───────────────────────────────────────────────────

info "Installing and configuring Valkey..."

CONTAINER_SCRIPT
#!/bin/bash
apt-get update -qq
apt-get install -y curl gpg
curl -fsSL https://packages.valkey.io/valkey-signing.gpg \
    | gpg --dearmor -o /usr/share/keyrings/valkey-archive-keyring.gpg
echo 'deb [signed-by=/usr/share/keyrings/valkey-archive-keyring.gpg] https://packages.valkey.io/apt stable main' \
    | tee /etc/apt/sources.list.d/valkey.list
apt-get update -qq
apt-get install -y valkey
sed -i 's/^port .*/port ${VALKEY_PORT}/' /etc/valkey/valkey.conf
sed -i 's/^bind .*/bind 0.0.0.0/' /etc/valkey/valkey.conf
if [[ -n "${VALKEY_PASSWORD}" ]]; then
    sed -i 's/^# requirepass .*/requirepass ${VALKEY_PASSWORD}/' /etc/valkey/valkey.conf
    sed -i 's/^requirepass .*/requirepass ${VALKEY_PASSWORD}/' /etc/valkey/valkey.conf
fi
case "${VALKEY_PERSISTENCE}" in
    rdb)
        sed -i 's/^appendonly .*/appendonly no/' /etc/valkey/valkey.conf
        ;;
    aof)
        sed -i 's/^appendonly .*/appendonly yes/' /etc/valkey/valkey.conf
        ;;
    none)
        sed -i 's/^save /#save /' /etc/valkey/valkey.conf
        sed -i 's/^appendonly .*/appendonly no/' /etc/valkey/valkey.conf
        ;;
esac
systemctl enable --now valkey
CONTAINER_SCRIPT_EOD

container shell-script --name "$CT_NAME" --path /opt/valkey-setup.sh \
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
