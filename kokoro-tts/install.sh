#!/bin/bash
source <(curl -sL https://raw.githubusercontent.com/rmayobre/shtuff/main/shtuff-remote.sh)

# ─── User Configuration ───────────────────────────────────────────────────────

info "Configuring Kokoro TTS (Kokoro-FastAPI) container installation..."

# Distribution
options "Select distribution" \
    --choice "debian" \
    --choice "ubuntu" \
    && CT_DIST="$answer"

case "$CT_DIST" in
    debian)
        options "Select Debian release" \
            --choice "bookworm" \
            --choice "trixie" \
            && CT_RELEASE="$answer"
        ;;
    ubuntu)
        options "Select Ubuntu release" \
            --choice "jammy" \
            --choice "noble" \
            && CT_RELEASE="$answer"
        ;;
esac

# Container configuration
question "Container name [kokoro-tts]"     && CT_NAME="${answer:-kokoro-tts}"
question "Container hostname [kokoro-tts]" && CT_HOSTNAME="${answer:-kokoro-tts}"
question "Memory in MB [4096]"             && CT_MEMORY="${answer:-4096}"
question "CPU cores [4]"                   && CT_CORES="${answer:-4}"
question "Disk size in GB [20]"            && CT_DISK="${answer:-20}"

# Kokoro configuration
question "API listen port [8880]"          && KOKORO_PORT="${answer:-8880}"
if ! [[ "$KOKORO_PORT" =~ ^[0-9]+$ ]] || (( KOKORO_PORT < 1 || KOKORO_PORT > 65535 )); then
    error "Invalid port: '$KOKORO_PORT'"
    exit 1
fi

CT_GPU=""
CT_GPU_PCIE="no"
KOKORO_USE_GPU="false"
confirm "Enable GPU (NVIDIA CUDA) acceleration?" && ENABLE_GPU="$answer"
if [[ "$ENABLE_GPU" == "true" || "$ENABLE_GPU" == "yes" ]]; then
    KOKORO_USE_GPU="true"
    gpu_select && CT_GPU="$answer"
    confirm "Enable PCIe passthrough mode (PCT only)?" && CT_GPU_PCIE="$answer"
    warn "The NVIDIA driver must also be available inside the container for CUDA to work."
fi

# ─── Container Creation ───────────────────────────────────────────────────────

info "Creating container for Kokoro TTS..."

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

# ─── Network Configuration ────────────────────────────────────────────────────

info "Configuring network for container '$CT_NAME'..."
container network prompt --name "$CT_NAME" || exit 1

# ─── Setup Inside Container ───────────────────────────────────────────────────

info "Installing Kokoro TTS in container '$CT_NAME'..."

script=$(cat <<'CONTAINER_SCRIPT_EOD'
#!/bin/bash
source <(wget -qO- https://raw.githubusercontent.com/rmayobre/shtuff/main/shtuff-remote.sh)

INSTALL_DIR="/opt/kokoro"

update &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Updating packages" \
    --success_msg "Packages updated" --error_msg "Package update failed" || exit 1

install curl wget git ca-certificates espeak-ng libsndfile1 ffmpeg &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing dependencies" \
    --success_msg "Dependencies installed" --error_msg "Dependency installation failed" || exit 1

# uv manages Python (3.10) and the project's virtualenv
wget -qO- https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin UV_NO_MODIFY_PATH=1 sh &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing uv" \
    --success_msg "uv installed" --error_msg "uv installation failed" || exit 1

git clone --depth 1 https://github.com/remsky/Kokoro-FastAPI.git "$INSTALL_DIR" &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Downloading Kokoro-FastAPI" \
    --success_msg "Kokoro-FastAPI downloaded" --error_msg "Failed to download Kokoro-FastAPI" || exit 1

if [[ "$KOKORO_USE_GPU" == "true" ]]; then
    KOKORO_EXTRA="gpu"
else
    KOKORO_EXTRA="cpu"
fi

(cd "$INSTALL_DIR" && uv venv --python 3.10 && uv pip install -e ".[${KOKORO_EXTRA}]") &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing Python dependencies (${KOKORO_EXTRA})" \
    --success_msg "Python dependencies installed" --error_msg "Python dependency installation failed" || exit 1

(cd "$INSTALL_DIR" && uv run --no-sync python docker/scripts/download_model.py --output api/src/models/v1_0) &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Downloading Kokoro model" \
    --success_msg "Model downloaded" --error_msg "Model download failed" || exit 1

cat > "$INSTALL_DIR/run.sh" <<RUN_EOF
#!/bin/bash
cd "$INSTALL_DIR"
export USE_GPU=${KOKORO_USE_GPU}
export USE_ONNX=false
export PYTHONPATH="$INSTALL_DIR:$INSTALL_DIR/api"
export MODEL_DIR=src/models
export VOICES_DIR=src/voices/v1_0
export WEB_PLAYER_PATH="$INSTALL_DIR/web"
exec uv run --no-sync uvicorn api.src.main:app --host 0.0.0.0 --port ${KOKORO_PORT}
RUN_EOF
chmod +x "$INSTALL_DIR/run.sh"

service \
    --name "kokoro-tts" \
    --description "Kokoro TTS (Kokoro-FastAPI)" \
    --exec-start "$INSTALL_DIR/run.sh" \
    --restart "on-failure" \
    --restart-sec 5 &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Configuring Kokoro TTS service" \
    --success_msg "Kokoro TTS service configured and started" \
    --error_msg "Failed to configure Kokoro TTS service" || exit 1
CONTAINER_SCRIPT_EOD
)

container shell-script --name "$CT_NAME" --path /opt/kokoro-setup.sh \
    --content "$script" \
    --env "KOKORO_PORT=$KOKORO_PORT" \
    --env "KOKORO_USE_GPU=$KOKORO_USE_GPU" \
    --env "SPINNER_LOADING_STYLE=$SPINNER_LOADING_STYLE" \
    --style "$SPINNER_LOADING_STYLE" &
monitor $! --style "$SPINNER_LOADING_STYLE" \
    --message "Deploying Kokoro TTS setup script" \
    --success_msg "Setup script deployed" \
    --error_msg "Setup script deployment failed" || exit 1

container exec --name "$CT_NAME" -- /opt/kokoro-setup.sh &
monitor $! --style "$SPINNER_LOADING_STYLE" \
    --message "Installing Kokoro TTS (this may take several minutes)" \
    --success_msg "Kokoro TTS ready" \
    --error_msg "Kokoro TTS setup failed" || exit 1

# ─── Host Cleanup ─────────────────────────────────────────────────────────────

clean &
monitor $! --style "$SPINNER_LOADING_STYLE" \
    --message "Cleaning up" \
    --success_msg "Cleanup complete" \
    --error_msg "Cleanup failed"

info "Kokoro TTS installed successfully in container '$CT_NAME'!"
info "OpenAI-compatible API: http://<container-ip>:${KOKORO_PORT}/v1/audio/speech"
info "Web UI:                http://<container-ip>:${KOKORO_PORT}/web"
info "API docs:              http://<container-ip>:${KOKORO_PORT}/docs"
