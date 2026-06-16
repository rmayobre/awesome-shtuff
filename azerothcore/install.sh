#!/bin/bash
source <(curl -sL https://raw.githubusercontent.com/rmayobre/shtuff/main/shtuff-remote.sh)

# ─── User Configuration ───────────────────────────────────────────────────────

info "Configuring AzerothCore installation..."

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
# Elevated defaults: clang build requires 4 GB+ RAM and ~40 GB disk (source + build + client data)
question "Container name [azerothcore]"     && CT_NAME="${answer:-azerothcore}"
question "Container hostname [azerothcore]" && CT_HOSTNAME="${answer:-azerothcore}"
question "Memory in MB [4096]"              && CT_MEMORY="${answer:-4096}"
question "CPU cores [4]"                    && CT_CORES="${answer:-4}"
question "Disk size in GB [40]"             && CT_DISK="${answer:-40}"

# Server ports
question "Auth server port [3724]"          && AUTH_PORT="${answer:-3724}"
question "World server port [8085]"         && WORLD_PORT="${answer:-8085}"

# Database setup
options "Database setup" \
    --choice "local" \
    --choice "remote" \
    && DB_MODE="$answer"

if [[ "$DB_MODE" == "local" ]]; then
    DB_HOST="127.0.0.1"
    question "Database port [3306]"             && DB_PORT="${answer:-3306}"
    question "MySQL root password"              && DB_ROOT_PASSWORD="$answer"

    if [[ -z "$DB_ROOT_PASSWORD" ]]; then
        error "MySQL root password is required for a local database."
        exit 1
    fi

    question "AzerothCore DB user [acore]"      && DB_USER="${answer:-acore}"
    question "AzerothCore DB password [acore]"  && DB_PASS="${answer:-acore}"
else
    question "Remote database host"             && DB_HOST="$answer"

    if [[ -z "$DB_HOST" ]]; then
        error "Remote database host is required."
        exit 1
    fi

    question "Remote database port [3306]"      && DB_PORT="${answer:-3306}"
    question "AzerothCore DB user [acore]"      && DB_USER="${answer:-acore}"
    question "AzerothCore DB password [acore]"  && DB_PASS="${answer:-acore}"
fi

# ─── Container Creation ───────────────────────────────────────────────────────

info "Creating container for AzerothCore..."

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

# ─── Container Networking ─────────────────────────────────────────────────────

info "Configuring container networking..."
container network prompt --name "$CT_NAME"

# ─── Setup Inside Container ───────────────────────────────────────────────────

info "Building AzerothCore in container '$CT_NAME'..."
warn "The build step takes 30-60 minutes. Do not interrupt the process."

CONTAINER_SCRIPT
#!/bin/bash
source <(wget -qO- https://raw.githubusercontent.com/rmayobre/shtuff/main/shtuff-remote.sh)

update &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Updating packages" \
    --success_msg "Packages updated" --error_msg "Package update failed" || exit 1

install git cmake make gcc g++ clang libssl-dev libbz2-dev libreadline-dev libncurses-dev libboost-all-dev default-libmysqlclient-dev &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing build dependencies" \
    --success_msg "Build dependencies installed" --error_msg "Build dependency installation failed" || exit 1

if [[ "${DB_MODE}" == "local" ]]; then
    install mysql-server &
    monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing MySQL" \
        --success_msg "MySQL installed" --error_msg "MySQL installation failed" || exit 1

    if [[ "${DB_PORT}" != "3306" ]]; then
        if grep -q '^\s*#*\s*port\s*=' /etc/mysql/mysql.conf.d/mysqld.cnf; then
            sed -i "s|^\s*#*\s*port\s*=.*|port = ${DB_PORT}|" /etc/mysql/mysql.conf.d/mysqld.cnf
        else
            sed -i "/^\[mysqld\]/a port = ${DB_PORT}" /etc/mysql/mysql.conf.d/mysqld.cnf
        fi &
        monitor $! --style "$SPINNER_LOADING_STYLE" --message "Configuring MySQL port" \
            --success_msg "MySQL port configured" --error_msg "Failed to configure MySQL port" || exit 1
    fi

    systemctl enable --now mysql &
    monitor $! --style "$SPINNER_LOADING_STYLE" --message "Starting MySQL service" \
        --success_msg "MySQL service started" --error_msg "Failed to start MySQL service" || exit 1

    mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASSWORD}'; DELETE FROM mysql.user WHERE User=''; DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1'); DROP DATABASE IF EXISTS test; DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%'; FLUSH PRIVILEGES;" &
    monitor $! --style "$SPINNER_LOADING_STYLE" --message "Securing MySQL" \
        --success_msg "MySQL secured" --error_msg "Failed to secure MySQL" || exit 1

    mysql -u root -p'${DB_ROOT_PASSWORD}' -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}'; CREATE USER IF NOT EXISTS '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}'; GRANT ALL PRIVILEGES ON *.* TO '${DB_USER}'@'localhost' WITH GRANT OPTION; GRANT ALL PRIVILEGES ON *.* TO '${DB_USER}'@'127.0.0.1' WITH GRANT OPTION; FLUSH PRIVILEGES;" &
    monitor $! --style "$SPINNER_LOADING_STYLE" --message "Configuring AzerothCore database user" \
        --success_msg "Database user configured" --error_msg "Failed to configure database user" || exit 1
fi

git clone https://github.com/azerothcore/azerothcore-wotlk.git \
    --branch master --single-branch --depth 1 /opt/azerothcore &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Cloning AzerothCore repository" \
    --success_msg "Repository cloned" --error_msg "Failed to clone repository" || exit 1

cmake -S /opt/azerothcore -B /opt/azerothcore/build \
    -DCMAKE_INSTALL_PREFIX=/opt/azerothcore/env/dist/ \
    -DCMAKE_C_COMPILER=/usr/bin/clang \
    -DCMAKE_CXX_COMPILER=/usr/bin/clang++ \
    -DWITH_WARNINGS=1 \
    -DTOOLS_BUILD=all \
    -DSCRIPTS=static \
    -DMODULES=static &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Configuring build with CMake" \
    --success_msg "CMake configuration complete" --error_msg "CMake configuration failed" || exit 1

make -j$(nproc) -C /opt/azerothcore/build &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Building AzerothCore (this takes 30-60 minutes)" \
    --success_msg "Build complete" --error_msg "Build failed" || exit 1

make install -C /opt/azerothcore/build &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing AzerothCore binaries" \
    --success_msg "Binaries installed" --error_msg "Binary installation failed" || exit 1

cp /opt/azerothcore/env/dist/etc/authserver.conf.dist \
    /opt/azerothcore/env/dist/etc/authserver.conf \
    || { error "Failed to copy authserver config"; exit 1; }
cp /opt/azerothcore/env/dist/etc/worldserver.conf.dist \
    /opt/azerothcore/env/dist/etc/worldserver.conf \
    || { error "Failed to copy worldserver config"; exit 1; }

sed -i 's|^LoginDatabaseInfo\s*=.*|LoginDatabaseInfo = "${DB_HOST};${DB_PORT};${DB_USER};${DB_PASS};acore_auth"|' \
    /opt/azerothcore/env/dist/etc/authserver.conf \
    || { error "Failed to configure authserver database connection"; exit 1; }

sed -i 's|^LoginDatabaseInfo\s*=.*|LoginDatabaseInfo = "${DB_HOST};${DB_PORT};${DB_USER};${DB_PASS};acore_auth"|' \
    /opt/azerothcore/env/dist/etc/worldserver.conf \
    || { error "Failed to configure worldserver login database connection"; exit 1; }
sed -i 's|^WorldDatabaseInfo\s*=.*|WorldDatabaseInfo = "${DB_HOST};${DB_PORT};${DB_USER};${DB_PASS};acore_world"|' \
    /opt/azerothcore/env/dist/etc/worldserver.conf \
    || { error "Failed to configure worldserver world database connection"; exit 1; }
sed -i 's|^CharacterDatabaseInfo\s*=.*|CharacterDatabaseInfo = "${DB_HOST};${DB_PORT};${DB_USER};${DB_PASS};acore_characters"|' \
    /opt/azerothcore/env/dist/etc/worldserver.conf \
    || { error "Failed to configure worldserver character database connection"; exit 1; }

sed -i 's|^DataDir\s*=.*|DataDir = "/opt/azerothcore/env/dist/bin"|' \
    /opt/azerothcore/env/dist/etc/worldserver.conf \
    || { error "Failed to configure worldserver data directory"; exit 1; }
sed -i 's|^LogsDir\s*=.*|LogsDir = "/opt/azerothcore/env/dist/bin/logs"|' \
    /opt/azerothcore/env/dist/etc/worldserver.conf \
    || { error "Failed to configure worldserver logs directory"; exit 1; }

mkdir -p \
    /opt/azerothcore/env/dist/bin/maps \
    /opt/azerothcore/env/dist/bin/vmaps \
    /opt/azerothcore/env/dist/bin/mmaps \
    /opt/azerothcore/env/dist/bin/dbc \
    /opt/azerothcore/env/dist/bin/Cameras \
    /opt/azerothcore/env/dist/bin/gt \
    /opt/azerothcore/env/dist/bin/logs \
    || { error "Failed to create data directories"; exit 1; }

service \
    --name "acore-auth" \
    --description "AzerothCore Authserver" \
    --exec-start "/opt/azerothcore/env/dist/bin/authserver --config /opt/azerothcore/env/dist/etc/authserver.conf" \
    --restart "on-failure" \
    --restart-sec 5 &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Configuring authserver service" \
    --success_msg "Authserver service configured and started" \
    --error_msg "Failed to configure authserver service" || exit 1

service \
    --name "acore-world" \
    --description "AzerothCore Worldserver" \
    --exec-start "/opt/azerothcore/env/dist/bin/worldserver --config /opt/azerothcore/env/dist/etc/worldserver.conf" \
    --restart "on-failure" \
    --restart-sec 10 &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Configuring worldserver service" \
    --success_msg "Worldserver service configured and started" \
    --error_msg "Failed to configure worldserver service" || exit 1
CONTAINER_SCRIPT_EOD

container shell-script --name "$CT_NAME" --path /opt/azerothcore-setup.sh \
    --env "DB_MODE=$DB_MODE" \
    --env "DB_ROOT_PASSWORD=$DB_ROOT_PASSWORD" \
    --env "DB_USER=$DB_USER" \
    --env "DB_PASS=$DB_PASS" \
    --env "DB_HOST=$DB_HOST" \
    --env "DB_PORT=$DB_PORT" \
    --env "SPINNER_LOADING_STYLE=$SPINNER_LOADING_STYLE" \
    --style "$SPINNER_LOADING_STYLE" &
monitor $! --style "$SPINNER_LOADING_STYLE" \
    --message "Deploying AzerothCore setup script" \
    --success_msg "Setup script deployed" \
    --error_msg "Setup script deployment failed" || exit 1

container exec --name "$CT_NAME" -- /opt/azerothcore-setup.sh &
monitor $! --style "$SPINNER_LOADING_STYLE" \
    --message "Building and configuring AzerothCore" \
    --success_msg "AzerothCore ready" \
    --error_msg "AzerothCore setup failed" || exit 1

# ─── Host Cleanup ─────────────────────────────────────────────────────────────

clean &
monitor $! --style "$SPINNER_LOADING_STYLE" \
    --message "Cleaning up" \
    --success_msg "Cleanup complete" \
    --error_msg "Cleanup failed"

info "AzerothCore installed successfully in container '$CT_NAME'!"
info "  Authserver  : port $AUTH_PORT  (service: acore-auth)"
info "  Worldserver : port $WORLD_PORT (service: acore-world)"
info "  Database    : ${DB_HOST}:${DB_PORT} (user: ${DB_USER})"
info "  Install dir : /opt/azerothcore/env/dist/"
info "  Config dir  : /opt/azerothcore/env/dist/etc/"
warn "Worldserver will NOT accept connections until WoW client data files are in place."
warn "Extract and copy data into /opt/azerothcore/env/dist/bin/:"
warn "  maps/  vmaps/  mmaps/  dbc/  Cameras/  gt/"
warn "Use the extraction tools in /opt/azerothcore/env/dist/bin/ against a WoTLK client."

if [[ "$DB_MODE" == "local" ]]; then
    info "On first worldserver start, AzerothCore will auto-populate acore_auth, acore_world,"
    info "and acore_characters. This initial import takes several minutes."
else
    warn "Remote DB: ensure user '${DB_USER}' exists on ${DB_HOST}:${DB_PORT} with"
    warn "ALL PRIVILEGES on acore_auth, acore_world, and acore_characters before"
    warn "starting the worldserver. Databases will be auto-created on first start."
fi
