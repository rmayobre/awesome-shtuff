#!/bin/bash
source <(curl -sL https://raw.githubusercontent.com/rmayobre/shtuff/v1.2.0/shtuff-remote.sh)

# ─── User Configuration ───────────────────────────────────────────────────────

info "Configuring Ollama host installation..."

question "Ollama listen port [11434]" && OLLAMA_PORT="${answer:-11434}"

question "Ollama listen address [0.0.0.0]" && OLLAMA_HOST_ADDR="${answer:-0.0.0.0}"

question "Pull a model after install? (e.g. llama3, mistral — leave blank to skip)" \
    && OLLAMA_MODEL="${answer:-}"

# ─── Dependencies ─────────────────────────────────────────────────────────────

apt-get update -qq &
monitor $! --style "$SPINNER_LOADING_STYLE" \
    --message "Updating packages" \
    --success_msg "Packages updated" \
    --error_msg "Package update failed" || exit 1

apt-get install -y curl ca-certificates &
monitor $! --style "$SPINNER_LOADING_STYLE" \
    --message "Installing dependencies" \
    --success_msg "Dependencies installed" \
    --error_msg "Dependency installation failed" || exit 1

# ─── Ollama Installation ──────────────────────────────────────────────────────

info "Installing Ollama on host..."

curl -fsSL https://ollama.com/install.sh | sh &
monitor $! --style "$SPINNER_LOADING_STYLE" \
    --message "Installing Ollama" \
    --success_msg "Ollama installed" \
    --error_msg "Ollama installation failed" || exit 1

# ─── Service Configuration ────────────────────────────────────────────────────

mkdir -p /etc/systemd/system/ollama.service.d
cat > /etc/systemd/system/ollama.service.d/override.conf <<EOF
[Service]
Environment="OLLAMA_HOST=${OLLAMA_HOST_ADDR}:${OLLAMA_PORT}"
EOF

systemctl daemon-reload &
monitor $! --style "$SPINNER_LOADING_STYLE" \
    --message "Reloading systemd" \
    --success_msg "Systemd reloaded" \
    --error_msg "Systemd reload failed" || exit 1

systemctl enable --now ollama &
monitor $! --style "$SPINNER_LOADING_STYLE" \
    --message "Enabling Ollama service" \
    --success_msg "Ollama service enabled and started" \
    --error_msg "Failed to enable Ollama service" || exit 1

# ─── Optional Model Pull ──────────────────────────────────────────────────────

if [[ -n "$OLLAMA_MODEL" ]]; then
    ollama pull "$OLLAMA_MODEL" &
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

info "Ollama installed successfully on host!"
info "Access Ollama API at: http://${OLLAMA_HOST_ADDR}:${OLLAMA_PORT}"
