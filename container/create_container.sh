#!/bin/bash
source <(curl -sL https://raw.githubusercontent.com/rmayobre/shtuff/v1.3.0-beta/shtuff-remote.sh)
shopt -s expand_aliases

#IS_DRY_RUN=true
LOG_LEVEL="$INFO_LEVEL"
LOG_FILE="$(mktemp -d)/log.txt"

info "Logs can be found at: $LOG_FILE"

# ─── User Configuration ───────────────────────────────────────────────────────

info "Configuring distro container installation..."

container prompt || exit 1

container start --name "$CONTAINER_NAME" --style "$SPINNER_LOADING_STYLE" || exit 1

# ─── System Setup Inside Container ────────────────────────────────────────────

CONTAINER_SCRIPT
#!/bin/bash
source <(curl -sL https://raw.githubusercontent.com/rmayobre/shtuff/v1.3.0-beta/shtuff-remote.sh)

apt-get update -qq &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Updating packages" \
    --success_msg "Packages updated" --error_msg "Package update failed" || exit 1

apt-get install -y ca-certificates curl wget &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing base utilities" \
    --success_msg "Base utilities installed" --error_msg "Base utility installation failed" || exit 1
CONTAINER_SCRIPT_EOD

container shell-script --name "$CONTAINER_NAME" --path /opt/setup.sh \
    --style "$SPINNER_LOADING_STYLE" &
monitor $! --style "$SPINNER_LOADING_STYLE" \
    --message "Deploying setup script" \
    --success_msg "Setup script deployed" \
    --error_msg "Setup script deployment failed" || exit 1

container exec --name "$CONTAINER_NAME" -- /opt/setup.sh &
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

info "Container '$CONTAINER_NAME' is ready!"
