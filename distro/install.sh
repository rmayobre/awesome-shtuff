#!/bin/bash

# ─── Bootstrap: Source shtuff from release tarball ───────────────────────────

SHTUFF_TMP=$(mktemp -d)
curl -sL "https://github.com/rmayobre/shtuff/releases/download/v1.2.0/shtuff-v1.2.0.tar.gz" \
    | tar -xz -C "$SHTUFF_TMP"
source "$SHTUFF_TMP/shtuff.sh"

# ─── User Configuration ───────────────────────────────────────────────────────

info "Configuring distro container installation..."

if [[ -z "${CT_DIST:-}" ]]; then
    options "Select distribution" "debian" "ubuntu" "alpine" && CT_DIST="$answer"
fi

if [[ -z "${CT_RELEASE:-}" ]]; then
    case "$CT_DIST" in
        debian)
            options "Select Debian release (11=bullseye, 12=bookworm)" "bullseye" "bookworm" \
                && CT_RELEASE="$answer"
            ;;
        ubuntu)
            options "Select Ubuntu release (20.04=focal, 22.04=jammy, 24.04=noble)" "focal" "jammy" "noble" \
                && CT_RELEASE="$answer"
            ;;
        alpine)
            options "Select Alpine release" "3.18" "3.19" "3.20" \
                && CT_RELEASE="$answer"
            ;;
    esac
fi

if [[ -z "${CT_NAME:-}" ]]; then
    question "Container name [$CT_DIST]" && CT_NAME="${answer:-$CT_DIST}"
fi

if [[ -z "${CT_HOSTNAME:-}" ]]; then
    question "Container hostname [$CT_DIST]" && CT_HOSTNAME="${answer:-$CT_DIST}"
fi

if [[ -n "${CT_MEMORY:-}" ]]; then
    info "Using CT_MEMORY from environment: ${CT_MEMORY} MB"
else
    question "Memory in MB [256]" && CT_MEMORY="${answer:-256}"
fi

if [[ -n "${CT_CORES:-}" ]]; then
    info "Using CT_CORES from environment: ${CT_CORES}"
else
    question "CPU cores [1]" && CT_CORES="${answer:-1}"
fi

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

info "Creating $CT_DIST ($CT_RELEASE) container..."

container create \
    --name "$CT_NAME" \
    --hostname "$CT_HOSTNAME" \
    --memory "$CT_MEMORY" \
    --cores "$CT_CORES" \
    --disk-size "$CT_DISK" \
    --dist "$CT_DIST" \
    --release "$CT_RELEASE" \
    $CT_TEMPLATE_FLAG \
    --style "$SPINNER_LOADING_STYLE" || exit 1

container start --name "$CT_NAME" --style "$SPINNER_LOADING_STYLE" || exit 1

# ─── Alpine: Install bash before sourcing shtuff ─────────────────────────────
# Alpine ships with ash; bash is required to source shtuff inside the container.

if [[ "$CT_DIST" == "alpine" ]]; then
    container exec --name "$CT_NAME" -- /bin/sh -c "apk update" &
    monitor $! --style "$SPINNER_LOADING_STYLE" --message "Updating packages" \
        --success_msg "Packages updated" --error_msg "Package update failed" || exit 1

    container exec --name "$CT_NAME" -- /bin/sh -c "apk upgrade" &
    monitor $! --style "$SPINNER_LOADING_STYLE" --message "Upgrading packages" \
        --success_msg "Packages upgraded" --error_msg "Package upgrade failed" || exit 1

    container exec --name "$CT_NAME" -- /bin/sh -c "apk add bash" &
    monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing bash" \
        --success_msg "bash installed" --error_msg "bash installation failed" || exit 1
fi

# ─── Copy shtuff into Container ───────────────────────────────────────────────

container push --name "$CT_NAME" --source "$SHTUFF_TMP" --dest "/opt/shtuff"

container exec --name "$CT_NAME" -- bash -c \
    "echo 'source /opt/shtuff/shtuff.sh' > /etc/profile.d/shtuff.sh && chmod +x /etc/profile.d/shtuff.sh" &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Setting up shtuff in container" \
    --success_msg "shtuff configured" --error_msg "shtuff setup failed" || exit 1

# ─── System Setup Inside Container ────────────────────────────────────────────

container exec --name "$CT_NAME" -- bash -c \
    "source /opt/shtuff/shtuff.sh && update" &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Updating packages" \
    --success_msg "Packages updated" --error_msg "Package update failed" || exit 1

container exec --name "$CT_NAME" -- bash -c \
    "source /opt/shtuff/shtuff.sh && install ca-certificates curl wget" &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing base utilities" \
    --success_msg "Base utilities installed" --error_msg "Base utility installation failed" || exit 1

# ─── Host Cleanup ─────────────────────────────────────────────────────────────

rm -rf "$SHTUFF_TMP"

clean &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Cleaning up" \
    --success_msg "Cleanup complete" --error_msg "Cleanup failed"

info "$CT_DIST ($CT_RELEASE) installed successfully in container '$CT_NAME'!"
