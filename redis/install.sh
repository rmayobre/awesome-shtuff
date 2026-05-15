#!/bin/bash
source <(curl -sL https://raw.githubusercontent.com/rmayobre/shtuff/v1.3.0-beta/shtuff-remote.sh)
shopt -s expand_aliases

# ─── User Configuration ───────────────────────────────────────────────────────

info "Configuring Redis installation..."

# Container configuration
question "Container name [redis]"     && CT_NAME="${answer:-redis}"
question "Container hostname [redis]" && CT_HOSTNAME="${answer:-redis}"
question "Memory in MB [512]"         && CT_MEMORY="${answer:-512}"
question "CPU cores [1]"              && CT_CORES="${answer:-1}"
question "Disk size in GB [4]"        && CT_DISK="${answer:-4}"

# Redis-specific configuration
question "Redis port [6379]"          && REDIS_PORT="${answer:-6379}"
question "Redis password (leave blank for no auth)" && REDIS_PASSWORD="${answer:-}"

options "Persistence mode" \
    --choice "rdb" \
    --choice "aof" \
    --choice "none" \
    && REDIS_PERSISTENCE="$answer"

# ─── Container Creation ───────────────────────────────────────────────────────

info "Creating container for Redis..."

container create \
    --name "$CT_NAME" \
    --hostname "$CT_HOSTNAME" \
    --memory "$CT_MEMORY" \
    --cores "$CT_CORES" \
    --disk-size "$CT_DISK" \
    --style "$SPINNER_LOADING_STYLE" || exit 1

container start --name "$CT_NAME" --style "$SPINNER_LOADING_STYLE" || exit 1

# ─── Setup Inside Container ───────────────────────────────────────────────────

info "Installing and configuring Redis..."

CONTAINER_SCRIPT
#!/bin/bash
apt-get update -qq
apt-get install -y redis-server
sed -i 's/^port .*/port ${REDIS_PORT}/' /etc/redis/redis.conf
sed -i 's/^bind .*/bind 0.0.0.0/' /etc/redis/redis.conf
if [[ -n "${REDIS_PASSWORD}" ]]; then
    sed -i 's/^# requirepass .*/requirepass ${REDIS_PASSWORD}/' /etc/redis/redis.conf
    sed -i 's/^requirepass .*/requirepass ${REDIS_PASSWORD}/' /etc/redis/redis.conf
fi
case "${REDIS_PERSISTENCE}" in
    rdb)
        sed -i 's/^appendonly .*/appendonly no/' /etc/redis/redis.conf
        ;;
    aof)
        sed -i 's/^appendonly .*/appendonly yes/' /etc/redis/redis.conf
        ;;
    none)
        sed -i 's/^save /#save /' /etc/redis/redis.conf
        sed -i 's/^appendonly .*/appendonly no/' /etc/redis/redis.conf
        ;;
esac
systemctl enable --now redis-server
CONTAINER_SCRIPT_EOD

container shell-script --name "$CT_NAME" --path /opt/redis-setup.sh \
    --style "$SPINNER_LOADING_STYLE" &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Deploying Redis setup script" \
    --success_msg "Setup script deployed" --error_msg "Setup script deployment failed" || exit 1

container exec --name "$CT_NAME" -- /opt/redis-setup.sh &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing and configuring Redis" \
    --success_msg "Redis ready" --error_msg "Redis setup failed" || exit 1

# ─── Host Cleanup ─────────────────────────────────────────────────────────────

clean &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Cleaning up" \
    --success_msg "Cleanup complete" --error_msg "Cleanup failed"

info "Redis installed successfully in container '$CT_NAME'!"
info "Redis is listening on port $REDIS_PORT."
if [[ -n "$REDIS_PASSWORD" ]]; then
    info "Authentication is enabled. Connect with: redis-cli -h <container-ip> -p $REDIS_PORT -a <password>"
else
    warn "No password set. Consider enabling authentication for production use."
fi
