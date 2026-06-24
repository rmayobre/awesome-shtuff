#!/bin/bash
source <(curl -sL https://raw.githubusercontent.com/rmayobre/shtuff/main/shtuff-remote.sh)

# ─── User Configuration ───────────────────────────────────────────────────────

info "Configuring MySQL installation..."

# Distribution
options "Select distribution" \
    --choice "debian" \
    --choice "ubuntu" \
    && CT_DIST="$answer"

case "$CT_DIST" in
    debian)
        options "Select Debian release" \
            --choice "bookworm" \
            --choice "trixie" \
            && CT_RELEASE="$answer"
        ;;
    ubuntu)
        options "Select Ubuntu release" \
            --choice "jammy" \
            --choice "noble" \
            --choice "oracular" \
            && CT_RELEASE="$answer"
        ;;
esac

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
    --dist "$CT_DIST" \
    --release "$CT_RELEASE" \
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

locale "en_US.UTF-8" &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Configuring locale" \
    --success_msg "Locale configured" --error_msg "Failed to configure locale" || exit 1

update &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Updating packages" \
    --success_msg "Packages updated" --error_msg "Package update failed" || exit 1

install gnupg lsb-release apt-transport-https ca-certificates &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing prerequisites" \
    --success_msg "Prerequisites installed" --error_msg "Failed to install prerequisites" || exit 1

mkdir -p /etc/apt/keyrings
gpg --keyserver keyserver.ubuntu.com --recv-keys B7B3B788A8D3785C &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Importing MySQL GPG key" \
    --success_msg "MySQL GPG key imported" --error_msg "Failed to import MySQL GPG key" || exit 1

gpg --export B7B3B788A8D3785C > /etc/apt/keyrings/mysql.gpg

echo "deb [signed-by=/etc/apt/keyrings/mysql.gpg] http://repo.mysql.com/apt/${CT_DIST} ${CT_RELEASE} mysql-8.0" \
    > /etc/apt/sources.list.d/mysql.list

update &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Updating package lists with MySQL repo" \
    --success_msg "Package lists updated" --error_msg "Package list update failed" || exit 1

debconf-set-selections <<< "mysql-community-server mysql-community-server/root-pass password ${DB_ROOT_PASSWORD}"
debconf-set-selections <<< "mysql-community-server mysql-community-server/re-root-pass password ${DB_ROOT_PASSWORD}"

DEBIAN_FRONTEND=noninteractive install mysql-server &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing MySQL" \
    --success_msg "MySQL installed" --error_msg "MySQL installation failed" || exit 1

if [[ "${DB_PORT}" != "3306" ]]; then
    if grep -q '^\s*#*\s*port\s*=' /etc/mysql/mysql.conf.d/mysqld.cnf; then
        sed -i "s|^\s*#*\s*port\s*=.*|port = ${DB_PORT}|" /etc/mysql/mysql.conf.d/mysqld.cnf
    else
        sed -i "/^\[mysqld\]/a port = ${DB_PORT}" /etc/mysql/mysql.conf.d/mysqld.cnf
    fi
fi

systemctl enable --now mysql &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Starting MySQL service" \
    --success_msg "MySQL service started" --error_msg "Failed to start MySQL service" || exit 1

mysql -u root -p"${DB_ROOT_PASSWORD}" -e "DELETE FROM mysql.user WHERE User=''; DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1'); DROP DATABASE IF EXISTS test; DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%'; FLUSH PRIVILEGES;" &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Securing MySQL" \
    --success_msg "MySQL secured" --error_msg "Failed to secure MySQL" || exit 1

if [[ -n "${DB_NAME}" ]]; then
    mysql -u root -p"${DB_ROOT_PASSWORD}" -e "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`; CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_USER_PASSWORD}'; GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'%' WITH GRANT OPTION; FLUSH PRIVILEGES;" &
    monitor $! --style "$SPINNER_LOADING_STYLE" --message "Creating database '${DB_NAME}' and user '${DB_USER}'" \
        --success_msg "Database and user created" --error_msg "Failed to create database and user" || exit 1
fi
CONTAINER_SCRIPT_EOD

container shell-script --name "$CT_NAME" --path /opt/mysql-setup.sh \
    --env "CT_DIST=$CT_DIST" \
    --env "CT_RELEASE=$CT_RELEASE" \
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
