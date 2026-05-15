#!/bin/bash
source <(curl -sL https://raw.githubusercontent.com/rmayobre/shtuff/v1.3.0-beta/shtuff-remote.sh)
shopt -s expand_aliases

# ─── User Configuration ───────────────────────────────────────────────────────

info "Configuring Ollama container installation..."

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
question "Container name [ollama]"     && CT_NAME="${answer:-ollama}"
question "Container hostname [ollama]" && CT_HOSTNAME="${answer:-ollama}"
question "Memory in MB [2048]"         && CT_MEMORY="${answer:-2048}"
question "CPU cores [2]"               && CT_CORES="${answer:-2}"
question "Disk size in GB [20]"        && CT_DISK="${answer:-20}"

# Ollama configuration
question "Ollama listen port [11434]"  && OLLAMA_PORT="${answer:-11434}"

CT_GPU=""
CT_GPU_PCIE="no"
confirm "Enable GPU passthrough (requires GPU on host)?" && ENABLE_GPU="$answer"
if [[ "$ENABLE_GPU" == "true" || "$ENABLE_GPU" == "yes" ]]; then
    gpu_select && CT_GPU="$answer"
    confirm "Enable PCIe passthrough mode (PCT only)?" && CT_GPU_PCIE="$answer"
fi

question "Pull a model after install? (e.g. llama3, mistral — leave blank to skip)" \
    && OLLAMA_MODEL="${answer:-}"

# ─── Container Creation ───────────────────────────────────────────────────────

info "Creating container for Ollama..."

CONTAINER_ARGS=(
    --name "$CT_NAME"
    --hostname "$CT_HOSTNAME"
    --memory "$CT_MEMORY"
    --cores "$CT_CORES"
    --disk-size "$CT_DISK"
    --dist "$CT_DIST"
    --release "$CT_RELEASE"
    --style "$SPINNER_LOADING_STYLE"
)

if [[ -n "$CT_GPU" ]]; then
    CONTAINER_ARGS+=(--gpu "$CT_GPU")
    if [[ "$CT_GPU_PCIE" == "true" || "$CT_GPU_PCIE" == "yes" ]]; then
        CONTAINER_ARGS+=(--pcie)
    fi
fi

container create "${CONTAINER_ARGS[@]}" || exit 1

container start --name "$CT_NAME" --style "$SPINNER_LOADING_STYLE" || exit 1

# ─── Dependencies Inside Container ────────────────────────────────────────────

CONTAINER_SCRIPT
#!/bin/bash
apt-get update -qq
apt-get install -y curl ca-certificates
CONTAINER_SCRIPT_EOD

container shell-script --name "$CT_NAME" --path /opt/ollama-deps.sh \
    --style "$SPINNER_LOADING_STYLE" &
monitor $! --style "$SPINNER_LOADING_STYLE" \
    --message "Deploying dependency script" \
    --success_msg "Dependency script deployed" \
    --error_msg "Dependency script deployment failed" || exit 1

container exec --name "$CT_NAME" -- /opt/ollama-deps.sh &
monitor $! --style "$SPINNER_LOADING_STYLE" \
    --message "Installing dependencies" \
    --success_msg "Dependencies installed" \
    --error_msg "Dependency installation failed" || exit 1

# ─── Ollama Installation ──────────────────────────────────────────────────────

info "Installing Ollama in container '$CT_NAME'..."

CONTAINER_SCRIPT
#!/bin/bash
curl -fsSL https://ollama.com/install.sh | sh
CONTAINER_SCRIPT_EOD

container shell-script --name "$CT_NAME" --path /opt/ollama-install.sh \
    --style "$SPINNER_LOADING_STYLE" &
monitor $! --style "$SPINNER_LOADING_STYLE" \
    --message "Deploying Ollama installer" \
    --success_msg "Installer deployed" \
    --error_msg "Installer deployment failed" || exit 1

container exec --name "$CT_NAME" -- /opt/ollama-install.sh &
monitor $! --style "$SPINNER_LOADING_STYLE" \
    --message "Installing Ollama" \
    --success_msg "Ollama installed" \
    --error_msg "Ollama installation failed" || exit 1

# ─── Service Configuration ────────────────────────────────────────────────────

# Configure listen address/port
CONTAINER_SCRIPT
#!/bin/bash
mkdir -p /etc/systemd/system/ollama.service.d
printf '[Service]\nEnvironment="OLLAMA_HOST=0.0.0.0:${OLLAMA_PORT}"\n' \
    > /etc/systemd/system/ollama.service.d/override.conf
CONTAINER_SCRIPT_EOD

container shell-script --name "$CT_NAME" --path /opt/ollama-service.sh \
    --style "$SPINNER_LOADING_STYLE" &
monitor $! --style "$SPINNER_LOADING_STYLE" \
    --message "Deploying service configuration script" \
    --success_msg "Service configuration script deployed" \
    --error_msg "Service configuration script deployment failed" || exit 1

container exec --name "$CT_NAME" -- /opt/ollama-service.sh &
monitor $! --style "$SPINNER_LOADING_STYLE" \
    --message "Configuring Ollama listen address" \
    --success_msg "Ollama listener configured" \
    --error_msg "Listener configuration failed" || exit 1

container exec --name "$CT_NAME" -- systemctl daemon-reload &
monitor $! --style "$SPINNER_LOADING_STYLE" \
    --message "Reloading systemd" \
    --success_msg "Systemd reloaded" \
    --error_msg "Systemd reload failed" || exit 1

container exec --name "$CT_NAME" -- systemctl enable --now ollama &
monitor $! --style "$SPINNER_LOADING_STYLE" \
    --message "Enabling Ollama service" \
    --success_msg "Ollama service enabled and started" \
    --error_msg "Failed to enable Ollama service" || exit 1

# ─── Optional Model Pull ──────────────────────────────────────────────────────

if [[ -n "$OLLAMA_MODEL" ]]; then
    container exec --name "$CT_NAME" -- ollama pull "$OLLAMA_MODEL" &
    monitor $! --style "$SPINNER_LOADING_STYLE" \
        --message "Pulling model '$OLLAMA_MODEL'" \
        --success_msg "Model '$OLLAMA_MODEL' pulled" \
        --error_msg "Failed to pull model '$OLLAMA_MODEL'" || exit 1
fi

# ─── Host Cleanup ─────────────────────────────────────────────────────────────

clean &
monitor $! --style "$SPINNER_LOADING_STYLE" \
    --message "Cleaning up" \
    --success_msg "Cleanup complete" \
    --error_msg "Cleanup failed"

info "Ollama installed successfully in container '$CT_NAME'!"
info "Access Ollama API at: http://<container-ip>:${OLLAMA_PORT}"
