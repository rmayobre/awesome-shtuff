#!/bin/bash
source <(curl -sL https://raw.githubusercontent.com/rmayobre/shtuff/main/shtuff-remote.sh)

# ─── User Configuration ───────────────────────────────────────────────────────

info "Configuring phpMyAdmin installation..."

# Distribution
options "Select distribution" \
    --choice "debian" \
    --choice "ubuntu" \
    && CT_DIST="$answer"

case "$CT_DIST" in
    debian)
        options "Select Debian release" \
            --choice "bullseye" \
            --choice "bookworm" \
            && CT_RELEASE="$answer"
        ;;
    ubuntu)
        options "Select Ubuntu release" \
            --choice "focal" \
            --choice "jammy" \
            --choice "noble" \
            && CT_RELEASE="$answer"
        ;;
esac

# Container configuration
question "Container name [phpmyadmin]"     && CT_NAME="${answer:-phpmyadmin}"
question "Container hostname [phpmyadmin]" && CT_HOSTNAME="${answer:-phpmyadmin}"
question "Memory in MB [512]"              && CT_MEMORY="${answer:-512}"
question "CPU cores [1]"                   && CT_CORES="${answer:-1}"
question "Disk size in GB [8]"             && CT_DISK="${answer:-8}"

# phpMyAdmin configuration
question "phpMyAdmin web port [80]" && PMA_PORT="${answer:-80}"

# MySQL/MariaDB database connection
options "Is the MySQL/MariaDB database local or remote?" \
    --choice "local" \
    --choice "remote" \
    && DB_MODE="$answer"

if [[ "$DB_MODE" == "local" ]]; then
    DB_HOST="127.0.0.1"

    question "MariaDB root password" && DB_ROOT_PASSWORD="$answer"

    if [[ -z "$DB_ROOT_PASSWORD" ]]; then
        error "MariaDB root password is required for a local database."
        exit 1
    fi
else
    question "Remote MySQL/MariaDB host (IP address)" && DB_HOST="$answer"

    if [[ -z "$DB_HOST" ]]; then
        error "Remote database host is required."
        exit 1
    fi

    question "Remote database root/admin password (used by phpMyAdmin's setup)" && DB_ROOT_PASSWORD="$answer"

    if [[ -z "$DB_ROOT_PASSWORD" ]]; then
        error "Remote database root/admin password is required."
        exit 1
    fi
fi

question "MySQL/MariaDB port [3306]" && DB_PORT="${answer:-3306}"

# ─── Container Creation ───────────────────────────────────────────────────────

info "Creating container for phpMyAdmin..."

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

info "Installing and configuring phpMyAdmin..."

CONTAINER_SCRIPT
#!/bin/bash
source <(wget -qO- https://raw.githubusercontent.com/rmayobre/shtuff/main/shtuff-remote.sh)

update --style "$SPINNER_LOADING_STYLE" --message "Updating packages" \
    --success_msg "Packages updated" --error_msg "Package update failed" || exit 1

install apache2 php php-mbstring php-zip php-curl php-mysqli libapache2-mod-php --style "$SPINNER_LOADING_STYLE" --message "Installing web stack" \
    --success_msg "Web stack installed" --error_msg "Web stack installation failed" || exit 1

if [[ "${DB_MODE}" == "local" ]]; then
    install mariadb-server --style "$SPINNER_LOADING_STYLE" --message "Installing MariaDB" \
        --success_msg "MariaDB installed" --error_msg "MariaDB installation failed" || exit 1

    systemctl enable --now mariadb &
    monitor $! --style "$SPINNER_LOADING_STYLE" --message "Starting MariaDB service" \
        --success_msg "MariaDB service started" --error_msg "Failed to start MariaDB service" || exit 1

    mariadb -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASSWORD}'; DELETE FROM mysql.user WHERE User=''; DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1'); DROP DATABASE IF EXISTS test; DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%'; FLUSH PRIVILEGES;" &
    monitor $! --style "$SPINNER_LOADING_STYLE" --message "Securing MariaDB" \
        --success_msg "MariaDB secured" --error_msg "Failed to secure MariaDB" || exit 1

    if [[ "${DB_PORT}" != "3306" ]]; then
        echo -e "[mysqld]\nport = ${DB_PORT}" >> /etc/mysql/mariadb.conf.d/50-server.cnf \
            || { error "Failed to write port configuration"; exit 1; }
        systemctl restart mariadb &
        monitor $! --style "$SPINNER_LOADING_STYLE" --message "Restarting MariaDB" \
            --success_msg "MariaDB restarted" --error_msg "Failed to restart MariaDB" || exit 1
    fi
fi

PMA_CONTROL_PASS=$(openssl rand -hex 16)

if [[ "${DB_MODE}" == "local" ]]; then
    PMA_DBCONFIG="true"
else
    PMA_DBCONFIG="false"
fi

debconf-set-selections <<EOF
phpmyadmin phpmyadmin/dbconfig-install boolean ${PMA_DBCONFIG}
phpmyadmin phpmyadmin/mysql/admin-pass password ${DB_ROOT_PASSWORD}
phpmyadmin phpmyadmin/mysql/app-pass password ${PMA_CONTROL_PASS}
phpmyadmin phpmyadmin/app-password-confirm password ${PMA_CONTROL_PASS}
phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2
EOF

DEBIAN_FRONTEND=noninteractive apt-get install -y phpmyadmin &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing phpMyAdmin" \
    --success_msg "phpMyAdmin installed" --error_msg "phpMyAdmin installation failed" || exit 1

cat >> /etc/phpmyadmin/config.inc.php <<EOF

\$cfg['Servers'][\$i]['host'] = '${DB_HOST}';
\$cfg['Servers'][\$i]['port'] = '${DB_PORT}';
EOF

if [[ "${PMA_PORT}" != "80" ]]; then
    sed -i "s/^Listen 80/Listen ${PMA_PORT}/" /etc/apache2/ports.conf \
        || { error "Failed to write Apache port configuration"; exit 1; }
    sed -i "s/<VirtualHost \*:80>/<VirtualHost *:${PMA_PORT}>/" /etc/apache2/sites-enabled/000-default.conf \
        || { error "Failed to write Apache virtual host configuration"; exit 1; }
fi

systemctl restart apache2 &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Restarting Apache" \
    --success_msg "Apache restarted" --error_msg "Failed to restart Apache" || exit 1
CONTAINER_SCRIPT_EOD

container shell-script --name "$CT_NAME" --path /opt/phpmyadmin-setup.sh \
    --env "DB_MODE=$DB_MODE" \
    --env "DB_HOST=$DB_HOST" \
    --env "DB_PORT=$DB_PORT" \
    --env "DB_ROOT_PASSWORD=$DB_ROOT_PASSWORD" \
    --env "PMA_PORT=$PMA_PORT" \
    --env "SPINNER_LOADING_STYLE=$SPINNER_LOADING_STYLE" \
    --style "$SPINNER_LOADING_STYLE" &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Deploying phpMyAdmin setup script" \
    --success_msg "Setup script deployed" --error_msg "Setup script deployment failed" || exit 1

container exec --name "$CT_NAME" -- /opt/phpmyadmin-setup.sh &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing and configuring phpMyAdmin" \
    --success_msg "phpMyAdmin ready" --error_msg "phpMyAdmin setup failed" || exit 1

# ─── Host Cleanup ─────────────────────────────────────────────────────────────

clean --style "$SPINNER_LOADING_STYLE" --message "Cleaning up" \
    --success_msg "Cleanup complete" --error_msg "Cleanup failed"

info "phpMyAdmin installed successfully in container '$CT_NAME'!"
info "  Web UI : http://<container-ip>:$PMA_PORT"
if [[ "$DB_MODE" == "local" ]]; then
    info "  Database: local MariaDB ($DB_HOST:$DB_PORT)"
else
    info "  Database: remote MySQL/MariaDB ($DB_HOST:$DB_PORT)"
fi
