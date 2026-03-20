#!/bin/bash
source <(curl -sL https://raw.githubusercontent.com/rmayobre/shtuff/v1.2.0/shtuff-remote.sh)

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

container exec --name "$CT_NAME" -- apt-get update -qq &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Updating packages in container" \
    --success_msg "Packages updated" --error_msg "Package update failed" || exit 1

container exec --name "$CT_NAME" -- apt-get install -y postgresql postgresql-contrib &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing PostgreSQL" \
    --success_msg "PostgreSQL installed" --error_msg "PostgreSQL installation failed" || exit 1

# ─── PostgreSQL Configuration ─────────────────────────────────────────────────

info "Configuring PostgreSQL..."

# Enable and start the service
container exec --name "$CT_NAME" -- systemctl enable --now postgresql &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Starting PostgreSQL service" \
    --success_msg "PostgreSQL service started" --error_msg "Failed to start PostgreSQL service" || exit 1

# Create database user
container exec --name "$CT_NAME" -- \
    su -c "psql -c \"CREATE USER ${PG_USER} WITH PASSWORD '${PG_PASSWORD}';\"" postgres &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Creating database user '${PG_USER}'" \
    --success_msg "Database user created" --error_msg "Failed to create database user" || exit 1

# Create database
container exec --name "$CT_NAME" -- \
    su -c "psql -c \"CREATE DATABASE ${PG_DB} OWNER ${PG_USER};\"" postgres &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Creating database '${PG_DB}'" \
    --success_msg "Database created" --error_msg "Failed to create database" || exit 1

# Update PostgreSQL to listen on the configured port (if non-default)
if [[ "$PG_PORT" != "5432" ]]; then
    container exec --name "$CT_NAME" -- \
        bash -c "sed -i \"s/^#port = 5432/port = ${PG_PORT}/\" /etc/postgresql/*/main/postgresql.conf" &
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
