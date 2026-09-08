#!/bin/bash
source <(curl -sL https://raw.githubusercontent.com/rmayobre/shtuff/main/shtuff-remote.sh)

# ─── User Configuration ───────────────────────────────────────────────────────

info "Configuring LibreChat installation..."

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
question "Container name [librechat]"     && CT_NAME="${answer:-librechat}"
question "Container hostname [librechat]" && CT_HOSTNAME="${answer:-librechat}"
question "Memory in MB [4096]"            && CT_MEMORY="${answer:-4096}"
question "CPU cores [2]"                  && CT_CORES="${answer:-2}"
question "Disk size in GB [20]"           && CT_DISK="${answer:-20}"

# LibreChat configuration
question "Web UI port [3080]"    && LC_PORT="${answer:-3080}"
question "App title [LibreChat]" && LC_TITLE="${answer:-LibreChat}"
confirm "Allow new user registration?" && LC_ALLOW_REGISTRATION="$answer"

# MongoDB
options "Is the MongoDB database local or remote?" \
    --choice "local" \
    --choice "remote" \
    && MONGO_MODE="$answer"

if [[ "$MONGO_MODE" == "remote" ]]; then
    question "Remote MongoDB connection URI (e.g. mongodb://user:pass@host:27017/LibreChat)" \
        && MONGO_URI="$answer"

    if [[ -z "$MONGO_URI" ]]; then
        error "A MongoDB connection URI is required for a remote database."
        exit 1
    fi
fi

# Meilisearch (optional message search indexing)
confirm "Enable Meilisearch for message search?" && ENABLE_MEILI="$answer"

# AI provider API keys (leave any blank to configure later in .env)
info "Enter API keys for the AI providers you want to enable (leave blank to skip)."
question "OpenAI API key"    && OPENAI_API_KEY="${answer:-}"
question "Anthropic API key" && ANTHROPIC_API_KEY="${answer:-}"
question "Google API key"    && GOOGLE_KEY="${answer:-}"
question "Groq API key"      && GROQ_API_KEY="${answer:-}"

if [[ -z "$OPENAI_API_KEY" && -z "$ANTHROPIC_API_KEY" && -z "$GOOGLE_KEY" && -z "$GROQ_API_KEY" ]]; then
    warn "No AI provider API keys were provided. You'll need to add at least one to /opt/librechat/.env before LibreChat is usable."
fi

# ─── Container Creation ───────────────────────────────────────────────────────

info "Creating container for LibreChat..."

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

info "Installing LibreChat in container '$CT_NAME'..."

CONTAINER_SCRIPT
#!/bin/bash
source <(wget -qO- https://raw.githubusercontent.com/rmayobre/shtuff/main/shtuff-remote.sh)

update &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Updating packages" \
    --success_msg "Packages updated" --error_msg "Package update failed" || exit 1

install curl ca-certificates gnupg git build-essential python3 openssl &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing dependencies" \
    --success_msg "Dependencies installed" --error_msg "Dependency installation failed" || exit 1

(curl -fsSL https://deb.nodesource.com/setup_20.x | bash -) &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Adding Node.js APT repository" \
    --success_msg "Node.js APT repository added" --error_msg "Failed to add Node.js APT repository" || exit 1

install nodejs &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing Node.js" \
    --success_msg "Node.js installed" --error_msg "Node.js installation failed" || exit 1

if [[ "${MONGO_MODE}" == "local" ]]; then
    (curl -fsSL https://pgp.mongodb.com/server-7.0.asc | gpg --dearmor -o /usr/share/keyrings/mongodb-server-7.0.gpg \
        && echo "deb [signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg] https://repo.mongodb.org/apt/${CT_DIST} ${CT_RELEASE}/mongodb-org/7.0 main" > /etc/apt/sources.list.d/mongodb-org-7.0.list \
        && apt-get update -qq) &
    monitor $! --style "$SPINNER_LOADING_STYLE" --message "Adding MongoDB APT repository" \
        --success_msg "MongoDB APT repository added" --error_msg "Failed to add MongoDB APT repository" || exit 1

    install mongodb-org &
    monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing MongoDB" \
        --success_msg "MongoDB installed" --error_msg "MongoDB installation failed" || exit 1

    systemctl enable --now mongod &
    monitor $! --style "$SPINNER_LOADING_STYLE" --message "Starting MongoDB service" \
        --success_msg "MongoDB service started" --error_msg "Failed to start MongoDB service" || exit 1

    MONGO_URI="mongodb://127.0.0.1:27017/LibreChat"
fi

MEILI_MASTER_KEY=""
if [[ "${ENABLE_MEILI}" == "true" || "${ENABLE_MEILI}" == "yes" ]]; then
    (curl -fsSL https://install.meilisearch.com | sh) &
    monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing Meilisearch" \
        --success_msg "Meilisearch installed" --error_msg "Meilisearch installation failed" || exit 1

    mv ./meilisearch /usr/local/bin/meilisearch \
        || { error "Failed to install Meilisearch binary"; exit 1; }

    MEILI_MASTER_KEY="$(openssl rand -hex 16)"

    service \
        --name "meilisearch" \
        --description "Meilisearch" \
        --exec-start "/usr/local/bin/meilisearch --http-addr 127.0.0.1:7700 --master-key ${MEILI_MASTER_KEY} --no-analytics" \
        --restart "on-failure" \
        --restart-sec 5 &
    monitor $! --style "$SPINNER_LOADING_STYLE" --message "Configuring Meilisearch service" \
        --success_msg "Meilisearch service configured and started" \
        --error_msg "Failed to configure Meilisearch service" || exit 1
fi

git clone --depth 1 https://github.com/danny-avila/LibreChat.git /opt/librechat &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Cloning LibreChat" \
    --success_msg "LibreChat cloned" --error_msg "Failed to clone LibreChat" || exit 1

(cd /opt/librechat && npm ci) &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing LibreChat dependencies" \
    --success_msg "LibreChat dependencies installed" --error_msg "Failed to install LibreChat dependencies" || exit 1

JWT_SECRET="$(openssl rand -hex 32)"
JWT_REFRESH_SECRET="$(openssl rand -hex 32)"
CREDS_KEY="$(openssl rand -hex 32)"
CREDS_IV="$(openssl rand -hex 16)"

cat > /opt/librechat/.env <<EOF
HOST=0.0.0.0
PORT=${LC_PORT}
APP_TITLE=${LC_TITLE}
DOMAIN_CLIENT=http://localhost:${LC_PORT}
DOMAIN_SERVER=http://localhost:${LC_PORT}
ALLOW_REGISTRATION=${LC_ALLOW_REGISTRATION}
MONGO_URI=${MONGO_URI}
JWT_SECRET=${JWT_SECRET}
JWT_REFRESH_SECRET=${JWT_REFRESH_SECRET}
CREDS_KEY=${CREDS_KEY}
CREDS_IV=${CREDS_IV}
OPENAI_API_KEY=${OPENAI_API_KEY}
ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
GOOGLE_KEY=${GOOGLE_KEY}
GROQ_API_KEY=${GROQ_API_KEY}
SEARCH=$([[ "${ENABLE_MEILI}" == "true" || "${ENABLE_MEILI}" == "yes" ]] && echo "true" || echo "false")
MEILI_HOST=http://127.0.0.1:7700
MEILI_MASTER_KEY=${MEILI_MASTER_KEY}
MEILI_NO_ANALYTICS=true
EOF

(cd /opt/librechat && npm run frontend) &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Building LibreChat client (this can take a few minutes)" \
    --success_msg "LibreChat client built" --error_msg "Failed to build LibreChat client" || exit 1

service \
    --name "librechat" \
    --description "LibreChat" \
    --exec-start "/bin/bash -c 'cd /opt/librechat && node api/server/index.js'" \
    --restart "on-failure" \
    --restart-sec 5 &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Configuring LibreChat service" \
    --success_msg "LibreChat service configured and started" \
    --error_msg "Failed to configure LibreChat service" || exit 1
CONTAINER_SCRIPT_EOD

container shell-script --name "$CT_NAME" --path /opt/librechat-setup.sh \
    --env "CT_DIST=$CT_DIST" \
    --env "CT_RELEASE=$CT_RELEASE" \
    --env "LC_PORT=$LC_PORT" \
    --env "LC_TITLE=$LC_TITLE" \
    --env "LC_ALLOW_REGISTRATION=$LC_ALLOW_REGISTRATION" \
    --env "MONGO_MODE=$MONGO_MODE" \
    --env "MONGO_URI=$MONGO_URI" \
    --env "ENABLE_MEILI=$ENABLE_MEILI" \
    --env "OPENAI_API_KEY=$OPENAI_API_KEY" \
    --env "ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY" \
    --env "GOOGLE_KEY=$GOOGLE_KEY" \
    --env "GROQ_API_KEY=$GROQ_API_KEY" \
    --env "SPINNER_LOADING_STYLE=$SPINNER_LOADING_STYLE" \
    --style "$SPINNER_LOADING_STYLE" &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Deploying LibreChat setup script" \
    --success_msg "Setup script deployed" --error_msg "Setup script deployment failed" || exit 1

container exec --name "$CT_NAME" -- /opt/librechat-setup.sh &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing and configuring LibreChat" \
    --success_msg "LibreChat ready" --error_msg "LibreChat setup failed" || exit 1

# ─── Host Cleanup ─────────────────────────────────────────────────────────────

clean &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Cleaning up" \
    --success_msg "Cleanup complete" --error_msg "Cleanup failed"

info "LibreChat installed successfully in container '$CT_NAME'!"
info "  Web UI  : http://<container-ip>:$LC_PORT"
if [[ "$MONGO_MODE" == "local" ]]; then
    info "  Database: local MongoDB (127.0.0.1:27017)"
else
    info "  Database: remote MongoDB"
fi
if [[ "$ENABLE_MEILI" == "true" || "$ENABLE_MEILI" == "yes" ]]; then
    info "  Search  : Meilisearch enabled (127.0.0.1:7700)"
fi
info "Update DOMAIN_CLIENT and DOMAIN_SERVER in /opt/librechat/.env to the container's reachable URL, then restart the 'librechat' service."
if [[ -z "$OPENAI_API_KEY" && -z "$ANTHROPIC_API_KEY" && -z "$GOOGLE_KEY" && -z "$GROQ_API_KEY" ]]; then
    warn "No AI provider API keys were configured. Add at least one to /opt/librechat/.env and restart the 'librechat' service."
fi
