#!/bin/bash
source <(curl -sL https://raw.githubusercontent.com/rmayobre/shtuff/main/shtuff-remote.sh)

# ─── User Configuration ───────────────────────────────────────────────────────

info "Configuring Woodpecker CI installation..."

# Container configuration
question "Container name [woodpecker]"     && CT_NAME="${answer:-woodpecker}"
question "Container hostname [woodpecker]" && CT_HOSTNAME="${answer:-woodpecker}"
question "Memory in MB [2048]"             && CT_MEMORY="${answer:-2048}"
question "CPU cores [2]"                   && CT_CORES="${answer:-2}"
question "Disk size in GB [16]"            && CT_DISK="${answer:-16}"

# Woodpecker server configuration
question "Web UI port [8000]"  && WP_HTTP_PORT="${answer:-8000}"
question "Agent gRPC port [9000]" && WP_GRPC_PORT="${answer:-9000}"
question "External URL Woodpecker will be reachable at (e.g. https://ci.example.com) [http://localhost:${WP_HTTP_PORT}]" \
    && WP_HOST="${answer:-http://localhost:${WP_HTTP_PORT}}"

# Forge integration
options "Select the forge (git server) Woodpecker will integrate with" \
    --choice "github" \
    --choice "gitea" \
    --choice "gitlab" \
    --choice "bitbucket" \
    --choice "skip" \
    && WP_FORGE="$answer"

WP_FORGE_ENV=""
case "$WP_FORGE" in
    github)
        question "GitHub OAuth Client ID"     && WP_FORGE_CLIENT="$answer"
        question "GitHub OAuth Client Secret" && WP_FORGE_SECRET="$answer"
        question "GitHub URL (leave blank for github.com, set for GitHub Enterprise)" \
            && WP_FORGE_URL="${answer:-}"

        WP_FORGE_ENV="WOODPECKER_GITHUB=true
WOODPECKER_GITHUB_CLIENT=${WP_FORGE_CLIENT}
WOODPECKER_GITHUB_SECRET=${WP_FORGE_SECRET}"
        [[ -n "$WP_FORGE_URL" ]] && WP_FORGE_ENV="${WP_FORGE_ENV}
WOODPECKER_GITHUB_URL=${WP_FORGE_URL}"
        ;;
    gitea)
        question "Gitea URL (e.g. https://gitea.example.com)" && WP_FORGE_URL="$answer"
        question "Gitea OAuth Client ID"     && WP_FORGE_CLIENT="$answer"
        question "Gitea OAuth Client Secret" && WP_FORGE_SECRET="$answer"

        WP_FORGE_ENV="WOODPECKER_GITEA=true
WOODPECKER_GITEA_URL=${WP_FORGE_URL}
WOODPECKER_GITEA_CLIENT=${WP_FORGE_CLIENT}
WOODPECKER_GITEA_SECRET=${WP_FORGE_SECRET}"
        ;;
    gitlab)
        question "GitLab URL (leave blank for gitlab.com)" && WP_FORGE_URL="${answer:-https://gitlab.com}"
        question "GitLab OAuth Application ID"     && WP_FORGE_CLIENT="$answer"
        question "GitLab OAuth Application Secret" && WP_FORGE_SECRET="$answer"

        WP_FORGE_ENV="WOODPECKER_GITLAB=true
WOODPECKER_GITLAB_URL=${WP_FORGE_URL}
WOODPECKER_GITLAB_CLIENT=${WP_FORGE_CLIENT}
WOODPECKER_GITLAB_SECRET=${WP_FORGE_SECRET}"
        ;;
    bitbucket)
        question "Bitbucket OAuth Consumer Key"    && WP_FORGE_CLIENT="$answer"
        question "Bitbucket OAuth Consumer Secret" && WP_FORGE_SECRET="$answer"

        WP_FORGE_ENV="WOODPECKER_BITBUCKET=true
WOODPECKER_BITBUCKET_CLIENT=${WP_FORGE_CLIENT}
WOODPECKER_BITBUCKET_SECRET=${WP_FORGE_SECRET}"
        ;;
    skip)
        warn "No forge configured. You'll need to edit /etc/woodpecker/woodpecker-server.env manually."
        ;;
esac

question "Admin username(s) on the forge, comma-separated (leave blank to skip)" \
    && WP_ADMIN="${answer:-}"

confirm "Allow open user registration?" && WP_OPEN="$answer"

# Agent configuration
options "Select the pipeline execution backend for the agent" \
    --choice "local" \
    --choice "docker" \
    && WP_BACKEND="$answer"

question "Max concurrent pipeline workflows for the agent [1]" && WP_MAX_WORKFLOWS="${answer:-1}"

# ─── Container Creation ───────────────────────────────────────────────────────

info "Creating container for Woodpecker CI..."

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

info "Installing and configuring Woodpecker CI..."

CONTAINER_SCRIPT
#!/bin/bash
source <(wget -qO- https://raw.githubusercontent.com/rmayobre/shtuff/main/shtuff-remote.sh)

update &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Updating packages" \
    --success_msg "Packages updated" --error_msg "Package update failed" || exit 1

install curl ca-certificates openssl git &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing dependencies" \
    --success_msg "Dependencies installed" --error_msg "Dependency installation failed" || exit 1

if [[ "${WP_BACKEND}" == "docker" ]]; then
    install docker.io &
    monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing Docker" \
        --success_msg "Docker installed" --error_msg "Docker installation failed" || exit 1

    systemctl enable --now docker &
    monitor $! --style "$SPINNER_LOADING_STYLE" --message "Starting Docker service" \
        --success_msg "Docker service started" --error_msg "Failed to start Docker service" || exit 1
fi

WP_TAG=$(curl -fsSL https://api.github.com/repos/woodpecker-ci/woodpecker/releases/latest \
    | grep '"tag_name"' | sed -E 's/.*"(v[^"]+)".*/\1/') &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Looking up latest Woodpecker release" \
    --success_msg "Found latest release: ${WP_TAG}" --error_msg "Failed to look up latest release" || exit 1

if [[ -z "${WP_TAG}" ]]; then
    error "Could not determine latest Woodpecker release"
    exit 1
fi

WP_VERSION="${WP_TAG#v}"
WP_BASE_URL="https://github.com/woodpecker-ci/woodpecker/releases/download/${WP_TAG}"

cd /tmp || exit 1

curl -fsSL -o woodpecker-server.deb "${WP_BASE_URL}/woodpecker-server_${WP_VERSION}_amd64.deb" &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Downloading Woodpecker server ${WP_VERSION}" \
    --success_msg "Woodpecker server downloaded" --error_msg "Failed to download Woodpecker server" || exit 1

curl -fsSL -o woodpecker-agent.deb "${WP_BASE_URL}/woodpecker-agent_${WP_VERSION}_amd64.deb" &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Downloading Woodpecker agent ${WP_VERSION}" \
    --success_msg "Woodpecker agent downloaded" --error_msg "Failed to download Woodpecker agent" || exit 1

(dpkg -i --force-overwrite woodpecker-server.deb woodpecker-agent.deb; apt-get install -f -y) &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing Woodpecker packages" \
    --success_msg "Woodpecker packages installed" --error_msg "Woodpecker package installation failed" || exit 1

rm -f woodpecker-server.deb woodpecker-agent.deb

WP_AGENT_SECRET=$(openssl rand -hex 32)

cat > /etc/woodpecker/woodpecker-server.env <<EOF
WOODPECKER_OPEN=${WP_OPEN}
WOODPECKER_HOST=${WP_HOST}
WOODPECKER_SERVER_ADDR=:${WP_HTTP_PORT}
WOODPECKER_GRPC_ADDR=:${WP_GRPC_PORT}
WOODPECKER_AGENT_SECRET=${WP_AGENT_SECRET}
EOF

if [[ -n "${WP_ADMIN}" ]]; then
    echo "WOODPECKER_ADMIN=${WP_ADMIN}" >> /etc/woodpecker/woodpecker-server.env
fi

if [[ -n "${WP_FORGE_ENV}" ]]; then
    echo "${WP_FORGE_ENV}" >> /etc/woodpecker/woodpecker-server.env
fi

cat > /etc/woodpecker/woodpecker-agent.env <<EOF
WOODPECKER_SERVER=localhost:${WP_GRPC_PORT}
WOODPECKER_AGENT_SECRET=${WP_AGENT_SECRET}
WOODPECKER_BACKEND=${WP_BACKEND}
WOODPECKER_MAX_WORKFLOWS=${WP_MAX_WORKFLOWS}
EOF

chown woodpecker:woodpecker /etc/woodpecker/woodpecker-server.env /etc/woodpecker/woodpecker-agent.env
chmod 640 /etc/woodpecker/woodpecker-server.env /etc/woodpecker/woodpecker-agent.env

if [[ "${WP_BACKEND}" == "docker" ]]; then
    usermod -aG docker woodpecker \
        || { error "Failed to add woodpecker user to docker group"; exit 1; }
fi

systemctl enable --now woodpecker-server &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Starting Woodpecker server" \
    --success_msg "Woodpecker server started" --error_msg "Failed to start Woodpecker server" || exit 1

systemctl enable --now woodpecker-agent &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Starting Woodpecker agent" \
    --success_msg "Woodpecker agent started" --error_msg "Failed to start Woodpecker agent" || exit 1
CONTAINER_SCRIPT_EOD

container shell-script --name "$CT_NAME" --path /opt/woodpecker-setup.sh \
    --env "WP_HTTP_PORT=$WP_HTTP_PORT" \
    --env "WP_GRPC_PORT=$WP_GRPC_PORT" \
    --env "WP_HOST=$WP_HOST" \
    --env "WP_ADMIN=$WP_ADMIN" \
    --env "WP_OPEN=$WP_OPEN" \
    --env "WP_FORGE_ENV=$WP_FORGE_ENV" \
    --env "WP_BACKEND=$WP_BACKEND" \
    --env "WP_MAX_WORKFLOWS=$WP_MAX_WORKFLOWS" \
    --env "SPINNER_LOADING_STYLE=$SPINNER_LOADING_STYLE" \
    --style "$SPINNER_LOADING_STYLE" &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Deploying Woodpecker setup script" \
    --success_msg "Setup script deployed" --error_msg "Setup script deployment failed" || exit 1

container exec --name "$CT_NAME" -- /opt/woodpecker-setup.sh &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing and configuring Woodpecker CI" \
    --success_msg "Woodpecker CI ready" --error_msg "Woodpecker CI setup failed" || exit 1

# ─── Host Cleanup ─────────────────────────────────────────────────────────────

clean &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Cleaning up" \
    --success_msg "Cleanup complete" --error_msg "Cleanup failed"

info "Woodpecker CI installed successfully in container '$CT_NAME'!"
info "Web UI: ${WP_HOST}"
if [[ "$WP_FORGE" == "skip" ]]; then
    warn "No forge was configured. Edit /etc/woodpecker/woodpecker-server.env inside the container and restart woodpecker-server."
fi
info "Agent backend: $WP_BACKEND"
