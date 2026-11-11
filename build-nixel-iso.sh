#!/usr/bin/env bash
# build-nixel-iso.sh — build a Nixel Linux live ISO (Arch-based) with XFCE,
# LightDM autologin, and a service that creates the "nixel" user at boot.
#
# Run on an Arch Linux host (or Arch container) as root:
#   sudo ./build-nixel-iso.sh
#
# Optional: put a 640x480 PNG named splash.png next to this script to replace
# the BIOS (syslinux) boot splash.

set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Run as root." >&2; exit 1; }
command -v pacman >/dev/null || { echo "This script must run on Arch Linux." >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${BUILD_DIR:-$SCRIPT_DIR/nixel-build}"
PROFILE="$BUILD_DIR/profile"
WORK="$BUILD_DIR/work"
OUT="${OUT_DIR:-$SCRIPT_DIR/out}"

echo "==> Installing archiso"
pacman -Sy --needed --noconfirm archiso

echo "==> Preparing profile from releng"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$OUT"
cp -r /usr/share/archiso/configs/releng "$PROFILE"
AIROOT="$PROFILE/airootfs"

# ---------------------------------------------------------------------------
# profiledef.sh branding
# ---------------------------------------------------------------------------
echo "==> Branding profiledef.sh"
sed -i -E \
  -e 's|^iso_name=.*|iso_name="nixel"|' \
  -e "s|^iso_label=.*|iso_label=\"NIXEL_\$(date +%Y%m)\"|" \
  -e 's|^iso_publisher=.*|iso_publisher="Nixel Linux"|' \
  -e 's|^iso_application=.*|iso_application="Nixel Linux Live/Rescue ISO"|' \
  -e 's|^install_dir=.*|install_dir="nixel"|' \
  "$PROFILE/profiledef.sh"

# ---------------------------------------------------------------------------
# Bootloader branding (GRUB, syslinux, systemd-boot) — replace every visible
# "Arch Linux" string in the boot menus.
# ---------------------------------------------------------------------------
echo "==> Branding bootloader menus"
for d in grub syslinux efiboot; do
  [[ -d "$PROFILE/$d" ]] || continue
  grep -rl --binary-files=without-match -e 'Arch Linux' -e 'ARCH' "$PROFILE/$d" 2>/dev/null | while read -r f; do
    sed -i -e 's/Arch Linux/Nixel Linux/g' "$f"
  done
done

if [[ -f "$SCRIPT_DIR/splash.png" && -f "$PROFILE/syslinux/splash.png" ]]; then
  cp "$SCRIPT_DIR/splash.png" "$PROFILE/syslinux/splash.png"
fi

# ---------------------------------------------------------------------------
# Packages: XFCE + LightDM
# ---------------------------------------------------------------------------
echo "==> Adding packages"
cat >> "$PROFILE/packages.x86_64" <<'EOF'
xorg-server
xorg-xinit
xfce4
xfce4-goodies
lightdm
lightdm-gtk-greeter
networkmanager
network-manager-applet
sudo
firefox
file-roller
gvfs
pavucontrol
EOF

# ---------------------------------------------------------------------------
# OS identity: os-release, lsb-release, issue, motd, hostname, GRUB distributor
# ---------------------------------------------------------------------------
echo "==> Writing OS identity files"
mkdir -p "$AIROOT/etc" "$AIROOT/usr/lib" "$AIROOT/etc/default"

cat > "$AIROOT/etc/os-release" <<'EOF'
NAME="Nixel Linux"
PRETTY_NAME="Nixel Linux"
ID=nixel
ID_LIKE=arch
BUILD_ID=rolling
ANSI_COLOR="38;2;23;147;209"
HOME_URL="https://github.com/nixel-linux"
LOGO=nixel-logo
EOF
cp "$AIROOT/etc/os-release" "$AIROOT/usr/lib/os-release"

cat > "$AIROOT/etc/lsb-release" <<'EOF'
DISTRIB_ID="Nixel"
DISTRIB_RELEASE="rolling"
DISTRIB_DESCRIPTION="Nixel Linux"
EOF

cat > "$AIROOT/etc/issue" <<'EOF'
Nixel Linux \r (\l)

EOF

cat > "$AIROOT/etc/motd" <<'EOF'

  _   _ _          _   _     _
 | \ | (_)_  _____| | | |   (_)_ __  _   ___  __
 |  \| | \ \/ / _ \ | | |   | | '_ \| | | \ \/ /
 | |\  | |>  <  __/ | | |___| | | | | |_| |>  <
 |_| \_|_/_/\_\___|_| |_____|_|_| |_|\__,_/_/\_\

 Welcome to Nixel Linux.
 Live user: nixel (autologin, XFCE via LightDM)

EOF

echo "nixel" > "$AIROOT/etc/hostname"

cat > "$AIROOT/etc/default/grub" <<'EOF'
GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="Nixel"
GRUB_CMDLINE_LINUX_DEFAULT="quiet"
GRUB_CMDLINE_LINUX=""
GRUB_PRELOAD_MODULES="part_gpt part_msdos"
GRUB_TIMEOUT_STYLE=menu
GRUB_TERMINAL_INPUT=console
GRUB_GFXMODE=auto
GRUB_GFXPAYLOAD_LINUX=keep
GRUB_DISABLE_RECOVERY=true
EOF

# ---------------------------------------------------------------------------
# LightDM autologin into XFCE as "nixel"
# ---------------------------------------------------------------------------
echo "==> Configuring LightDM autologin"
mkdir -p "$AIROOT/etc/lightdm/lightdm.conf.d"
cat > "$AIROOT/etc/lightdm/lightdm.conf.d/50-nixel-autologin.conf" <<'EOF'
[Seat:*]
autologin-user=nixel
autologin-user-timeout=0
autologin-session=xfce
user-session=xfce
greeter-session=lightdm-gtk-greeter
EOF

# ---------------------------------------------------------------------------
# Service that creates the nixel user at boot (before LightDM starts)
# ---------------------------------------------------------------------------
echo "==> Creating nixel-create-user service"
mkdir -p "$AIROOT/usr/local/bin" "$AIROOT/etc/systemd/system/multi-user.target.wants" "$AIROOT/etc/sudoers.d"

cat > "$AIROOT/usr/local/bin/nixel-create-user" <<'EOF'
#!/usr/bin/env bash
# Creates the live "nixel" user (idempotent).
set -euo pipefail

USERNAME="nixel"

# LightDM's PAM autologin stack requires membership in the "autologin" group.
getent group autologin >/dev/null || groupadd -r autologin

if ! id "$USERNAME" >/dev/null 2>&1; then
  useradd -m -s /bin/bash \
    -G wheel,audio,video,storage,optical,network,autologin \
    -c "Nixel Live User" "$USERNAME"
  # Empty password: live session only.
  passwd -d "$USERNAME"
fi

# Make sure the group membership is right even if the user pre-existed.
usermod -aG autologin,wheel "$USERNAME"
EOF

cat > "$AIROOT/etc/systemd/system/nixel-create-user.service" <<'EOF'
[Unit]
Description=Create the Nixel live user
After=local-fs.target
Before=lightdm.service display-manager.service systemd-user-sessions.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/nixel-create-user

[Install]
WantedBy=multi-user.target
EOF

ln -sf /etc/systemd/system/nixel-create-user.service \
  "$AIROOT/etc/systemd/system/multi-user.target.wants/nixel-create-user.service"

# Passwordless sudo for the live user
echo 'nixel ALL=(ALL:ALL) NOPASSWD: ALL' > "$AIROOT/etc/sudoers.d/10-nixel"

# ---------------------------------------------------------------------------
# Enable LightDM + NetworkManager, boot to graphical target
# ---------------------------------------------------------------------------
echo "==> Enabling services"
ln -sf /usr/lib/systemd/system/lightdm.service "$AIROOT/etc/systemd/system/display-manager.service"
ln -sf /usr/lib/systemd/system/graphical.target "$AIROOT/etc/systemd/system/default.target"
ln -sf /usr/lib/systemd/system/NetworkManager.service \
  "$AIROOT/etc/systemd/system/multi-user.target.wants/NetworkManager.service"

# ---------------------------------------------------------------------------
# File permissions (profiledef.sh is sourced as bash, so appending works)
# ---------------------------------------------------------------------------
cat >> "$PROFILE/profiledef.sh" <<'EOF'

file_permissions+=(
  ["/usr/local/bin/nixel-create-user"]="0:0:755"
  ["/etc/sudoers.d/10-nixel"]="0:0:440"
)
EOF

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
echo "==> Building ISO (this takes a while and needs several GB of space)"
mkarchiso -v -w "$WORK" -o "$OUT" "$PROFILE"

echo
echo "Done. ISO is in: $OUT"
ls -lh "$OUT"
