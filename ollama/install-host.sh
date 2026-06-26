#!/bin/bash
source <(curl -sL https://raw.githubusercontent.com/rmayobre/shtuff/main/shtuff-remote.sh)

# ─── User Configuration ───────────────────────────────────────────────────────

info "Configuring Ollama host installation..."

question "Ollama listen port [11434]" && OLLAMA_PORT="${answer:-11434}"

question "Ollama listen address [0.0.0.0]" && OLLAMA_HOST_ADDR="${answer:-0.0.0.0}"

question "Pull a model after install? (e.g. llama3, mistral — leave blank to skip)" \
    && OLLAMA_MODEL="${answer:-}"

# ─── Dependencies ─────────────────────────────────────────────────────────────

update --style "$SPINNER_LOADING_STYLE" \
    --message "Updating packages" \
    --success_msg "Packages updated" \
    --error_msg "Package update failed" || exit 1

install curl ca-certificates --style "$SPINNER_LOADING_STYLE" \
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

service \
    --name "ollama" \
    --description "Ollama Large Language Model Server" \
    --exec-start "/usr/local/bin/ollama serve" \
    --user "ollama" \
    --environment "OLLAMA_HOST=${OLLAMA_HOST_ADDR}:${OLLAMA_PORT}" &
monitor $! --style "$SPINNER_LOADING_STYLE" \
    --message "Configuring Ollama service" \
    --success_msg "Ollama service configured and started" \
    --error_msg "Failed to configure Ollama service" || exit 1

# ─── Optional Model Pull ──────────────────────────────────────────────────────

if [[ -n "$OLLAMA_MODEL" ]]; then
    ollama pull "$OLLAMA_MODEL" &
    monitor $! --style "$SPINNER_LOADING_STYLE" \
        --message "Pulling model '$OLLAMA_MODEL'" \
        --success_msg "Model '$OLLAMA_MODEL' pulled" \
        --error_msg "Failed to pull model '$OLLAMA_MODEL'" || exit 1
fi

# ─── Host Cleanup ─────────────────────────────────────────────────────────────

clean --style "$SPINNER_LOADING_STYLE" \
    --message "Cleaning up" \
    --success_msg "Cleanup complete" \
    --error_msg "Cleanup failed"

info "Ollama installed successfully on host!"
info "Access Ollama API at: http://${OLLAMA_HOST_ADDR}:${OLLAMA_PORT}"
