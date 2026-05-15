#!/bin/bash
source <(curl -sL https://raw.githubusercontent.com/rmayobre/shtuff/v1.3.0-beta/shtuff-remote.sh)
shopt -s expand_aliases

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

# ─── Dependencies Inside Container ────────────────────────────────────────────

CONTAINER_SCRIPT
#!/bin/bash
apt-get update -qq
apt-get install -y postgresql postgresql-contrib
CONTAINER_SCRIPT_EOD

container shell-script --name "$CT_NAME" --path /opt/postgres-deps.sh \
    --style "$SPINNER_LOADING_STYLE" &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Deploying PostgreSQL dependency script" \
    --success_msg "Dependency script deployed" --error_msg "Dependency script deployment failed" || exit 1

container exec --name "$CT_NAME" -- /opt/postgres-deps.sh &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing PostgreSQL" \
    --success_msg "PostgreSQL installed" --error_msg "PostgreSQL installation failed" || exit 1

# ─── PostgreSQL Configuration ─────────────────────────────────────────────────

info "Configuring PostgreSQL..."

# Enable and start the service
container exec --name "$CT_NAME" -- systemctl enable --now postgresql &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Starting PostgreSQL service" \
    --success_msg "PostgreSQL service started" --error_msg "Failed to start PostgreSQL service" || exit 1

# Create database user and database
CONTAINER_SCRIPT
#!/bin/bash
su -c "psql -c \"CREATE USER ${PG_USER} WITH PASSWORD '${PG_PASSWORD}';\"" postgres
su -c "psql -c \"CREATE DATABASE ${PG_DB} OWNER ${PG_USER};\"" postgres
CONTAINER_SCRIPT_EOD

container shell-script --name "$CT_NAME" --path /opt/postgres-setup.sh \
    --style "$SPINNER_LOADING_STYLE" &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Deploying database setup script" \
    --success_msg "Setup script deployed" --error_msg "Setup script deployment failed" || exit 1

container exec --name "$CT_NAME" -- /opt/postgres-setup.sh &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Creating database '${PG_DB}' and user '${PG_USER}'" \
    --success_msg "Database and user created" --error_msg "Failed to create database and user" || exit 1

# Update PostgreSQL to listen on the configured port (if non-default)
if [[ "$PG_PORT" != "5432" ]]; then
    CONTAINER_SCRIPT
#!/bin/bash
sed -i "s/^#port = 5432/port = ${PG_PORT}/" /etc/postgresql/*/main/postgresql.conf
CONTAINER_SCRIPT_EOD

    container shell-script --name "$CT_NAME" --path /opt/postgres-port.sh \
        --style "$SPINNER_LOADING_STYLE" &
    monitor $! --style "$SPINNER_LOADING_STYLE" --message "Deploying port configuration script" \
        --success_msg "Port configuration script deployed" --error_msg "Port configuration script deployment failed" || exit 1

    container exec --name "$CT_NAME" -- /opt/postgres-port.sh &
    monitor $! --style "$SPINNER_LOADING_STYLE" --message "Configuring PostgreSQL port" \
        --success_msg "Port configured" --error_msg "Failed to configure port" || exit 1

    container exec --name "$CT_NAME" -- systemctl restart postgresql &
    monitor $! --style "$SPINNER_LOADING_STYLE" --message "Restarting PostgreSQL" \
        --success_msg "PostgreSQL restarted" --error_msg "Failed to restart PostgreSQL" || exit 1
fi

# ─── Host Cleanup ─────────────────────────────────────────────────────────────

clean &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Cleaning up" \
    --success_msg "Cleanup complete" --error_msg "Cleanup failed"

info "PostgreSQL installed successfully in container '$CT_NAME'!"
info "  Database : $PG_DB"
info "  User     : $PG_USER"
info "  Port     : $PG_PORT"
