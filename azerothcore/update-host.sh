#!/bin/bash
source <(curl -sL https://raw.githubusercontent.com/rmayobre/shtuff/main/shtuff-remote.sh)

# ─── User Configuration ────────────────────────────────────────────────────────

info "Configuring AzerothCore host update..."

if [[ ! -d /opt/azerothcore ]]; then
    error "AzerothCore installation not found at /opt/azerothcore. Run install-host.sh first."
    exit 1
fi

confirm "This will pull the latest AzerothCore source and rebuild on this host. This can take 30-60 minutes. Continue?" \
    && [[ "$answer" != "yes" ]] && { info "Aborted."; exit 0; }

# Client data is large and rarely changes, so only re-download it on request.
confirm "Update client data too?" && UPDATE_CLIENT_DATA="$answer"

CLIENT_DATA_URL=""
if [[ "$UPDATE_CLIENT_DATA" == "yes" ]]; then
    question "Client data zip URL" && CLIENT_DATA_URL="$answer"

    if [[ -z "$CLIENT_DATA_URL" ]]; then
        error "Client data zip URL is required to update client data."
        exit 1
    fi
fi

# ─── AzerothCore Update ─────────────────────────────────────────────────────────

info "Updating AzerothCore on this host..."
warn "The rebuild step takes 30-60 minutes. Do not interrupt the process."

systemctl stop acore-world &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Stopping worldserver" \
    --success_msg "Worldserver stopped" --error_msg "Failed to stop worldserver" || exit 1

systemctl stop acore-auth &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Stopping authserver" \
    --success_msg "Authserver stopped" --error_msg "Failed to stop authserver" || exit 1

git -C /opt/azerothcore pull --ff-only &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Pulling latest AzerothCore source" \
    --success_msg "Source updated" --error_msg "Failed to pull latest source" || exit 1

cmake -S /opt/azerothcore -B /opt/azerothcore/build \
    -DCMAKE_INSTALL_PREFIX=/opt/azerothcore/env/dist/ \
    -DCMAKE_C_COMPILER=/usr/bin/clang \
    -DCMAKE_CXX_COMPILER=/usr/bin/clang++ \
    -DWITH_WARNINGS=1 \
    -DTOOLS_BUILD=all \
    -DSCRIPTS=static \
    -DMODULES=static &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Configuring build with CMake" \
    --success_msg "CMake configuration complete" --error_msg "CMake configuration failed" || exit 1

make -j$(nproc) -C /opt/azerothcore/build &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Rebuilding AzerothCore (this takes 30-60 minutes)" \
    --success_msg "Build complete" --error_msg "Build failed" || exit 1

make install -C /opt/azerothcore/build &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing AzerothCore binaries" \
    --success_msg "Binaries installed" --error_msg "Binary installation failed" || exit 1

if [[ -n "${CLIENT_DATA_URL}" ]]; then
    install unzip &
    monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing unzip" \
        --success_msg "unzip installed" --error_msg "Failed to install unzip" || exit 1

    curl -sL "${CLIENT_DATA_URL}" -o /tmp/azerothcore-client-data.zip &
    monitor $! --style "$SPINNER_LOADING_STYLE" --message "Downloading client data" \
        --success_msg "Client data downloaded" --error_msg "Failed to download client data" || exit 1

    unzip -oq /tmp/azerothcore-client-data.zip -d /opt/azerothcore/env/dist/bin &
    monitor $! --style "$SPINNER_LOADING_STYLE" --message "Extracting client data" \
        --success_msg "Client data extracted" --error_msg "Failed to extract client data" || exit 1

    rm -f /tmp/azerothcore-client-data.zip
fi

systemctl start acore-auth &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Starting authserver" \
    --success_msg "Authserver started" --error_msg "Failed to start authserver" || exit 1

systemctl start acore-world &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Starting worldserver" \
    --success_msg "Worldserver started" --error_msg "Failed to start worldserver" || exit 1

# ─── Host Cleanup ───────────────────────────────────────────────────────────────

clean &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Cleaning up" \
    --success_msg "Cleanup complete" --error_msg "Cleanup failed"

info "AzerothCore updated successfully on this host!"
info "Existing authserver.conf/worldserver.conf were left untouched."
info "Worldserver will auto-apply any pending database migrations on startup."

if [[ -n "$CLIENT_DATA_URL" ]]; then
    info "Client data was re-downloaded and extracted into /opt/azerothcore/env/dist/bin/."
else
    info "Client data was left untouched."
fi
