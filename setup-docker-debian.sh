#!/bin/bash
SCRIPT_VERSION="v1.1-debian"
# ==============================================================================
# Tony Teaches Tech's VPS Setup Script (Debian Edition)
# ==============================================================================
# This script is designed to take a freshly provisioned Debian VPS
# and immediately secure it while preparing it for Docker-based deployments.
#
# EXACTLY WHAT THIS SCRIPT DOES:
# 0. Initial Checks: Ensures the script is run as root and verifies that
#    the OS supports apt-get and systemd before proceeding.
# 1. User Setup: Prompts to create a new non-root user, asks you to set a
#    password, and grants them passwordless sudo access (NOPASSWD:ALL).
# 2. SSH Hardening: Safely disables direct root login to prevent brute-force
#    attacks while ensuring password and SSH key access remain enabled for
#    the new user. Tests the config before applying to prevent lockouts.
# 3. System Updates: Updates package lists and upgrades all system packages.
# 4. Core Utilities & Security: Installs essential tools (ufw, curl, wget, git,
#    ca-certificates, gnupg) and starts Fail2Ban to block malicious IPs.
# 5. Auto-Patching: Installs and configures 'unattended-upgrades' to
#    automatically apply security updates and clean up old packages weekly.
# 6. Firewall Lockdown: Enables UFW, denying all incoming traffic by default,
#    allowing outgoing traffic, and explicitly allowing SSH.
# 7. Docker Engine: Installs Docker from the official Debian repo, enables the
#    systemd service, and adds the new user to the 'docker' group so containers
#    can be run without 'sudo'.
# 8. Final Output: Dynamically fetches the server's public IP, prints
#    login instructions for the new user, and detects if a system reboot is
#    required.
#
# SAFETY & LOGGING:
# This script is idempotent (safe to run multiple times). It backs up your SSH
# config before modifying it. All verbose installation output is cleanly
# redirected to /var/log/vps-setup.log to keep the terminal clean.
# ==============================================================================
set -uo pipefail
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'
LOG_FILE="/var/log/vps-setup.log"
echo "Starting TTT VPS Setup ($SCRIPT_VERSION)..." > "$LOG_FILE"

die() {
    echo -e "\n${RED}❌ ERROR: $1${NC}"
    echo -e "${RED}Script aborted. Check log for possible details: cat $LOG_FILE${NC}"
    exit 1
}
step() {
    echo -e "\n${BLUE}====================================================${NC}"
    echo -e "${BLUE}[$1] $2${NC}"
    echo -e "${BLUE}====================================================${NC}"
}
ok() {
    echo -e "   ${GREEN}✔ Done${NC}"
}
info() {
    echo -e "   ${YELLOW}$1${NC}"
}

# Wait for background apt processes to release the dpkg lock
wait_for_apt() {
    if command -v fuser >/dev/null 2>&1; then
        while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || fuser /var/lib/dpkg/lock >/dev/null 2>&1; do
            info "Waiting for background apt processes to finish..."
            sleep 5
        done
    fi
}

# Install Docker from the official Debian apt repository
install_docker() {
    # Add Docker's official GPG key
    apt-get update -qq >> "$LOG_FILE" 2>&1
    DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl >> "$LOG_FILE" 2>&1
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc >> "$LOG_FILE" 2>&1
    chmod a+r /etc/apt/keyrings/docker.asc

    # Add the Docker repository — no leading whitespace (heredoc must be unindented)
    CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
    ARCH=$(dpkg --print-architecture)
cat > /etc/apt/sources.list.d/docker.sources << EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: ${CODENAME}
Components: stable
Architectures: ${ARCH}
Signed-By: /etc/apt/keyrings/docker.asc
EOF

    apt-get update -qq >> "$LOG_FILE" 2>&1
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin >> "$LOG_FILE" 2>&1
}

# ============================================================
# 0. INITIAL CHECKS
# ============================================================
[ "$EUID" -ne 0 ] && die "Run with: sudo bash setup.sh"
command -v apt-get >/dev/null 2>&1 || die "Unsupported OS (Debian required)"
command -v systemctl >/dev/null 2>&1 || die "Systemd required"

# Detect OS — Debian uses 'sshd', Ubuntu uses 'ssh' service name
# Also check Debian version for sshd_config.d support (Debian 11+)
OS_ID=$(grep -oP '(?<=^ID=).+' /etc/os-release | tr -d '"')
OS_VERSION_ID=$(grep -oP '(?<=^VERSION_ID=).+' /etc/os-release | tr -d '"' | cut -d. -f1)

# Debian 10 (Buster) doesn't support sshd_config.d includes by default
# Debian 11+ (Bullseye/Bookworm) does
USE_SSHD_D=true
if [ "$OS_ID" = "debian" ] && [ "${OS_VERSION_ID:-0}" -lt 11 ] 2>/dev/null; then
    USE_SSHD_D=false
fi

# Resolve SSH service name: Debian uses 'sshd', Ubuntu uses 'ssh'
if systemctl list-units --type=service | grep -q "^.*sshd\.service"; then
    SSH_SERVICE="sshd"
else
    SSH_SERVICE="ssh"
fi

# ============================================================
# HEADER
# ============================================================
echo -e "${BLUE}====================================================${NC}"
echo -e "${GREEN}   VPS Setup Script ${SCRIPT_VERSION} by Tony Teaches Tech${NC}"
echo -e "${BLUE}====================================================${NC}"
echo
echo "Detected OS: ${OS_ID} ${OS_VERSION_ID}"
echo
echo "On a fresh VPS instance, this script:"
echo "- Creates a new user"
echo "- Makes SSH access more secure"
echo "- Updates the system"
echo "- Installs recommended packages"
echo "- Enables automatic security updates"
echo "- Locks down the firewall to only allow SSH"
echo "- Installs Docker"

# ============================================================
# 1. USER SETUP
# ============================================================
step "1/7" "Create a new user"
while true; do
    read -p "Enter username (default: noname): " NEW_USER
    if [ -z "${NEW_USER:-}" ]; then
        NEW_USER="noname"
        info "Using default user: noname"
    fi
    NEW_USER=$(echo "$NEW_USER" | tr '[:upper:]' '[:lower:]')
    if [[ "$NEW_USER" =~ ^(root|admin|ubuntu|daemon)$ ]]; then
        info "Error: '$NEW_USER' is a reserved name. Try again."
        continue
    fi
    if [[ ! "$NEW_USER" =~ ^[a-z][a-z0-9_-]{0,31}$ ]]; then
        info "Error: Invalid format. Must start with a letter and contain no spaces."
        continue
    fi
    break
done

if id "$NEW_USER" &>/dev/null; then
    info "User '$NEW_USER' already exists, skipping creation..."
else
    useradd -m -s /bin/bash "$NEW_USER" >> "$LOG_FILE" 2>&1 || die "User creation failed"
    info "Created user '$NEW_USER'"
fi
echo "Set password for SSH login:"
passwd "$NEW_USER" || die "Password setup failed"
ok

# ============================================================
# 2. SSH SAFETY
# ============================================================
step "2/7" "Secure SSH"

if [ "$USE_SSHD_D" = true ]; then
    # Debian 11+ : use drop-in config dir
    SSH_CONF="/etc/ssh/sshd_config.d/60-ttt.conf"

    # Ensure the include directive exists in the main sshd_config
    if ! grep -q "^Include /etc/ssh/sshd_config.d/\*\.conf" /etc/ssh/sshd_config 2>/dev/null; then
        sed -i '1s|^|Include /etc/ssh/sshd_config.d/*.conf\n|' /etc/ssh/sshd_config \
            >> "$LOG_FILE" 2>&1 || die "Failed to add Include directive to sshd_config"
        info "Added sshd_config.d Include directive"
    fi

    mkdir -p /etc/ssh/sshd_config.d

    if [ -f "$SSH_CONF" ]; then
        cp "$SSH_CONF" "${SSH_CONF}.bak" >> "$LOG_FILE" 2>&1 || die "Backup failed"
        info "Backed up old SSH config"
    fi

    cat <<EOF > "$SSH_CONF" || die "SSH config write failed"
PermitRootLogin prohibit-password
PasswordAuthentication yes
PubkeyAuthentication yes
EOF

else
    # Debian 10 (Buster): modify main sshd_config directly
    SSH_CONF="/etc/ssh/sshd_config"
    cp "$SSH_CONF" "${SSH_CONF}.bak" >> "$LOG_FILE" 2>&1 || die "Backup failed"
    info "Backed up /etc/ssh/sshd_config"

    sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/' "$SSH_CONF"
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' "$SSH_CONF"
    sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' "$SSH_CONF"
fi

info "Secured SSH config"
sshd -t >> "$LOG_FILE" 2>&1 || {
    if [ -f "${SSH_CONF}.bak" ]; then
        mv "${SSH_CONF}.bak" "$SSH_CONF" >> "$LOG_FILE" 2>&1
    fi
    die "Invalid SSH config — rollback executed"
}
info "Validated new SSH config"

systemctl restart "$SSH_SERVICE" >> "$LOG_FILE" 2>&1 || die "Failed to restart SSH service ($SSH_SERVICE)"
info "Restarted SSH service ($SSH_SERVICE)"
ok

# ============================================================
# 3. SYSTEM UPDATE
# ============================================================
step "3/7" "Updating system"
wait_for_apt
apt-get update -qq >> "$LOG_FILE" 2>&1 || die "apt update failed"
info "Updated package lists"
wait_for_apt
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq >> "$LOG_FILE" 2>&1 || die "upgrade failed"
info "Upgraded system packages"
ok

# ============================================================
# 4. RECOMMENDED PACKAGES
# ============================================================
step "4/7" "Installing recommended packages"
PACKAGES="ufw curl wget git ca-certificates gnupg fail2ban"
wait_for_apt
DEBIAN_FRONTEND=noninteractive apt-get install -y $PACKAGES \
    >> "$LOG_FILE" 2>&1 || die "package install failed"
systemctl enable fail2ban >> "$LOG_FILE" 2>&1
systemctl start fail2ban >> "$LOG_FILE" 2>&1
info "Installed the following packages:"
for pkg in $PACKAGES; do
    echo -e "   ${YELLOW}- $pkg${NC}"
done
ok

# ============================================================
# 5. SECURITY UPDATES
# ============================================================
step "5/7" "Enabling automatic security updates"
wait_for_apt
DEBIAN_FRONTEND=noninteractive apt-get install -y unattended-upgrades \
    >> "$LOG_FILE" 2>&1 || die "failed to install unattended-upgrades"

# Debian uses 'stable' origin, not 'Ubuntu' — configure appropriately
cat <<EOF > /etc/apt/apt.conf.d/50unattended-upgrades
Unattended-Upgrade::Origins-Pattern {
    "origin=Debian,codename=\${distro_codename},label=Debian-Security";
    "origin=Debian,codename=\${distro_codename}-security,label=Debian-Security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

echo unattended-upgrades unattended-upgrades/enable_auto_updates boolean true | debconf-set-selections \
    >> "$LOG_FILE" 2>&1 || die "failed to configure unattended-upgrades"
dpkg-reconfigure -f noninteractive unattended-upgrades >> "$LOG_FILE" 2>&1 \
    || die "failed to enable unattended-upgrades"

cat <<EOF > /etc/apt/apt.conf.d/20auto-upgrades
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

systemctl enable --now apt-daily.timer >> "$LOG_FILE" 2>&1
systemctl enable --now apt-daily-upgrade.timer >> "$LOG_FILE" 2>&1
info "Enabled automatic security updates"
ok

# ============================================================
# 6. FIREWALL
# ============================================================
step "6/7" "Configuring ufw firewall"
ufw default deny incoming >> "$LOG_FILE" 2>&1 || die "ufw deny incoming failed"
info "Set default policy: Deny incoming"
ufw default allow outgoing >> "$LOG_FILE" 2>&1 || die "ufw allow outgoing failed"
info "Set default policy: Allow outgoing"
ufw allow OpenSSH >> "$LOG_FILE" 2>&1 || die "ufw ssh rule failed"
info "Allowed only SSH traffic"
ufw --force enable >> "$LOG_FILE" 2>&1 || die "ufw enable failed"
info "Enabled UFW firewall"
ok

# ============================================================
# 7. DOCKER
# ============================================================
step "7/7" "Installing Docker"
if ! command -v docker >/dev/null 2>&1; then
    # Remove any conflicting packages before installing
    CONFLICT_PKGS="docker.io docker-compose docker-doc podman-docker containerd runc"
    for pkg in $CONFLICT_PKGS; do
        if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
            DEBIAN_FRONTEND=noninteractive apt-get remove -y "$pkg" >> "$LOG_FILE" 2>&1
        fi
    done
    info "Removed conflicting packages (if any)"

    wait_for_apt
    install_docker || die "Docker install failed"
    info "Installed Docker Engine"

    systemctl enable --now docker >> "$LOG_FILE" 2>&1 || die "docker service start failed"
    info "Started Docker daemon"
else
    info "Docker already installed"
fi
usermod -aG docker "$NEW_USER" >> "$LOG_FILE" 2>&1 || die "docker group add failed"
info "Added user '$NEW_USER' to docker group"
ok

# ============================================================
# FINAL OUTPUT
# ============================================================
echo -e "\n${BLUE}====================================================${NC}"
echo -e "${GREEN}            🎉 SETUP COMPLETE                       ${NC}"
echo -e "${BLUE}====================================================${NC}\n"
IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')
[ -z "$IP" ] && IP=$(hostname -I | awk '{print $1}')
[ -z "$IP" ] && IP="YOUR_SERVER_IP"
echo "🚨 IMPORTANT NEXT STEPS:"
echo -e "⚠ Docker WILL NOT WORK until you log in as the new user.\n"
if [ -f /var/run/reboot-required ]; then
    echo -e "${YELLOW}Reboot required. Server restarting in 5 seconds...${NC}"
    echo -e "Once it boots up, reconnect using: ${GREEN}ssh $NEW_USER@$IP${NC}\n"
    sleep 5
    reboot
else
    echo "1. Type 'exit' to log out of this root session."
    echo -e "2. Reconnect using: ${GREEN}ssh $NEW_USER@$IP${NC}\n"
fi
