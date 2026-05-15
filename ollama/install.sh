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

# ─── Setup Inside Container ───────────────────────────────────────────────────

info "Installing Ollama in container '$CT_NAME'..."

CONTAINER_SCRIPT
#!/bin/bash
apt-get update -qq
apt-get install -y curl ca-certificates
curl -fsSL https://ollama.com/install.sh | sh
mkdir -p /etc/systemd/system/ollama.service.d
printf '[Service]\nEnvironment="OLLAMA_HOST=0.0.0.0:${OLLAMA_PORT}"\n' \
    > /etc/systemd/system/ollama.service.d/override.conf
systemctl daemon-reload
systemctl enable --now ollama
if [[ -n "${OLLAMA_MODEL}" ]]; then
    ollama pull "${OLLAMA_MODEL}"
fi
CONTAINER_SCRIPT_EOD

container shell-script --name "$CT_NAME" --path /opt/ollama-setup.sh \
    --style "$SPINNER_LOADING_STYLE" &
monitor $! --style "$SPINNER_LOADING_STYLE" \
    --message "Deploying Ollama setup script" \
    --success_msg "Setup script deployed" \
    --error_msg "Setup script deployment failed" || exit 1

container exec --name "$CT_NAME" -- /opt/ollama-setup.sh &
monitor $! --style "$SPINNER_LOADING_STYLE" \
    --message "Installing Ollama" \
    --success_msg "Ollama ready" \
    --error_msg "Ollama setup failed" || exit 1

# ─── Host Cleanup ─────────────────────────────────────────────────────────────

clean &
monitor $! --style "$SPINNER_LOADING_STYLE" \
    --message "Cleaning up" \
    --success_msg "Cleanup complete" \
    --error_msg "Cleanup failed"

info "Ollama installed successfully in container '$CT_NAME'!"
info "Access Ollama API at: http://<container-ip>:${OLLAMA_PORT}"
