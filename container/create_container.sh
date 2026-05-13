#!/bin/bash
source <(curl -sL https://raw.githubusercontent.com/rmayobre/shtuff/v1.3.0-beta/shtuff-remote.sh)
shopt -s expand_aliases

#IS_DRY_RUN=true
LOG_LEVEL="$INFO_LEVEL"
LOG_FILE="$(mktemp -d)/log.txt"

info "Logs can be found at: $LOG_FILE"

# ─── User Configuration ───────────────────────────────────────────────────────

info "Configuring distro container installation..."

if [[ -z "${CT_DIST:-}" ]]; then
    options "Select distribution" \
        --choice "debian" \
        --choice "ubuntu" \
        && CT_DIST="$answer"
        # --choice "alpine" \-- shtuff is yet compatible with ash shell
        # && CT_DIST="$answer"
fi

if [[ -z "${CT_RELEASE:-}" ]]; then
    case "$CT_DIST" in
        debian)
            options "Select Debian release (11=bullseye, 12=bookworm)" \
                --choice "bullseye" \
                --choice "bookworm" \
                && CT_RELEASE="$answer"
            ;;
        ubuntu)
            options "Select Ubuntu release (20.04=focal, 22.04=jammy, 24.04=noble)" \
                --choice "focal" \
                --choice "jammy" \
                --choice "noble" \
                && CT_RELEASE="$answer"
            ;;
        # shtuff is yet compatible with ash shell.
        # alpine)
        #     options "Select Alpine release" "3.18" "3.19" "3.20" \
        #         && CT_RELEASE="$answer"
        #     ;;
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

if [[ -n "${CT_DISK_TYPE:-}" ]]; then
    info "Using CT_DISK_TYPE from environment: ${CT_DISK_TYPE} GB"
else
    options "Select Storage type" \
        --choice "dir" \
        --choice "btrfs" \
        --choice "zfs" \
        && CT_DISK_TYPE="${answer:-4}"
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
    --storage "$CT_DISK_TYPE" \
    $CT_TEMPLATE_FLAG || exit 1

container start --name "$CT_NAME" --style "$SPINNER_LOADING_STYLE" || exit 1

# ─── System Setup Inside Container ────────────────────────────────────────────

CONTAINER_SCRIPT
#!/bin/bash
apt-get update -qq
apt-get install -y ca-certificates curl wget
CONTAINER_SCRIPT_EOD

container shell-script --name "$CT_NAME" --path /opt/setup.sh \
    --style "$SPINNER_LOADING_STYLE" &
monitor $! --style "$SPINNER_LOADING_STYLE" \
    --message "Deploying setup script" \
    --success_msg "Setup script deployed" \
    --error_msg "Setup script deployment failed" || exit 1

container exec --name "$CT_NAME" -- /opt/setup.sh &
monitor $! --style "$SPINNER_LOADING_STYLE" \
    --message "Installing base utilities" \
    --success_msg "Base utilities installed" \
    --error_msg "Base utility installation failed" || exit 1

# ─── Host Cleanup ─────────────────────────────────────────────────────────────

clean &
monitor $! --style "$SPINNER_LOADING_STYLE" \
    --message "Cleaning up" \
    --success_msg "Cleanup complete" \
    --error_msg "Cleanup failed"

info "$CT_DIST ($CT_RELEASE) installed successfully in container '$CT_NAME'!"
