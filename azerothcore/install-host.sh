#!/bin/bash
source <(curl -sL https://raw.githubusercontent.com/rmayobre/shtuff/main/shtuff-remote.sh)

# ─── Environment Variables ─────────────────────────────────────────────────────
# Override any of these before running the script to skip the matching prompt,
# e.g.: AZEROTHCORE_GIT_URL="https://github.com/myfork/azerothcore-wotlk.git" ./install-host.sh

AZEROTHCORE_GIT_URL="${AZEROTHCORE_GIT_URL:-https://github.com/azerothcore/azerothcore-wotlk.git}"
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="${DB_PORT:-3306}"
DB_USER="${DB_USER:-acore}"
DB_PASS="${DB_PASS:-acore}"
CLIENT_DATA_URL="${CLIENT_DATA_URL:-}"

# ─── User Configuration ────────────────────────────────────────────────────────

info "Configuring AzerothCore host installation..."

question "AzerothCore git URL [$AZEROTHCORE_GIT_URL]" \
    && AZEROTHCORE_GIT_URL="${answer:-$AZEROTHCORE_GIT_URL}"

# Server ports
question "Auth server port [3724]"          && AUTH_PORT="${answer:-3724}"
question "World server port [8085]"         && WORLD_PORT="${answer:-8085}"

# Client data
question "Client data zip URL (leave blank to add data manually later) [$CLIENT_DATA_URL]" \
    && CLIENT_DATA_URL="${answer:-$CLIENT_DATA_URL}"

# Database setup
options "Database setup" \
    --choice "local" \
    --choice "remote" \
    && DB_MODE="$answer"

if [[ "$DB_MODE" == "local" ]]; then
    question "Database port [$DB_PORT]"         && DB_PORT="${answer:-$DB_PORT}"
    question "MySQL root password"              && DB_ROOT_PASSWORD="$answer"

    if [[ -z "$DB_ROOT_PASSWORD" ]]; then
        error "MySQL root password is required for a local database."
        exit 1
    fi

    DB_HOST="127.0.0.1"
    question "AzerothCore DB user [$DB_USER]"   && DB_USER="${answer:-$DB_USER}"
    question "AzerothCore DB password [$DB_PASS]" && DB_PASS="${answer:-$DB_PASS}"
else
    question "Remote database host [$DB_HOST]"  && DB_HOST="${answer:-$DB_HOST}"

    if [[ -z "$DB_HOST" ]]; then
        error "Remote database host is required."
        exit 1
    fi

    question "Remote database port [$DB_PORT]"  && DB_PORT="${answer:-$DB_PORT}"
    question "AzerothCore DB user [$DB_USER]"   && DB_USER="${answer:-$DB_USER}"
    question "AzerothCore DB password [$DB_PASS]" && DB_PASS="${answer:-$DB_PASS}"
fi

info "Building AzerothCore on this host..."
warn "The build step takes 30-60 minutes. Do not interrupt the process."

# ─── Dependencies ───────────────────────────────────────────────────────────────

update &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Updating packages" \
    --success_msg "Packages updated" --error_msg "Package update failed" || exit 1

install gnupg lsb-release apt-transport-https ca-certificates &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing prerequisites" \
    --success_msg "Prerequisites installed" --error_msg "Failed to install prerequisites" || exit 1

HOST_DIST="$(. /etc/os-release && echo "$ID")"
HOST_RELEASE="$(. /etc/os-release && echo "$VERSION_CODENAME")"

mkdir -p /etc/apt/keyrings
gpg --keyserver keyserver.ubuntu.com --recv-keys B7B3B788A8D3785C &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Importing MySQL GPG key" \
    --success_msg "MySQL GPG key imported" --error_msg "Failed to import MySQL GPG key" || exit 1

gpg --export B7B3B788A8D3785C > /etc/apt/keyrings/mysql.gpg

echo "deb [signed-by=/etc/apt/keyrings/mysql.gpg] http://repo.mysql.com/apt/${HOST_DIST} ${HOST_RELEASE} mysql-8.0" \
    > /etc/apt/sources.list.d/mysql.list

update &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Updating package lists with MySQL repo" \
    --success_msg "Package lists updated" --error_msg "Package list update failed" || exit 1

install git cmake make gcc g++ clang libssl-dev libbz2-dev libreadline-dev libncurses-dev libboost-all-dev screen unzip &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing build dependencies" \
    --success_msg "Build dependencies installed" --error_msg "Build dependency installation failed" || exit 1

install mysql-community-client-core mysql-community-client mysql-community-client-plugins libmysqlclient-dev &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing MySQL client library" \
    --success_msg "MySQL client library installed" --error_msg "MySQL client library installation failed" || exit 1

# ─── Local Database Setup (optional) ───────────────────────────────────────────

if [[ "${DB_MODE}" == "local" ]]; then
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
        fi &
        monitor $! --style "$SPINNER_LOADING_STYLE" --message "Configuring MySQL port" \
            --success_msg "MySQL port configured" --error_msg "Failed to configure MySQL port" || exit 1
    fi

    systemctl enable --now mysql &
    monitor $! --style "$SPINNER_LOADING_STYLE" --message "Starting MySQL service" \
        --success_msg "MySQL service started" --error_msg "Failed to start MySQL service" || exit 1

    mysql -u root -p"${DB_ROOT_PASSWORD}" -e "DELETE FROM mysql.user WHERE User=''; DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1'); DROP DATABASE IF EXISTS test; DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%'; FLUSH PRIVILEGES;" &
    monitor $! --style "$SPINNER_LOADING_STYLE" --message "Securing MySQL" \
        --success_msg "MySQL secured" --error_msg "Failed to secure MySQL" || exit 1

    mysql -u root -p"${DB_ROOT_PASSWORD}" -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}'; CREATE USER IF NOT EXISTS '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}'; GRANT ALL PRIVILEGES ON *.* TO '${DB_USER}'@'localhost' WITH GRANT OPTION; GRANT ALL PRIVILEGES ON *.* TO '${DB_USER}'@'127.0.0.1' WITH GRANT OPTION; FLUSH PRIVILEGES;" &
    monitor $! --style "$SPINNER_LOADING_STYLE" --message "Configuring AzerothCore database user" \
        --success_msg "Database user configured" --error_msg "Failed to configure database user" || exit 1
fi

# ─── AzerothCore Build ──────────────────────────────────────────────────────────

git clone "$AZEROTHCORE_GIT_URL" \
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

# ─── Configuration ──────────────────────────────────────────────────────────────

cp /opt/azerothcore/env/dist/etc/authserver.conf.dist \
    /opt/azerothcore/env/dist/etc/authserver.conf \
    || { error "Failed to copy authserver config"; exit 1; }
cp /opt/azerothcore/env/dist/etc/worldserver.conf.dist \
    /opt/azerothcore/env/dist/etc/worldserver.conf \
    || { error "Failed to copy worldserver config"; exit 1; }

sed -i "s|^LoginDatabaseInfo\s*=.*|LoginDatabaseInfo = \"${DB_HOST};${DB_PORT};${DB_USER};${DB_PASS};acore_auth\"|" \
    /opt/azerothcore/env/dist/etc/authserver.conf \
    || { error "Failed to configure authserver database connection"; exit 1; }

sed -i "s|^LoginDatabaseInfo\s*=.*|LoginDatabaseInfo = \"${DB_HOST};${DB_PORT};${DB_USER};${DB_PASS};acore_auth\"|" \
    /opt/azerothcore/env/dist/etc/worldserver.conf \
    || { error "Failed to configure worldserver login database connection"; exit 1; }
sed -i "s|^WorldDatabaseInfo\s*=.*|WorldDatabaseInfo = \"${DB_HOST};${DB_PORT};${DB_USER};${DB_PASS};acore_world\"|" \
    /opt/azerothcore/env/dist/etc/worldserver.conf \
    || { error "Failed to configure worldserver world database connection"; exit 1; }
sed -i "s|^CharacterDatabaseInfo\s*=.*|CharacterDatabaseInfo = \"${DB_HOST};${DB_PORT};${DB_USER};${DB_PASS};acore_characters\"|" \
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

if [[ -n "${CLIENT_DATA_URL}" ]]; then
    curl -sL "${CLIENT_DATA_URL}" -o /tmp/azerothcore-client-data.zip &
    monitor $! --style "$SPINNER_LOADING_STYLE" --message "Downloading client data" \
        --success_msg "Client data downloaded" --error_msg "Failed to download client data" || exit 1

    unzip -oq /tmp/azerothcore-client-data.zip -d /opt/azerothcore/env/dist/bin &
    monitor $! --style "$SPINNER_LOADING_STYLE" --message "Extracting client data" \
        --success_msg "Client data extracted" --error_msg "Failed to extract client data" || exit 1

    rm -f /tmp/azerothcore-client-data.zip
fi

# ─── Service Setup ──────────────────────────────────────────────────────────────

service \
    --name "acore-auth" \
    --description "AzerothCore Authserver" \
    --exec-start "/usr/bin/screen -DmS acore-auth /opt/azerothcore/env/dist/bin/authserver --config /opt/azerothcore/env/dist/etc/authserver.conf" \
    --restart "on-failure" \
    --restart-sec 5 &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Configuring authserver service" \
    --success_msg "Authserver service configured and started" \
    --error_msg "Failed to configure authserver service" || exit 1

service \
    --name "acore-world" \
    --description "AzerothCore Worldserver" \
    --exec-start "/usr/bin/screen -DmS acore-world /opt/azerothcore/env/dist/bin/worldserver --config /opt/azerothcore/env/dist/etc/worldserver.conf" \
    --restart "on-failure" \
    --restart-sec 10 &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Configuring worldserver service" \
    --success_msg "Worldserver service configured and started" \
    --error_msg "Failed to configure worldserver service" || exit 1

# ─── Host Cleanup ───────────────────────────────────────────────────────────────

clean &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Cleaning up" \
    --success_msg "Cleanup complete" --error_msg "Cleanup failed"

info "AzerothCore installed successfully on this host!"
info "  Authserver  : port $AUTH_PORT  (service: acore-auth, screen: screen -r acore-auth)"
info "  Worldserver : port $WORLD_PORT (service: acore-world, screen: screen -r acore-world)"
info "  Database    : ${DB_HOST}:${DB_PORT} (user: ${DB_USER})"
info "  Install dir : /opt/azerothcore/env/dist/"
info "  Config dir  : /opt/azerothcore/env/dist/etc/"
if [[ -n "$CLIENT_DATA_URL" ]]; then
    info "Client data was downloaded and extracted into /opt/azerothcore/env/dist/bin/."
else
    warn "Worldserver will NOT accept connections until WoW client data files are in place."
    warn "Extract and copy data into /opt/azerothcore/env/dist/bin/:"
    warn "  maps/  vmaps/  mmaps/  dbc/  Cameras/  gt/"
    warn "Use the extraction tools in /opt/azerothcore/env/dist/bin/ against a WoTLK client."
fi

if [[ "$DB_MODE" == "local" ]]; then
    info "On first worldserver start, AzerothCore will auto-populate acore_auth, acore_world,"
    info "and acore_characters. This initial import takes several minutes."
else
    warn "Remote DB: ensure user '${DB_USER}' exists on ${DB_HOST}:${DB_PORT} with"
    warn "ALL PRIVILEGES on acore_auth, acore_world, and acore_characters before"
    warn "starting the worldserver. Databases will be auto-created on first start."
fi
