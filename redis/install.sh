#!/bin/bash
source <(curl -sL https://raw.githubusercontent.com/rmayobre/shtuff/v1.2.0/shtuff-remote.sh)

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

# ─── Dependencies Inside Container ────────────────────────────────────────────

container exec --name "$CT_NAME" -- apt-get update -qq &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Updating packages in container" \
    --success_msg "Packages updated" --error_msg "Package update failed" || exit 1

container exec --name "$CT_NAME" -- apt-get install -y redis-server &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing Redis" \
    --success_msg "Redis installed" --error_msg "Redis installation failed" || exit 1

# ─── Redis Configuration ──────────────────────────────────────────────────────

info "Configuring Redis..."

# Build the sed commands to configure redis.conf
REDIS_CONF_CMDS="sed -i 's/^port .*/port $REDIS_PORT/' /etc/redis/redis.conf"

# Bind to all interfaces so the container is reachable
REDIS_CONF_CMDS="$REDIS_CONF_CMDS && sed -i 's/^bind .*/bind 0.0.0.0/' /etc/redis/redis.conf"

# Configure authentication
if [[ -n "$REDIS_PASSWORD" ]]; then
    REDIS_CONF_CMDS="$REDIS_CONF_CMDS && sed -i 's/^# requirepass .*/requirepass $REDIS_PASSWORD/' /etc/redis/redis.conf"
    REDIS_CONF_CMDS="$REDIS_CONF_CMDS && sed -i 's/^requirepass .*/requirepass $REDIS_PASSWORD/' /etc/redis/redis.conf"
fi

# Configure persistence
case "$REDIS_PERSISTENCE" in
    rdb)
        REDIS_CONF_CMDS="$REDIS_CONF_CMDS && sed -i 's/^appendonly .*/appendonly no/' /etc/redis/redis.conf"
        ;;
    aof)
        REDIS_CONF_CMDS="$REDIS_CONF_CMDS && sed -i 's/^appendonly .*/appendonly yes/' /etc/redis/redis.conf"
        ;;
    none)
        REDIS_CONF_CMDS="$REDIS_CONF_CMDS && sed -i 's/^save /#save /' /etc/redis/redis.conf"
        REDIS_CONF_CMDS="$REDIS_CONF_CMDS && sed -i 's/^appendonly .*/appendonly no/' /etc/redis/redis.conf"
        ;;
esac

container exec --name "$CT_NAME" -- bash -c "$REDIS_CONF_CMDS" &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Applying Redis configuration" \
    --success_msg "Redis configured" --error_msg "Redis configuration failed" || exit 1

# ─── Service Setup ────────────────────────────────────────────────────────────

container exec --name "$CT_NAME" -- systemctl enable --now redis-server &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Enabling Redis service" \
    --success_msg "Redis service enabled" --error_msg "Failed to enable Redis service" || exit 1

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
