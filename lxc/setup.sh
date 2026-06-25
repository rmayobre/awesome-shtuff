#!/bin/bash
source <(curl -sL https://raw.githubusercontent.com/rmayobre/shtuff/main/shtuff-remote.sh)

# ─── User Configuration ───────────────────────────────────────────────────────

info "Configuring LXC host environment..."

question "LXC bridge IP address [10.0.3.1]" && LXC_BRIDGE_IP="${answer:-10.0.3.1}"

# Derive /24 subnet values from the bridge IP
LXC_SUBNET="${LXC_BRIDGE_IP%.*}.0/24"
LXC_NETMASK="255.255.255.0"
LXC_DHCP_RANGE="${LXC_BRIDGE_IP%.*}.2,${LXC_BRIDGE_IP%.*}.254"

if ! confirm "This will modify kernel parameters and network settings on this host. Continue?"; then
    info "Aborted."
    exit 0
fi

# ─── Install LXC ─────────────────────────────────────────────────────────────

info "Installing LXC..."

update &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Updating packages" \
    --success_msg "Packages updated" --error_msg "Package update failed" || exit 1

install lxc lxc-utils uidmap &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Installing LXC" \
    --success_msg "LXC installed" --error_msg "LXC installation failed" || exit 1

# ─── Network Bridge Configuration ─────────────────────────────────────────────

# Without a bridge and lxc-net, containers have no network — every container
# creation will fail or produce unreachable containers.
info "Configuring LXC network bridge..."

cat > /etc/default/lxc-net <<EOF || { error "Failed to write LXC network configuration"; exit 1; }
USE_LXC_BRIDGE="true"
LXC_BRIDGE="lxcbr0"
LXC_ADDR="${LXC_BRIDGE_IP}"
LXC_NETMASK="${LXC_NETMASK}"
LXC_NETWORK="${LXC_SUBNET}"
LXC_DHCP_RANGE="${LXC_DHCP_RANGE}"
LXC_DHCP_MAX="253"
LXC_IPV6_ADDR=""
LXC_IPV6_MASK=""
LXC_IPV6_NETWORK=""
LXC_IPV6_NAT="false"
EOF

# ─── Default Container Configuration ─────────────────────────────────────────

# Without this file, newly created containers have no network interface.
# AppArmor profile "generated" is more permissive than the default strict
# profile and prevents containers from failing to start due to AppArmor denials.
# allow_nesting lets containers run their own systemd and nested containers.
info "Writing default container configuration..."

mkdir -p /etc/lxc || { error "Failed to create /etc/lxc directory"; exit 1; }

cat > /etc/lxc/default.conf <<EOF || { error "Failed to write LXC default configuration"; exit 1; }
lxc.net.0.type = veth
lxc.net.0.link = lxcbr0
lxc.net.0.flags = up
lxc.apparmor.profile = generated
lxc.apparmor.allow_nesting = 1
EOF

# ─── Kernel Parameters ────────────────────────────────────────────────────────

# ip_forward=0 means containers can reach the bridge but not the internet.
# This affects every container on the host simultaneously.
info "Configuring kernel parameters..."

cat > /etc/sysctl.d/99-lxc.conf <<EOF || { error "Failed to write sysctl configuration"; exit 1; }
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF

sysctl -p /etc/sysctl.d/99-lxc.conf &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Applying kernel parameters" \
    --success_msg "Kernel parameters applied" --error_msg "Failed to apply kernel parameters" || exit 1

# Older Ubuntu/Debian kernels gate user namespaces behind this sysctl.
# Without it, all unprivileged container creation fails. Silently skip if the
# kernel doesn't expose this key (Ubuntu 24.04+ removed it, controls via AppArmor instead).
if sysctl kernel.unprivileged_userns_clone > /dev/null 2>&1; then
    sysctl -w kernel.unprivileged_userns_clone=1 > /dev/null 2>&1 \
        && echo "kernel.unprivileged_userns_clone = 1" >> /etc/sysctl.d/99-lxc.conf \
        || warn "Could not enable unprivileged user namespaces"
fi

# ─── UID/GID Mapping ─────────────────────────────────────────────────────────

# /etc/subuid and /etc/subgid must grant root a subordinate ID range for
# unprivileged containers. Without these entries, lxc-usernsexec fails and
# no unprivileged container can start.
info "Configuring UID/GID mapping for unprivileged containers..."

grep -q "^root:" /etc/subuid 2>/dev/null \
    || echo "root:100000:65536" >> /etc/subuid \
    || { error "Failed to configure subuid mapping"; exit 1; }

grep -q "^root:" /etc/subgid 2>/dev/null \
    || echo "root:100000:65536" >> /etc/subgid \
    || { error "Failed to configure subgid mapping"; exit 1; }

# ─── Enable lxc-net Service ───────────────────────────────────────────────────

systemctl enable --now lxc-net &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Starting LXC network bridge" \
    --success_msg "LXC network bridge started" --error_msg "Failed to start LXC network bridge" || exit 1

# ─── Host Cleanup ─────────────────────────────────────────────────────────────

clean &
monitor $! --style "$SPINNER_LOADING_STYLE" --message "Cleaning up" \
    --success_msg "Cleanup complete" --error_msg "Cleanup failed"

info "LXC setup complete!"
info "  Bridge : lxcbr0 (${LXC_BRIDGE_IP})"
info "  Subnet : ${LXC_SUBNET}"
info "  DHCP   : ${LXC_DHCP_RANGE}"
