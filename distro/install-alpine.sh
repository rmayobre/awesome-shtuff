#!/bin/bash
source <(curl -sL https://raw.githubusercontent.com/rmayobre/shtuff/v1.2.0/shtuff-remote.sh)

# ─── User Configuration ───────────────────────────────────────────────────────

info "Configuring Alpine container installation..."

options "Select Alpine release" "3.18" "3.19" "3.20" \
    && CT_RELEASE="$answer"

question "Container name [alpine]"     && CT_NAME="${answer:-alpine}"
question "Container hostname [alpine]" && CT_HOSTNAME="${answer:-alpine}"

# Memory: use CT_MEMORY env var if set, otherwise prompt
if [[ -n "${CT_MEMORY:-}" ]]; then
    info "Using CT_MEMORY from environment: ${CT_MEMORY} MB"
else
    question "Memory in MB [256]" && CT_MEMORY="${answer:-256}"
fi

# CPU cores: use CT_CORES env var if set, otherwise prompt
if [[ -n "${CT_CORES:-}" ]]; then
    info "Using CT_CORES from environment: ${CT_CORES}"
else
    question "CPU cores [1]" && CT_CORES="${answer:-1}"
fi

# Disk size: use CT_DISK env var if set, otherwise prompt
if [[ -n "${CT_DISK:-}" ]]; then
    info "Using CT_DISK from environment: ${CT_DISK} GB"
else
    question "Disk size in GB [4]" && CT_DISK="${answer:-4}"
fi

question "PCT template path (leave blank for LXC auto-download)" \
    && CT_TEMPLATE="${answer:-}"

CT_TEMPLATE_FLAG=""
if [[ -n "$CT_TEMPLATE" ]]; then
    CT_TEMPLATE_FLAG="--template $CT_TEMPLATE"
fi

# ─── Container Creation ───────────────────────────────────────────────────────

info "Creating Alpine ($CT_RELEASE) container..."

container create \
    --name "$CT_NAME" \
    --hostname "$CT_HOSTNAME" \
    --memory "$CT_MEMORY" \
    --cores "$CT_CORES" \
    --disk-size "$CT_DISK" \
    --dist "alpine" \
    --release "$CT_RELEASE" \
    $CT_TEMPLATE_FLAG \
    --style "$SPINNER_LOADING_STYLE" || exit 1

container start --name "$CT_NAME" --style "$SPINNER_LOADING_STYLE" || exit 1

# ─── System Setup Inside Container ────────────────────────────────────────────

container exec --name "$CT_NAME" -- apk update &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Updating packages" \
    --success_msg "Packages updated" --error_msg "Package update failed" || exit 1

container exec --name "$CT_NAME" -- apk upgrade &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Upgrading packages" \
    --success_msg "Packages upgraded" --error_msg "Package upgrade failed" || exit 1

container exec --name "$CT_NAME" -- apk add ca-certificates curl wget &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing base utilities" \
    --success_msg "Base utilities installed" --error_msg "Base utility installation failed" || exit 1

# ─── Host Cleanup ─────────────────────────────────────────────────────────────

clean &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Cleaning up" \
    --success_msg "Cleanup complete" --error_msg "Cleanup failed"

info "Alpine ($CT_RELEASE) installed successfully in container '$CT_NAME'!"
