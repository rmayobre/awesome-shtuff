#!/bin/bash
source <(curl -sL https://raw.githubusercontent.com/rmayobre/shtuff/main/shtuff-remote.sh)

# ─── User Configuration ───────────────────────────────────────────────────────

info "Configuring pgAdmin installation..."

# Container configuration
question "Container name [pgadmin]"     && CT_NAME="${answer:-pgadmin}"
question "Container hostname [pgadmin]" && CT_HOSTNAME="${answer:-pgadmin}"
question "Memory in MB [512]"           && CT_MEMORY="${answer:-512}"
question "CPU cores [1]"                && CT_CORES="${answer:-1}"
question "Disk size in GB [8]"          && CT_DISK="${answer:-8}"

# pgAdmin configuration
question "pgAdmin web port [80]"  && PGADMIN_PORT="${answer:-80}"
question "pgAdmin admin email"    && PGADMIN_EMAIL="$answer"
question "pgAdmin admin password" && PGADMIN_PASSWORD="$answer"

if [[ -z "$PGADMIN_EMAIL" || -z "$PGADMIN_PASSWORD" ]]; then
    error "pgAdmin admin email and password are required."
    exit 1
fi

# PostgreSQL database connection
options "Is the PostgreSQL database local or remote?" \
    --choice "local" \
    --choice "remote" \
    && DB_MODE="$answer"

if [[ "$DB_MODE" == "local" ]]; then
    DB_HOST="127.0.0.1"

    question "PostgreSQL root password" && DB_ROOT_PASSWORD="$answer"

    if [[ -z "$DB_ROOT_PASSWORD" ]]; then
        error "PostgreSQL root password is required for a local database."
        exit 1
    fi
else
    question "Remote PostgreSQL host (IP address)" && DB_HOST="$answer"

    if [[ -z "$DB_HOST" ]]; then
        error "Remote PostgreSQL host is required."
        exit 1
    fi
fi

question "PostgreSQL port [5432]"                     && DB_PORT="${answer:-5432}"
question "PostgreSQL maintenance database [postgres]" && DB_NAME="${answer:-postgres}"
question "PostgreSQL username [postgres]"             && DB_USER="${answer:-postgres}"

# ─── Container Creation ───────────────────────────────────────────────────────

info "Creating container for pgAdmin..."

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

info "Installing and configuring pgAdmin..."

CONTAINER_SCRIPT
#!/bin/bash
source <(wget -qO- https://raw.githubusercontent.com/rmayobre/shtuff/main/shtuff-remote.sh)

update &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Updating packages" \
    --success_msg "Packages updated" --error_msg "Package update failed" || exit 1

install curl ca-certificates gnupg lsb-release apache2 &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing dependencies" \
    --success_msg "Dependencies installed" --error_msg "Dependency installation failed" || exit 1

if [[ "${DB_MODE}" == "local" ]]; then
    install postgresql postgresql-contrib &
    monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing PostgreSQL" \
        --success_msg "PostgreSQL installed" --error_msg "PostgreSQL installation failed" || exit 1

    systemctl enable --now postgresql &
    monitor $! --style "$SPINNER_LOADING_STYLE" --message "Starting PostgreSQL service" \
        --success_msg "PostgreSQL service started" --error_msg "Failed to start PostgreSQL service" || exit 1

    su -c "psql -c \"ALTER USER ${DB_USER} WITH PASSWORD '${DB_ROOT_PASSWORD}';\"" postgres &
    monitor $! --style "$SPINNER_LOADING_STYLE" --message "Setting PostgreSQL '${DB_USER}' password" \
        --success_msg "PostgreSQL password set" --error_msg "Failed to set PostgreSQL password" || exit 1

    if [[ "${DB_PORT}" != "5432" ]]; then
        sed -i "s/^#port = 5432/port = ${DB_PORT}/" /etc/postgresql/*/main/postgresql.conf \
            || { error "Failed to write port configuration"; exit 1; }
        systemctl restart postgresql &
        monitor $! --style "$SPINNER_LOADING_STYLE" --message "Restarting PostgreSQL" \
            --success_msg "PostgreSQL restarted" --error_msg "Failed to restart PostgreSQL" || exit 1
    fi
fi

(curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/postgresql.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
    && apt-get update -qq) &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Adding PostgreSQL APT repository" \
    --success_msg "PostgreSQL APT repository added" --error_msg "Failed to add PostgreSQL APT repository" || exit 1

install pgadmin4-web &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing pgAdmin4" \
    --success_msg "pgAdmin4 installed" --error_msg "pgAdmin4 installation failed" || exit 1

PGADMIN_SETUP_EMAIL="${PGADMIN_EMAIL}" PGADMIN_SETUP_PASSWORD="${PGADMIN_PASSWORD}" /usr/pgadmin4/bin/setup-web.sh --yes &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Configuring pgAdmin4" \
    --success_msg "pgAdmin4 configured" --error_msg "pgAdmin4 configuration failed" || exit 1

if [[ "${PGADMIN_PORT}" != "80" ]]; then
    sed -i "s/^Listen 80/Listen ${PGADMIN_PORT}/" /etc/apache2/ports.conf \
        || { error "Failed to write Apache port configuration"; exit 1; }
    sed -i "s/<VirtualHost \*:80>/<VirtualHost *:${PGADMIN_PORT}>/" /etc/apache2/sites-enabled/000-default.conf \
        || { error "Failed to write Apache virtual host configuration"; exit 1; }
fi

systemctl restart apache2 &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Restarting Apache" \
    --success_msg "Apache restarted" --error_msg "Failed to restart Apache" || exit 1

cat > /opt/pgadmin-servers.json <<EOF
{
    "Servers": {
        "1": {
            "Name": "PostgreSQL",
            "Group": "Servers",
            "Host": "${DB_HOST}",
            "Port": ${DB_PORT},
            "MaintenanceDB": "${DB_NAME}",
            "Username": "${DB_USER}",
            "SSLMode": "prefer"
        }
    }
}
EOF

/usr/pgadmin4/venv/bin/python3 /usr/pgadmin4/web/setup.py load_servers /opt/pgadmin-servers.json --user "${PGADMIN_EMAIL}" &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Registering PostgreSQL server in pgAdmin" \
    --success_msg "PostgreSQL server registered" --error_msg "Failed to register PostgreSQL server (add it manually in pgAdmin)"
CONTAINER_SCRIPT_EOD

container shell-script --name "$CT_NAME" --path /opt/pgadmin-setup.sh \
    --env "DB_MODE=$DB_MODE" \
    --env "DB_HOST=$DB_HOST" \
    --env "DB_PORT=$DB_PORT" \
    --env "DB_NAME=$DB_NAME" \
    --env "DB_USER=$DB_USER" \
    --env "DB_ROOT_PASSWORD=$DB_ROOT_PASSWORD" \
    --env "PGADMIN_PORT=$PGADMIN_PORT" \
    --env "PGADMIN_EMAIL=$PGADMIN_EMAIL" \
    --env "PGADMIN_PASSWORD=$PGADMIN_PASSWORD" \
    --env "SPINNER_LOADING_STYLE=$SPINNER_LOADING_STYLE" \
    --style "$SPINNER_LOADING_STYLE" &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Deploying pgAdmin setup script" \
    --success_msg "Setup script deployed" --error_msg "Setup script deployment failed" || exit 1

container exec --name "$CT_NAME" -- /opt/pgadmin-setup.sh &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing and configuring pgAdmin" \
    --success_msg "pgAdmin ready" --error_msg "pgAdmin setup failed" || exit 1

# ─── Host Cleanup ─────────────────────────────────────────────────────────────

clean &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Cleaning up" \
    --success_msg "Cleanup complete" --error_msg "Cleanup failed"

info "pgAdmin installed successfully in container '$CT_NAME'!"
info "  Web UI : http://<container-ip>:$PGADMIN_PORT"
info "  Login  : $PGADMIN_EMAIL"
if [[ "$DB_MODE" == "local" ]]; then
    info "  Database: local PostgreSQL ($DB_HOST:$DB_PORT)"
else
    info "  Database: remote PostgreSQL ($DB_HOST:$DB_PORT)"
fi
