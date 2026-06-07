#!/bin/bash
source <(curl -sL https://raw.githubusercontent.com/rmayobre/shtuff/main/shtuff-remote.sh)
shopt -s expand_aliases

# ─── User Configuration ───────────────────────────────────────────────────────

info "Configuring MariaDB installation..."

# Container configuration
question "Container name [mariadb]"     && CT_NAME="${answer:-mariadb}"
question "Container hostname [mariadb]" && CT_HOSTNAME="${answer:-mariadb}"
question "Memory in MB [512]"           && CT_MEMORY="${answer:-512}"
question "CPU cores [1]"                && CT_CORES="${answer:-1}"
question "Disk size in GB [8]"          && CT_DISK="${answer:-8}"

# MariaDB configuration
question "MariaDB port [3306]"          && DB_PORT="${answer:-3306}"
question "Root password"                && DB_ROOT_PASSWORD="$answer"

if [[ -z "$DB_ROOT_PASSWORD" ]]; then
    error "Root password is required."
    exit 1
fi

question "Database name (leave blank to skip)" && DB_NAME="$answer"

if [[ -n "$DB_NAME" ]]; then
    question "Database user"   && DB_USER="$answer"
    question "Database user password" && DB_USER_PASSWORD="$answer"

    if [[ -z "$DB_USER" || -z "$DB_USER_PASSWORD" ]]; then
        error "Database user and password are required when creating a database."
        exit 1
    fi
fi

# ─── Container Creation ───────────────────────────────────────────────────────

info "Creating container for MariaDB..."

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

info "Installing and configuring MariaDB..."

CONTAINER_SCRIPT
#!/bin/bash
source <(wget -qO- https://raw.githubusercontent.com/rmayobre/shtuff/main/shtuff-remote.sh)

update &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Updating packages" \
    --success_msg "Packages updated" --error_msg "Package update failed" || exit 1

install mariadb-server &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing MariaDB" \
    --success_msg "MariaDB installed" --error_msg "MariaDB installation failed" || exit 1

systemctl enable --now mariadb &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Starting MariaDB service" \
    --success_msg "MariaDB service started" --error_msg "Failed to start MariaDB service" || exit 1

mariadb -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASSWORD}'; DELETE FROM mysql.user WHERE User=''; DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1'); DROP DATABASE IF EXISTS test; DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%'; FLUSH PRIVILEGES;" &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Securing MariaDB" \
    --success_msg "MariaDB secured" --error_msg "Failed to secure MariaDB" || exit 1

if [[ "${DB_PORT}" != "3306" ]]; then
    echo -e '[mysqld]\nport = ${DB_PORT}' >> /etc/mysql/mariadb.conf.d/50-server.cnf \
        || { error "Failed to write port configuration"; exit 1; }
    systemctl restart mariadb &
    monitor $! --style "$SPINNER_LOADING_STYLE" --message "Restarting MariaDB" \
        --success_msg "MariaDB restarted" --error_msg "Failed to restart MariaDB" || exit 1
fi

if [[ -n "${DB_NAME}" ]]; then
    mariadb -u root -p'${DB_ROOT_PASSWORD}' -e "CREATE DATABASE \`${DB_NAME}\`; CREATE USER '${DB_USER}'@'%' IDENTIFIED BY '${DB_USER_PASSWORD}'; GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'%'; FLUSH PRIVILEGES;" &
    monitor $! --style "$SPINNER_LOADING_STYLE" --message "Creating database '${DB_NAME}' and user '${DB_USER}'" \
        --success_msg "Database and user created" --error_msg "Failed to create database and user" || exit 1
fi
CONTAINER_SCRIPT_EOD

container shell-script --name "$CT_NAME" --path /opt/mariadb-setup.sh \
    --style "$SPINNER_LOADING_STYLE" &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Deploying MariaDB setup script" \
    --success_msg "Setup script deployed" --error_msg "Setup script deployment failed" || exit 1

container exec --name "$CT_NAME" -- /opt/mariadb-setup.sh &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing and configuring MariaDB" \
    --success_msg "MariaDB ready" --error_msg "MariaDB setup failed" || exit 1

# ─── Host Cleanup ─────────────────────────────────────────────────────────────

clean &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Cleaning up" \
    --success_msg "Cleanup complete" --error_msg "Cleanup failed"

info "MariaDB installed successfully in container '$CT_NAME'!"
info "  Port : $DB_PORT"
if [[ -n "$DB_NAME" ]]; then
    info "  Database : $DB_NAME"
    info "  User     : $DB_USER"
fi
