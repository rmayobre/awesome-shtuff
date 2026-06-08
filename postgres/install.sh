#!/bin/bash
source <(curl -sL https://raw.githubusercontent.com/rmayobre/shtuff/main/shtuff-remote.sh)

# ─── User Configuration ───────────────────────────────────────────────────────

info "Configuring PostgreSQL installation..."

# Container configuration
question "Container name [postgres]"     && CT_NAME="${answer:-postgres}"
question "Container hostname [postgres]" && CT_HOSTNAME="${answer:-postgres}"
question "Memory in MB [512]"            && CT_MEMORY="${answer:-512}"
question "CPU cores [1]"                 && CT_CORES="${answer:-1}"
question "Disk size in GB [8]"           && CT_DISK="${answer:-8}"

# PostgreSQL configuration
question "PostgreSQL port [5432]"        && PG_PORT="${answer:-5432}"
question "Database name [app]"           && PG_DB="${answer:-app}"
question "Database user [appuser]"       && PG_USER="${answer:-appuser}"
question "Database user password"        && PG_PASSWORD="$answer"

if [[ -z "$PG_PASSWORD" ]]; then
    error "Database user password is required."
    exit 1
fi

# ─── Container Creation ───────────────────────────────────────────────────────

info "Creating container for PostgreSQL..."

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

info "Installing and configuring PostgreSQL..."

CONTAINER_SCRIPT
#!/bin/bash
source <(wget -qO- https://raw.githubusercontent.com/rmayobre/shtuff/main/shtuff-remote.sh)

update &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Updating packages" \
    --success_msg "Packages updated" --error_msg "Package update failed" || exit 1

install postgresql postgresql-contrib &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing PostgreSQL" \
    --success_msg "PostgreSQL installed" --error_msg "PostgreSQL installation failed" || exit 1

systemctl enable --now postgresql &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Starting PostgreSQL service" \
    --success_msg "PostgreSQL service started" --error_msg "Failed to start PostgreSQL service" || exit 1

su -c "psql -c \"CREATE USER ${PG_USER} WITH PASSWORD '${PG_PASSWORD}'; CREATE DATABASE ${PG_DB} OWNER ${PG_USER};\"" postgres &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Creating database '${PG_DB}' and user '${PG_USER}'" \
    --success_msg "Database and user created" --error_msg "Failed to create database and user" || exit 1

if [[ "${PG_PORT}" != "5432" ]]; then
    sed -i "s/^#port = 5432/port = ${PG_PORT}/" /etc/postgresql/*/main/postgresql.conf \
        || { error "Failed to write port configuration"; exit 1; }
    systemctl restart postgresql &
    monitor $! --style "$SPINNER_LOADING_STYLE" --message "Restarting PostgreSQL" \
        --success_msg "PostgreSQL restarted" --error_msg "Failed to restart PostgreSQL" || exit 1
fi
CONTAINER_SCRIPT_EOD

container shell-script --name "$CT_NAME" --path /opt/postgres-setup.sh \
    --env "PG_USER=$PG_USER" \
    --env "PG_PASSWORD=$PG_PASSWORD" \
    --env "PG_DB=$PG_DB" \
    --env "PG_PORT=$PG_PORT" \
    --env "SPINNER_LOADING_STYLE=$SPINNER_LOADING_STYLE" \
    --style "$SPINNER_LOADING_STYLE" &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Deploying PostgreSQL setup script" \
    --success_msg "Setup script deployed" --error_msg "Setup script deployment failed" || exit 1

container exec --name "$CT_NAME" -- /opt/postgres-setup.sh &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing and configuring PostgreSQL" \
    --success_msg "PostgreSQL ready" --error_msg "PostgreSQL setup failed" || exit 1

# ─── Host Cleanup ─────────────────────────────────────────────────────────────

clean &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Cleaning up" \
    --success_msg "Cleanup complete" --error_msg "Cleanup failed"

info "PostgreSQL installed successfully in container '$CT_NAME'!"
info "  Database : $PG_DB"
info "  User     : $PG_USER"
info "  Port     : $PG_PORT"
