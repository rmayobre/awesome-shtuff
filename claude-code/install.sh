#!/bin/bash
source <(curl -sL https://raw.githubusercontent.com/rmayobre/shtuff/main/shtuff-remote.sh)

# ─── User Configuration ───────────────────────────────────────────────────────

info "Configuring Claude Code server development environment..."

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
question "Container name [claude-dev]"     && CT_NAME="${answer:-claude-dev}"
question "Container hostname [claude-dev]" && CT_HOSTNAME="${answer:-claude-dev}"
question "Memory in MB [2048]"             && CT_MEMORY="${answer:-2048}"
question "CPU cores [2]"                   && CT_CORES="${answer:-2}"
question "Disk size in GB [20]"            && CT_DISK="${answer:-20}"
question "Root password (leave blank to disable password login)" && CT_PASSWORD="${answer:-}"

# Node.js runtime
options "Select Node.js version to install (Claude Code requires Node.js 18+)" \
    --choice "20" \
    --choice "22" \
    --choice "24" \
    && NODE_MAJOR="$answer"

# Git identity (used for commits made inside the container)
question "Git user name (leave blank to skip)"  && GIT_NAME="${answer:-}"
question "Git user email (leave blank to skip)" && GIT_EMAIL="${answer:-}"

# Anthropic authentication
question "Anthropic API key (leave blank to run 'claude' interactively later)" \
    && ANTHROPIC_API_KEY="${answer:-}"

# Workspace directory
question "Project workspace directory inside container [/workspace]" \
    && WORKSPACE_DIR="${answer:-/workspace}"

# Non-root dev user
confirm "Create a non-root dev user for daily use?" && CREATE_DEV_USER="$answer"
if [[ "$CREATE_DEV_USER" == "yes" ]]; then
    question "Dev username [dev]" && DEV_USER="${answer:-dev}"
    question "Password for '$DEV_USER' (leave blank to disable password login)" && DEV_PASSWORD="${answer:-}"
    question "SSH public key to authorize for '$DEV_USER' (leave blank to skip)" && DEV_SSH_KEY="${answer:-}"
fi

# SSH access
confirm "Install and enable an SSH server for remote access?" && ENABLE_SSH="$answer"
if [[ "$ENABLE_SSH" == "yes" ]]; then
    question "SSH port [22]" && SSH_PORT="${answer:-22}"
fi

# ─── Container Creation ───────────────────────────────────────────────────────

info "Creating container for Claude Code..."

container create \
    --name "$CT_NAME" \
    --hostname "$CT_HOSTNAME" \
    --memory "$CT_MEMORY" \
    --cores "$CT_CORES" \
    --disk-size "$CT_DISK" \
    --dist "$CT_DIST" \
    --release "$CT_RELEASE" \
    --password "$CT_PASSWORD" \
    --style "$SPINNER_LOADING_STYLE" || exit 1

container start --name "$CT_NAME" --style "$SPINNER_LOADING_STYLE" || exit 1

# ─── Network Configuration ────────────────────────────────────────────────────

info "Configuring network for container '$CT_NAME'..."
container network prompt --name "$CT_NAME" || exit 1

# ─── Setup Inside Container ───────────────────────────────────────────────────

info "Installing Claude Code development environment in container '$CT_NAME'..."

CONTAINER_SCRIPT
#!/bin/bash
source <(wget -qO- https://raw.githubusercontent.com/rmayobre/shtuff/main/shtuff-remote.sh)

update &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Updating packages" \
    --success_msg "Packages updated" --error_msg "Package update failed" || exit 1

install curl wget ca-certificates gnupg git build-essential unzip python3 sudo &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing base dev tools" \
    --success_msg "Base dev tools installed" --error_msg "Base dev tool installation failed" || exit 1

curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash - \
    && apt-get install -y nodejs &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing Node.js ${NODE_MAJOR}.x" \
    --success_msg "Node.js installed" --error_msg "Node.js installation failed" || exit 1

npm install -g @anthropic-ai/claude-code &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing Claude Code" \
    --success_msg "Claude Code installed" --error_msg "Claude Code installation failed" || exit 1

if [[ -n "${GIT_NAME}" ]]; then
    git config --system user.name "${GIT_NAME}"
fi
if [[ -n "${GIT_EMAIL}" ]]; then
    git config --system user.email "${GIT_EMAIL}"
fi

mkdir -p "${WORKSPACE_DIR}"

if [[ -n "${ANTHROPIC_API_KEY}" ]]; then
    printf 'export ANTHROPIC_API_KEY=%q\n' "${ANTHROPIC_API_KEY}" > /etc/profile.d/claude-code.sh
    chmod 644 /etc/profile.d/claude-code.sh
fi

if [[ "${CREATE_DEV_USER}" == "yes" ]]; then
    useradd -m -s /bin/bash -G sudo "${DEV_USER}" &
    monitor $! --style "$SPINNER_LOADING_STYLE" --message "Creating dev user '${DEV_USER}'" \
        --success_msg "Dev user created" --error_msg "Failed to create dev user" || exit 1

    if [[ -n "${DEV_PASSWORD}" ]]; then
        echo "${DEV_USER}:${DEV_PASSWORD}" | chpasswd
    else
        passwd -l "${DEV_USER}" >/dev/null
    fi

    if [[ -n "${DEV_SSH_KEY}" ]]; then
        install -d -m 700 -o "${DEV_USER}" -g "${DEV_USER}" "/home/${DEV_USER}/.ssh"
        echo "${DEV_SSH_KEY}" >> "/home/${DEV_USER}/.ssh/authorized_keys"
        chmod 600 "/home/${DEV_USER}/.ssh/authorized_keys"
        chown "${DEV_USER}:${DEV_USER}" "/home/${DEV_USER}/.ssh/authorized_keys"
    fi

    chown "${DEV_USER}:${DEV_USER}" "${WORKSPACE_DIR}"
fi

if [[ "${ENABLE_SSH}" == "yes" ]]; then
    install openssh-server &
    monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing SSH server" \
        --success_msg "SSH server installed" --error_msg "SSH server installation failed" || exit 1

    sed -i "s/^#\?Port .*/Port ${SSH_PORT}/" /etc/ssh/sshd_config
    if [[ -n "${CT_PASSWORD}" || -n "${DEV_PASSWORD}" ]]; then
        sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config
    fi
    if [[ -n "${CT_PASSWORD}" ]]; then
        sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin yes/' /etc/ssh/sshd_config
    fi

    systemctl enable --now ssh &
    monitor $! --style "$SPINNER_LOADING_STYLE" --message "Starting SSH service" \
        --success_msg "SSH service started" --error_msg "Failed to start SSH service" || exit 1
fi

claude --version &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Verifying Claude Code install" \
    --success_msg "Claude Code is ready" --error_msg "Claude Code verification failed" || exit 1
CONTAINER_SCRIPT_EOD

container shell-script --name "$CT_NAME" --path /opt/claude-code-setup.sh \
    --env "NODE_MAJOR=$NODE_MAJOR" \
    --env "GIT_NAME=$GIT_NAME" \
    --env "GIT_EMAIL=$GIT_EMAIL" \
    --env "ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY" \
    --env "WORKSPACE_DIR=$WORKSPACE_DIR" \
    --env "CREATE_DEV_USER=$CREATE_DEV_USER" \
    --env "DEV_USER=$DEV_USER" \
    --env "DEV_PASSWORD=$DEV_PASSWORD" \
    --env "DEV_SSH_KEY=$DEV_SSH_KEY" \
    --env "ENABLE_SSH=$ENABLE_SSH" \
    --env "SSH_PORT=$SSH_PORT" \
    --env "CT_PASSWORD=$CT_PASSWORD" \
    --env "SPINNER_LOADING_STYLE=$SPINNER_LOADING_STYLE" \
    --style "$SPINNER_LOADING_STYLE" &
monitor $! --style "$SPINNER_LOADING_STYLE" \
    --message "Deploying setup script" \
    --success_msg "Setup script deployed" \
    --error_msg "Setup script deployment failed" || exit 1

container exec --name "$CT_NAME" -- /opt/claude-code-setup.sh &
monitor $! --style "$SPINNER_LOADING_STYLE" \
    --message "Installing Claude Code development environment" \
    --success_msg "Claude Code development environment ready" \
    --error_msg "Claude Code setup failed" || exit 1

# ─── Host Cleanup ─────────────────────────────────────────────────────────────

clean &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Cleaning up" \
    --success_msg "Cleanup complete" --error_msg "Cleanup failed"

info "Claude Code installed successfully in container '$CT_NAME'!"
info "Workspace directory: ${WORKSPACE_DIR}"
if [[ "$ENABLE_SSH" == "yes" ]]; then
    info "SSH is enabled on port ${SSH_PORT}."
fi
if [[ -n "$ANTHROPIC_API_KEY" ]]; then
    warn "ANTHROPIC_API_KEY was stored in plaintext at /etc/profile.d/claude-code.sh inside the container."
else
    info "No API key was provided — run 'claude' inside the container to log in interactively."
fi
info "Enter the container with: container enter --name $CT_NAME"
info "Then run 'claude' from ${WORKSPACE_DIR} to start developing."
