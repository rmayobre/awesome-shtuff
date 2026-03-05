#!/bin/bash
source <(curl -sL https://raw.githubusercontent.com/rmayobre/shtuff/v1.2.0/shtuff-remote.sh)

# ─── User Configuration ───────────────────────────────────────────────────────

info "Configuring Excalidraw installation..."

# Container configuration
question "Container name [excalidraw]"     && CT_NAME="${answer:-excalidraw}"
question "Container hostname [excalidraw]" && CT_HOSTNAME="${answer:-excalidraw}"
question "Memory in MB [1024]"             && CT_MEMORY="${answer:-1024}"
question "CPU cores [2]"                   && CT_CORES="${answer:-2}"
question "Disk size in GB [8]"             && CT_DISK="${answer:-8}"

# Project-specific configuration
question "Application port [80]"           && APP_PORT="${answer:-80}"

# ─── Container Creation ───────────────────────────────────────────────────────

info "Creating container for Excalidraw..."

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

container exec --name "$CT_NAME" -- apt-get install -y curl git nginx &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing dependencies" \
    --success_msg "Dependencies installed" --error_msg "Dependency installation failed" || exit 1

container exec --name "$CT_NAME" -- bash -c "curl -fsSL https://deb.nodesource.com/setup_20.x | bash -" &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Setting up Node.js repository" \
    --success_msg "Node.js repository configured" --error_msg "Node.js repository setup failed" || exit 1

container exec --name "$CT_NAME" -- apt-get install -y nodejs &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing Node.js" \
    --success_msg "Node.js installed" --error_msg "Node.js installation failed" || exit 1

# ─── Installation Steps ───────────────────────────────────────────────────────

info "Installing Excalidraw..."

container exec --name "$CT_NAME" -- git clone --depth 1 https://github.com/excalidraw/excalidraw.git /opt/excalidraw &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Cloning Excalidraw repository" \
    --success_msg "Repository cloned" --error_msg "Repository clone failed" || exit 1

container exec --name "$CT_NAME" -- bash -c "cd /opt/excalidraw && npm install --legacy-peer-deps" &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing npm dependencies" \
    --success_msg "Dependencies installed" --error_msg "npm install failed" || exit 1

container exec --name "$CT_NAME" -- bash -c "cd /opt/excalidraw && npm run build" &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Building Excalidraw (this may take a few minutes)" \
    --success_msg "Build complete" --error_msg "Build failed" || exit 1

container exec --name "$CT_NAME" -- bash -c "cp -r /opt/excalidraw/excalidraw-app/build/* /var/www/html/" &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Deploying static assets" \
    --success_msg "Assets deployed" --error_msg "Asset deployment failed" || exit 1

# ─── nginx Configuration ──────────────────────────────────────────────────────

if [ "$APP_PORT" != "80" ]; then
    container exec --name "$CT_NAME" -- sed -i "s/listen 80 default_server/listen $APP_PORT default_server/; s/listen \[::\]:80 default_server/listen [::]:$APP_PORT default_server/" /etc/nginx/sites-enabled/default &
    monitor $! --style "$SPINNER_LOADING_STYLE" --message "Configuring nginx port" \
        --success_msg "nginx configured on port $APP_PORT" --error_msg "nginx configuration failed" || exit 1
fi

# ─── Service Setup ────────────────────────────────────────────────────────────

container exec --name "$CT_NAME" -- systemctl enable --now nginx &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Starting nginx" \
    --success_msg "nginx started" --error_msg "nginx startup failed" || exit 1

# ─── Host Cleanup ─────────────────────────────────────────────────────────────

clean &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Cleaning up" \
    --success_msg "Cleanup complete" --error_msg "Cleanup failed"

info "Excalidraw installed successfully in container '$CT_NAME'!"
info "Access it at http://<container-ip>:$APP_PORT"
