#!/bin/bash
source <(curl -sL https://raw.githubusercontent.com/rmayobre/shtuff/main/shtuff-remote.sh)

# ─── User Configuration ───────────────────────────────────────────────────────

info "Configuring MySQL installation..."

# Container configuration
question "Container name [mysql]"     && CT_NAME="${answer:-mysql}"
question "Container hostname [mysql]" && CT_HOSTNAME="${answer:-mysql}"
question "Memory in MB [512]"         && CT_MEMORY="${answer:-512}"
question "CPU cores [1]"              && CT_CORES="${answer:-1}"
question "Disk size in GB [8]"        && CT_DISK="${answer:-8}"

# MySQL configuration
question "MySQL port [3306]"          && DB_PORT="${answer:-3306}"
question "Root password"              && DB_ROOT_PASSWORD="$answer"

if [[ -z "$DB_ROOT_PASSWORD" ]]; then
    error "Root password is required."
    exit 1
fi

question "Database name (leave blank to skip)" && DB_NAME="$answer"

if [[ -n "$DB_NAME" ]]; then
    question "Database user"              && DB_USER="$answer"
    question "Database user password"     && DB_USER_PASSWORD="$answer"

    if [[ -z "$DB_USER" || -z "$DB_USER_PASSWORD" ]]; then
        error "Database user and password are required when creating a database."
        exit 1
    fi
fi

# ─── Container Creation ───────────────────────────────────────────────────────

info "Creating container for MySQL..."

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

info "Installing and configuring MySQL..."

CONTAINER_SCRIPT
#!/bin/bash
source <(wget -qO- https://raw.githubusercontent.com/rmayobre/shtuff/main/shtuff-remote.sh)

update &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Updating packages" \
    --success_msg "Packages updated" --error_msg "Package update failed" || exit 1

echo "mysql-server mysql-server/root_password password ${DB_ROOT_PASSWORD}" | debconf-set-selections \
    || { error "Failed to pre-configure MySQL root password"; exit 1; }
echo "mysql-server mysql-server/root_password_again password ${DB_ROOT_PASSWORD}" | debconf-set-selections \
    || { error "Failed to pre-configure MySQL root password confirmation"; exit 1; }

install mysql-server &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing MySQL" \
    --success_msg "MySQL installed" --error_msg "MySQL installation failed" || exit 1

systemctl enable --now mysql &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Starting MySQL service" \
    --success_msg "MySQL service started" --error_msg "Failed to start MySQL service" || exit 1

mysql -u root -p'${DB_ROOT_PASSWORD}' -e "DELETE FROM mysql.user WHERE User=''; DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1'); DROP DATABASE IF EXISTS test; DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%'; FLUSH PRIVILEGES;" &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Securing MySQL" \
    --success_msg "MySQL secured" --error_msg "Failed to secure MySQL" || exit 1

if [[ "${DB_PORT}" != "3306" ]]; then
    echo -e '[mysqld]\nport = ${DB_PORT}' >> /etc/mysql/mysql.conf.d/mysqld.cnf \
        || { error "Failed to write port configuration"; exit 1; }
    systemctl restart mysql &
    monitor $! --style "$SPINNER_LOADING_STYLE" --message "Restarting MySQL" \
        --success_msg "MySQL restarted" --error_msg "Failed to restart MySQL" || exit 1
fi

if [[ -n "${DB_NAME}" ]]; then
    mysql -u root -p'${DB_ROOT_PASSWORD}' -e "CREATE DATABASE \`${DB_NAME}\`; CREATE USER '${DB_USER}'@'%' IDENTIFIED BY '${DB_USER_PASSWORD}'; GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'%'; FLUSH PRIVILEGES;" &
    monitor $! --style "$SPINNER_LOADING_STYLE" --message "Creating database '${DB_NAME}' and user '${DB_USER}'" \
        --success_msg "Database and user created" --error_msg "Failed to create database and user" || exit 1
fi
CONTAINER_SCRIPT_EOD

container shell-script --name "$CT_NAME" --path /opt/mysql-setup.sh \
    --env "DB_ROOT_PASSWORD=$DB_ROOT_PASSWORD" \
    --env "DB_PORT=$DB_PORT" \
    --env "DB_NAME=$DB_NAME" \
    --env "DB_USER=$DB_USER" \
    --env "DB_USER_PASSWORD=$DB_USER_PASSWORD" \
    --env "SPINNER_LOADING_STYLE=$SPINNER_LOADING_STYLE" \
    --style "$SPINNER_LOADING_STYLE" &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Deploying MySQL setup script" \
    --success_msg "Setup script deployed" --error_msg "Setup script deployment failed" || exit 1

container exec --name "$CT_NAME" -- /opt/mysql-setup.sh &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing and configuring MySQL" \
    --success_msg "MySQL ready" --error_msg "MySQL setup failed" || exit 1

# ─── Host Cleanup ─────────────────────────────────────────────────────────────

clean &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Cleaning up" \
    --success_msg "Cleanup complete" --error_msg "Cleanup failed"

info "MySQL installed successfully in container '$CT_NAME'!"
info "  Port : $DB_PORT"
if [[ -n "$DB_NAME" ]]; then
    info "  Database : $DB_NAME"
    info "  User     : $DB_USER"
fi
