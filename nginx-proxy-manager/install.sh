#!/bin/bash
source <(curl -sL https://raw.githubusercontent.com/rmayobre/shtuff/main/shtuff-remote.sh)

# ─── User Configuration ───────────────────────────────────────────────────────

info "Configuring Nginx Proxy Manager installation..."
warn "Nginx Proxy Manager has no official Docker-free package. This script builds it from source (OpenResty + Node.js), which can take 10-20 minutes."

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
question "Container name [nginx-proxy-manager]"     && CT_NAME="${answer:-nginx-proxy-manager}"
question "Container hostname [nginx-proxy-manager]" && CT_HOSTNAME="${answer:-nginx-proxy-manager}"
question "Memory in MB [2048]"                      && CT_MEMORY="${answer:-2048}"
question "CPU cores [2]"                            && CT_CORES="${answer:-2}"
question "Disk size in GB [10]"                     && CT_DISK="${answer:-10}"

# Nginx Proxy Manager configuration
question "Admin UI port [81]" && NPM_ADMIN_PORT="${answer:-81}"

confirm "Install Certbot Cloudflare DNS plugin (for DNS-01 SSL challenges)?" \
    && NPM_CLOUDFLARE_DNS="$answer"

if [[ -z "$CT_NAME" ]]; then
    error "Container name is required."
    exit 1
fi

if ! [[ "$NPM_ADMIN_PORT" =~ ^[0-9]+$ ]]; then
    error "Admin UI port must be numeric."
    exit 1
fi

# ─── Container Creation ───────────────────────────────────────────────────────

info "Creating container for Nginx Proxy Manager..."

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

info "Installing Nginx Proxy Manager in container '$CT_NAME'..."

CONTAINER_SCRIPT
#!/bin/bash
source <(wget -qO- https://raw.githubusercontent.com/rmayobre/shtuff/main/shtuff-remote.sh)

update &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Updating packages" \
    --success_msg "Packages updated" --error_msg "Package update failed" || exit 1

install ca-certificates curl gnupg apache2-utils logrotate build-essential \
    libpcre2-dev libssl-dev zlib1g-dev git python3 python3-dev python3-pip \
    python3-venv python3-cffi sqlite3 &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing build dependencies" \
    --success_msg "Build dependencies installed" --error_msg "Dependency installation failed" || exit 1

# ─── Node.js ───────────────────────────────────────────────────────────────

curl -fsSL https://deb.nodesource.com/setup_22.x | bash - &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Adding Node.js repository" \
    --success_msg "Node.js repository added" --error_msg "Failed to add Node.js repository" || exit 1

install nodejs &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing Node.js" \
    --success_msg "Node.js installed" --error_msg "Node.js installation failed" || exit 1

npm install -g yarn &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing Yarn" \
    --success_msg "Yarn installed" --error_msg "Yarn installation failed" || exit 1

# ─── Certbot ───────────────────────────────────────────────────────────────

python3 -m venv /opt/certbot &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Creating Certbot virtual environment" \
    --success_msg "Certbot virtual environment created" --error_msg "Failed to create Certbot virtual environment" || exit 1

/opt/certbot/bin/pip install --upgrade pip setuptools wheel &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Upgrading pip" \
    --success_msg "Pip upgraded" --error_msg "Failed to upgrade pip" || exit 1

if [[ "${NPM_CLOUDFLARE_DNS}" == "true" || "${NPM_CLOUDFLARE_DNS}" == "yes" ]]; then
    /opt/certbot/bin/pip install certbot certbot-dns-cloudflare &
    monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing Certbot with Cloudflare DNS plugin" \
        --success_msg "Certbot installed" --error_msg "Certbot installation failed" || exit 1
else
    /opt/certbot/bin/pip install certbot &
    monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing Certbot" \
        --success_msg "Certbot installed" --error_msg "Certbot installation failed" || exit 1
fi

ln -sf /opt/certbot/bin/certbot /usr/local/bin/certbot

# ─── OpenResty ─────────────────────────────────────────────────────────────

OPENRESTY_VERSION="1.29.2.5"

curl -fsSL "https://openresty.org/download/openresty-${OPENRESTY_VERSION}.tar.gz" -o /tmp/openresty.tar.gz &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Downloading OpenResty ${OPENRESTY_VERSION}" \
    --success_msg "OpenResty downloaded" --error_msg "Failed to download OpenResty" || exit 1

mkdir -p /opt/openresty \
    && tar -xzf /tmp/openresty.tar.gz -C /opt/openresty --strip-components=1 \
    || { error "Failed to extract OpenResty"; exit 1; }

cd /opt/openresty \
    && ./configure \
        --with-http_v2_module \
        --with-http_realip_module \
        --with-http_stub_status_module \
        --with-http_ssl_module \
        --with-http_sub_module \
        --with-http_auth_request_module \
        --with-pcre-jit \
        --with-stream \
        --with-stream_ssl_module &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Configuring OpenResty build" \
    --success_msg "OpenResty configured" --error_msg "OpenResty configuration failed" || exit 1

make -j"$(nproc)" &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Compiling OpenResty (this will take a while)" \
    --success_msg "OpenResty compiled" --error_msg "OpenResty compilation failed" || exit 1

make install &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing OpenResty" \
    --success_msg "OpenResty installed" --error_msg "OpenResty installation failed" || exit 1

cd / && rm -rf /opt/openresty /tmp/openresty.tar.gz

ln -sf /usr/local/openresty/nginx/sbin/nginx /usr/sbin/nginx
ln -sf /usr/local/openresty/nginx/ /etc/nginx
ln -sf /usr/bin/python3 /usr/bin/python

cat <<'EOF' > /lib/systemd/system/openresty.service
[Unit]
Description=The OpenResty Application Platform
After=syslog.target network-online.target remote-fs.target nss-lookup.target
Wants=network-online.target

[Service]
Type=simple
ExecStartPre=-/bin/mkdir -p /tmp/nginx/body /run/nginx
ExecStartPre=/usr/local/openresty/nginx/sbin/nginx -t
ExecStart=/usr/local/openresty/nginx/sbin/nginx -g 'daemon off;'

[Install]
WantedBy=multi-user.target
EOF

# ─── Nginx Proxy Manager source ───────────────────────────────────────────

NPM_VERSION=$(curl -fsSL https://api.github.com/repos/NginxProxyManager/nginx-proxy-manager/releases/latest \
    | grep -m1 '"tag_name"' | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | tr -d 'v')

if [[ -z "${NPM_VERSION}" ]]; then
    error "Could not determine the latest Nginx Proxy Manager release"
    exit 1
fi

curl -fsSL "https://github.com/NginxProxyManager/nginx-proxy-manager/archive/refs/tags/v${NPM_VERSION}.tar.gz" -o /tmp/npm.tar.gz &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Downloading Nginx Proxy Manager v${NPM_VERSION}" \
    --success_msg "Nginx Proxy Manager downloaded" --error_msg "Failed to download Nginx Proxy Manager" || exit 1

mkdir -p /opt/nginxproxymanager \
    && tar -xzf /tmp/npm.tar.gz -C /opt/nginxproxymanager --strip-components=1 \
    || { error "Failed to extract Nginx Proxy Manager"; exit 1; }
rm -f /tmp/npm.tar.gz

sed -i "0,/\"version\": \"[^\"]*\"/s|\"version\": \"[^\"]*\"|\"version\": \"${NPM_VERSION}\"|" \
    /opt/nginxproxymanager/backend/package.json
sed -i "0,/\"version\": \"[^\"]*\"/s|\"version\": \"[^\"]*\"|\"version\": \"${NPM_VERSION}\"|" \
    /opt/nginxproxymanager/frontend/package.json
sed -i 's+^daemon+#daemon+g' /opt/nginxproxymanager/docker/rootfs/etc/nginx/nginx.conf

for NGINX_CONF in $(find /opt/nginxproxymanager -type f -name "*.conf"); do
    sed -i 's+include conf.d+include /etc/nginx/conf.d+g' "$NGINX_CONF"
done

mkdir -p /var/www/html /etc/nginx/logs
cp -r /opt/nginxproxymanager/docker/rootfs/var/www/html/* /var/www/html/
cp -r /opt/nginxproxymanager/docker/rootfs/etc/nginx/* /etc/nginx/
cp /opt/nginxproxymanager/docker/rootfs/etc/letsencrypt.ini /etc/letsencrypt.ini
cp /opt/nginxproxymanager/docker/rootfs/etc/logrotate.d/nginx-proxy-manager /etc/logrotate.d/nginx-proxy-manager
ln -sf /etc/nginx/nginx.conf /etc/nginx/conf/nginx.conf
rm -f /etc/nginx/conf.d/dev.conf

if [[ "${NPM_ADMIN_PORT}" != "81" ]]; then
    sed -i "s/listen 81 default;/listen ${NPM_ADMIN_PORT} default;/" /etc/nginx/conf.d/production.conf
    sed -i "s/listen \[::\]:81 default;/listen [::]:${NPM_ADMIN_PORT} default;/" /etc/nginx/conf.d/production.conf
fi

mkdir -p /tmp/nginx/body \
    /run/nginx \
    /data/nginx \
    /data/custom_ssl \
    /data/logs \
    /data/access \
    /data/nginx/default_host \
    /data/nginx/default_www \
    /data/nginx/proxy_host \
    /data/nginx/redirection_host \
    /data/nginx/stream \
    /data/nginx/dead_host \
    /data/nginx/temp \
    /var/lib/nginx/cache/public \
    /var/lib/nginx/cache/private \
    /var/cache/nginx/proxy_temp

chmod -R 777 /var/cache/nginx
chown root /tmp/nginx

echo resolver "$(awk 'BEGIN{ORS=" "} $1=="nameserver" {print ($2 ~ ":")? "["$2"]": $2}' /etc/resolv.conf);" \
    > /etc/nginx/conf.d/include/resolvers.conf

openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 \
    -subj "/O=Nginx Proxy Manager/OU=Dummy Certificate/CN=localhost" \
    -keyout /data/nginx/dummykey.pem -out /data/nginx/dummycert.pem &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Generating dummy SSL certificate" \
    --success_msg "Dummy SSL certificate generated" --error_msg "Failed to generate dummy SSL certificate" || exit 1

# ─── Frontend ──────────────────────────────────────────────────────────────

mkdir -p /app/frontend/images
cp -r /opt/nginxproxymanager/backend/* /app

export NODE_OPTIONS="--max_old_space_size=2048 --openssl-legacy-provider"
cd /opt/nginxproxymanager/frontend
sed -E -i 's/"node-sass" *: *"([^"]*)"/"sass": "\1"/g' package.json

yarn install --network-timeout 600000 &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing frontend dependencies (this will take a while)" \
    --success_msg "Frontend dependencies installed" --error_msg "Frontend dependency installation failed" || exit 1

yarn locale-compile &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Compiling frontend locales" \
    --success_msg "Frontend locales compiled" --error_msg "Frontend locale compilation failed" || exit 1

yarn build &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Building frontend (this will take a while)" \
    --success_msg "Frontend built" --error_msg "Frontend build failed" || exit 1

cp -r /opt/nginxproxymanager/frontend/dist/* /app/frontend
cp -r /opt/nginxproxymanager/frontend/public/images/* /app/frontend/images

# ─── Backend ───────────────────────────────────────────────────────────────

rm -f /app/config/default.json
cat <<'EOF' > /app/config/production.json
{
  "database": {
    "engine": "knex-native",
    "knex": {
      "client": "better-sqlite3",
      "connection": {
        "filename": "/data/database.sqlite"
      },
      "useNullAsDefault": true
    }
  }
}
EOF

cd /app
yarn install --network-timeout 600000 &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing backend dependencies" \
    --success_msg "Backend dependencies installed" --error_msg "Backend dependency installation failed" || exit 1

rm -rf /opt/nginxproxymanager

# ─── Service Setup ─────────────────────────────────────────────────────────

CERTBOT_VER=$(/opt/certbot/bin/certbot --version 2>&1 | awk '{print $NF}')

cat <<EOF > /lib/systemd/system/npm.service
[Unit]
Description=Nginx Proxy Manager
After=network.target
Wants=openresty.service

[Service]
Type=simple
Environment=NODE_ENV=production
Environment=CERTBOT_VERSION=${CERTBOT_VER}
ExecStartPre=-mkdir -p /tmp/nginx/body /data/letsencrypt-acme-challenge
ExecStart=/usr/bin/node index.js --abort_on_uncaught_exception --max_old_space_size=250
WorkingDirectory=/app
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

sed -i 's/user npm/user root/g; s/^pid/#pid/g' /usr/local/openresty/nginx/conf/nginx.conf
sed -r -i 's/^([[:space:]]*)su npm npm/\1#su npm npm/g;' /etc/logrotate.d/nginx-proxy-manager

systemctl daemon-reload

systemctl enable --now openresty &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Starting OpenResty" \
    --success_msg "OpenResty started" --error_msg "Failed to start OpenResty" || exit 1

systemctl enable --now npm &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Starting Nginx Proxy Manager" \
    --success_msg "Nginx Proxy Manager started" --error_msg "Failed to start Nginx Proxy Manager" || exit 1
CONTAINER_SCRIPT_EOD

container shell-script --name "$CT_NAME" --path /opt/npm-setup.sh \
    --env "NPM_ADMIN_PORT=$NPM_ADMIN_PORT" \
    --env "NPM_CLOUDFLARE_DNS=$NPM_CLOUDFLARE_DNS" \
    --env "SPINNER_LOADING_STYLE=$SPINNER_LOADING_STYLE" \
    --style "$SPINNER_LOADING_STYLE" &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Deploying Nginx Proxy Manager setup script" \
    --success_msg "Setup script deployed" --error_msg "Setup script deployment failed" || exit 1

container exec --name "$CT_NAME" -- /opt/npm-setup.sh &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing Nginx Proxy Manager (this will take several minutes)" \
    --success_msg "Nginx Proxy Manager ready" --error_msg "Nginx Proxy Manager setup failed" || exit 1

# ─── Host Cleanup ─────────────────────────────────────────────────────────────

clean &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Cleaning up" \
    --success_msg "Cleanup complete" --error_msg "Cleanup failed"

info "Nginx Proxy Manager installed successfully in container '$CT_NAME'!"
info "  Admin UI : http://<container-ip>:${NPM_ADMIN_PORT}"
info "  Default login: admin@example.com / changeme (you will be forced to change this on first login)"
info "  Proxy hosts you configure in the UI will listen on the container's ports 80/443 directly."
info "Run 'container exec --name $CT_NAME -- hostname -I' to find the container IP."
