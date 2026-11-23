#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_FILE="${SCRIPT_DIR}/packages.txt"
GIT_CONFIG="${SCRIPT_DIR}/config/git.conf"
NETPLAN_SOURCE="${SCRIPT_DIR}/config/99-static-ip.yaml"
PROVISION_CONFIG="${SCRIPT_DIR}/config/provision.conf"
LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/provision-$(date +%F-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

trap 'rc=$?; echo "[ERROR] Provisioning failed at line ${LINENO} (exit ${rc}). See ${LOG_FILE}"; exit "$rc"' ERR

echo "=================================================="
echo " Raspberry Pi provisioning"
echo " Started: $(date)"
echo "=================================================="

if [[ $EUID -ne 0 ]]; then
    echo "Run with: sudo ./install.sh"
    exit 1
fi

for f in "$PACKAGE_FILE" "$GIT_CONFIG" "$NETPLAN_SOURCE" "$PROVISION_CONFIG"; do
    [[ -f "$f" ]] || { echo "Missing required file: $f"; exit 1; }
done

# Load trusted, locally maintained configuration files.
# shellcheck disable=SC1090
source "$GIT_CONFIG"
# shellcheck disable=SC1090
source "$PROVISION_CONFIG"

TARGET_USER="${SUDO_USER:-root}"
if [[ "$TARGET_USER" == "root" ]]; then
    TARGET_HOME="/root"
else
    TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
    [[ -n "$TARGET_HOME" && -d "$TARGET_HOME" ]] || {
        echo "Could not determine home directory for $TARGET_USER"; exit 1;
    }
fi

echo "[1/5] Updating APT metadata..."
apt-get update

echo "[2/5] Installing packages from packages.txt..."
mapfile -t PACKAGES < <(
    sed 's/[[:space:]]*#.*$//' "$PACKAGE_FILE" |
    awk 'NF { print $1 }' |
    sort -u
)
((${#PACKAGES[@]} > 0)) || { echo "No packages found."; exit 1; }
printf '  - %s\n' "${PACKAGES[@]}"
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${PACKAGES[@]}"

echo "[3/5] Configuring Git for ${TARGET_USER}..."
if ! id "$TARGET_USER" >/dev/null 2>&1; then
    echo "Target user does not exist: $TARGET_USER"; exit 1
fi
runuser -u "$TARGET_USER" -- env HOME="$TARGET_HOME" \
    git config --global user.name "$GIT_USER"
runuser -u "$TARGET_USER" -- env HOME="$TARGET_HOME" \
    git config --global user.email "$GIT_EMAIL"
runuser -u "$TARGET_USER" -- env HOME="$TARGET_HOME" \
    git config --global init.defaultBranch "$GIT_DEFAULT_BRANCH"
echo "Git identity configured for ${TARGET_USER}."

echo "[4/5] Installing Python script..."
PYTHON_SOURCE="${SCRIPT_DIR}/${PYTHON_SOURCE_RELATIVE}"
if [[ ! -f "$PYTHON_SOURCE" ]]; then
    echo "Python source not found: $PYTHON_SOURCE"
    echo "Place your own script there, then rerun."
    exit 1
fi
install -D -o root -g root -m 0755 "$PYTHON_SOURCE" "$PYTHON_DEST"
echo "Installed: $PYTHON_DEST"

echo "[5/5] Preparing Netplan configuration..."
install -d -m 0755 /etc/netplan
NETPLAN_DEST="/etc/netplan/99-rpi5-static-ip.yaml"

# Back up an existing file managed by this project before replacing it.
if [[ -f "$NETPLAN_DEST" ]]; then
    cp -a "$NETPLAN_DEST" "${NETPLAN_DEST}.bak.$(date +%F-%H%M%S)"
fi
install -m 0600 "$NETPLAN_SOURCE" "$NETPLAN_DEST"

# Validate generated Netplan configuration. This does not change live networking.
netplan generate

if [[ "${APPLY_NETPLAN:-no}" == "yes" ]]; then
    echo "APPLY_NETPLAN=yes: applying Netplan. SSH/network connectivity may drop."
    echo "Ensure you have local console access or another recovery path."
    netplan apply
else
    echo "Netplan config installed and generated, but NOT applied."
    echo "After checking your network setup, apply with:"
    echo "  sudo netplan try"
    echo "  sudo netplan apply"
fi

echo
echo "=================================================="
echo " Provisioning completed: $(date)"
echo " Log: ${LOG_FILE}"
echo "=================================================="
