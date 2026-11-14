
#!/usr/bin/env bash
#
# Nixel Linux - Post Installation Setup
# Arch Linux | Hyprland | Noctalia | Catppuccin Mocha
#

set -Eeuo pipefail

readonly SCRIPT_NAME="Nixel Setup"
readonly BACKUP="$HOME/.config/nixel-backup/$(date +%Y%m%d-%H%M%S)"
readonly TEMP_DIR="$(mktemp -d)"

trap 'rm -rf "$TEMP_DIR"' EXIT

# -----------------------------------------
# Helpers
# -----------------------------------------

info() {
    printf '\e[1;35m[NIXEL]\e[0m %s\n' "$*"
}

error() {
    printf '\e[1;31m[ERROR]\e[0m %s\n' "$*" >&2
}

backup_file() {
    local file="$1"

    if [[ -e "$file" ]]; then
        mkdir -p "$BACKUP$(dirname "$file")"
        cp -a "$file" "$BACKUP$file"
    fi
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || {
        error "Missing command: $1"
        exit 1
    }
}

# -----------------------------------------
# Initial checks
# -----------------------------------------

if [[ $EUID -eq 0 ]]; then
    error "Do not run this script as root."
    exit 1
fi

if [[ ! -f /etc/arch-release ]]; then
    error "This installer requires Arch Linux."
    exit 1
fi

require_command sudo
require_command pacman

sudo -v

info "Starting Nixel installation..."

mkdir -p "$BACKUP"

# -----------------------------------------
# System update
# -----------------------------------------

info "Updating Arch Linux..."

sudo pacman -Syu --needed --noconfirm

# -----------------------------------------
# Install base packages
# -----------------------------------------

info "Installing base packages..."

BASE_PACKAGES=(
    base-devel
    git
    curl
    wget
    unzip
    zip
    jq
    nano
    networkmanager
    bluez
    bluez-utils
    brightnessctl
    playerctl
    wl-clipboard
    grim
    slurp
    xdg-desktop-portal
    xdg-desktop-portal-hyprland
    qt5-wayland
    qt6-wayland
    polkit-gnome
    noto-fonts
    noto-fonts-emoji
    ttf-jetbrains-mono-nerd
    ttf-font-awesome
)

sudo pacman -S --needed --noconfirm "${BASE_PACKAGES[@]}"

# -----------------------------------------
# Install paru
# -----------------------------------------

install_paru() {
    if command -v paru >/dev/null 2>&1; then
        info "paru already installed."
        return
    fi

    info "Building paru..."

    git clone https://aur.archlinux.org/paru.git "$TEMP_DIR/paru"

    (
        cd "$TEMP_DIR/paru"
        makepkg -si --noconfirm
    )
}

install_paru

# -----------------------------------------
# Install desktop packages
# -----------------------------------------

info "Installing Hyprland and Noctalia..."

DESKTOP_PACKAGES=(
    hyprland
    kitty
    fish
    starship
    kakoune
    ly
    falkon
    fastfetch
    cava
    btop
    pipewire
    pipewire-alsa
    pipewire-pulse
    wireplumber
    pavucontrol
    playerctl
    network-manager-applet
)

sudo pacman -S --needed --noconfirm "${DESKTOP_PACKAGES[@]}"

# Noctalia is installed through the AUR.
paru -S --needed --noconfirm noctalia-shell

# -----------------------------------------
# Enable system services
# -----------------------------------------

info "Configuring system services..."

sudo systemctl enable NetworkManager.service
sudo systemctl enable bluetooth.service

# Ly runs on TTY2.
sudo systemctl disable getty@tty2.service || true
sudo systemctl enable ly@tty2.service

# -----------------------------------------
# Audio
# -----------------------------------------

info "Configuring PipeWire..."

systemctl --user enable --now \
    pipewire.socket \
    pipewire-pulse.socket \
    wireplumber.service

# -----------------------------------------
# Catppuccin theme repositories
# -----------------------------------------

info "Downloading Catppuccin themes..."

mkdir -p "$HOME/.config/kitty"
mkdir -p "$HOME/.config/fish"
mkdir -p "$HOME/.config/kak"
mkdir -p "$HOME/.config/btop/themes"
mkdir -p "$HOME/.config/cava"
mkdir -p "$HOME/.config/hypr"

# Kitty
git clone --depth 1 https://github.com/catppuccin/kitty.git \
    "$TEMP_DIR/kitty-theme"

# Fish
git clone --depth 1 https://github.com/catppuccin/fish.git \
    "$TEMP_DIR/fish-theme"

# Kakoune
git clone --depth 1 https://github.com/catppuccin/kakoune.git \
    "$TEMP_DIR/kak-theme"

# -----------------------------------------
# Kitty configuration
# -----------------------------------------

info "Configuring Kitty..."

backup_file "$HOME/.config/kitty/kitty.conf"

cat > "$HOME/.config/kitty/kitty.conf" <<'EOF'
font_family JetBrainsMono Nerd Font
font_size 11

background #1e1e2e
foreground #cdd6f4

selection_background #585b70
selection_foreground #cdd6f4

cursor #f5e0dc
cursor_text_color #1e1e2e

url_color #89b4fa

color0  #45475a
color1  #f38ba8
color2  #a6e3a1
color3  #f9e2af
color4  #89b4fa
color5  #f5c2e7
color6  #94e2d5
color7  #bac2de
color8  #585b70
color9  #f38ba8
color10 #a6e3a1
color11 #f9e2af
color12 #89b4fa
color13 #f5c2e7
color14 #94e2d5
color15 #a6adc8

window_padding_width 10
confirm_os_window_close 0
enable_audio_bell no
EOF

# -----------------------------------------
# Fish configuration
# -----------------------------------------

info "Configuring Fish..."

backup_file "$HOME/.config/fish/config.fish"

cat > "$HOME/.config/fish/config.fish" <<'EOF'
if status is-interactive
    set -g fish_greeting

    # Starship prompt
    starship init fish | source

    # General aliases
    alias ls='ls --color=auto'
    alias ll='ls -lah'
    alias la='ls -A'

    # Rust Cargo
    alias cr='cargo run'
    alias cb='cargo build'
    alias ct='cargo test'
    alias ca='cargo add'
    alias cn='cargo new'
    alias cc='cargo check'
    alias cf='cargo fmt'
    alias cl='cargo clippy'

    # Git
    alias gs='git status'
    alias ga='git add'
    alias gc='git commit'
    alias gp='git push'
    alias gl='git log --oneline --graph'
    alias gd='git diff'
    alias gb='git branch'
    alias gco='git checkout'

    # Navigation
    alias ..='cd ..'
    alias ...='cd ../..'
end
EOF

# Apply Catppuccin Fish theme if available.
FISH_THEME="$TEMP_DIR/fish-theme/themes/Catppuccin Mocha.theme"

if [[ -f "$FISH_THEME" ]]; then
    mkdir -p "$HOME/.config/fish/themes"
    cp "$FISH_THEME" "$HOME/.config/fish/themes/"
fi

# -----------------------------------------
# Starship configuration
# -----------------------------------------

info "Configuring Starship..."

mkdir -p "$HOME/.config"

backup_file "$HOME/.config/starship.toml"

cat > "$HOME/.config/starship.toml" <<'EOF'
add_newline = false

format = """
[╭─](#cba6f7)$directory$git_branch$git_status
[╰❱](#cba6f7) """

[directory]
style = "bold #89b4fa"
truncation_length = 3

[git_branch]
symbol = " "
style = "bold #cba6f7"

[git_status]
style = "#f38ba8"

[character]
success_symbol = "[❱](bold #a6e3a1)"
error_symbol = "[❱](bold #f38ba8)"
EOF

# -----------------------------------------
# Kakoune
# -----------------------------------------

info "Configuring Kakoune..."

backup_file "$HOME/.config/kak/kakrc"

cat > "$HOME/.config/kak/kakrc" <<'EOF'
# Kakoune configuration

set global tabstop 4
set global indentwidth 4
set global scrolloff 5,5
set global ui_options terminal_assistant=cat

colorscheme default
EOF

# Install theme files if the repository contains them.
if [[ -d "$TEMP_DIR/kak-theme" ]]; then
    find "$TEMP_DIR/kak-theme" -type f -name '*.kak' \
        -exec cp {} "$HOME/.config/kak/" \;
fi

# -----------------------------------------
# Cava
# -----------------------------------------

info "Configuring Cava..."

backup_file "$HOME/.config/cava/config"

cat > "$HOME/.config/cava/config" <<'EOF'
[general]
bars = 0

[colors]
gradient = 1
gradient_color_1 = '#89b4fa'
gradient_color_2 = '#cba6f7'
gradient_color_3 = '#f5c2e7'
gradient_color_4 = '#f38ba8'
gradient_color_5 = '#fab387'
EOF

# -----------------------------------------
# Hyprland
# -----------------------------------------

info "Configuring Hyprland..."

HYPR_CONFIG="$HOME/.config/hypr/hyprland.conf"

if [[ ! -f "$HYPR_CONFIG" ]]; then
    cat > "$HYPR_CONFIG" <<'EOF'
$mainMod = SUPER

monitor = ,preferred,auto,1

exec-once = noctalia-shell
exec-once = nm-applet --indicator
exec-once = /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1

input {
    kb_layout = us
    follow_mouse = 1
    sensitivity = 0
}

general {
    gaps_in = 5
    gaps_out = 10
    border_size = 2

    col.active_border = rgba(cba6f7ff)
    col.inactive_border = rgba(45475aff)
}

decoration {
    rounding = 12
    active_opacity = 1.0
    inactive_opacity = 0.95
}

animations {
    enabled = yes
}

$terminal = kitty

bind = $mainMod, RETURN, exec, $terminal
bind = $mainMod, Q, killactive
bind = $mainMod, M, exit
bind = $mainMod, E, exec, falkon
bind = $mainMod, SPACE, exec, noctalia-shell ipc call launcher toggle
bind = $mainMod, V, togglefloating
bind = $mainMod, F, fullscreen
bind = $mainMod, L, exec, loginctl lock-session
EOF
fi

# -----------------------------------------
# Ly
# -----------------------------------------

info "Configuring Ly..."

sudo mkdir -p /etc/ly

if [[ ! -f /etc/ly/config.ini ]]; then
    sudo install -m 644 /usr/share/doc/ly/config.ini /etc/ly/config.ini 2>/dev/null || true
fi

if [[ -f /etc/ly/config.ini ]]; then
    sudo cp /etc/ly/config.ini "$BACKUP/ly-config.ini"

    sudo sed -i \
        -e 's|^#\?animation =.*|animation = none|' \
        /etc/ly/config.ini
fi

# -----------------------------------------
# GRUB Catppuccin
# -----------------------------------------

info "Installing Catppuccin GRUB theme..."

if [[ -f /etc/default/grub && -f /boot/grub/grub.cfg ]]; then

    git clone --depth 1 https://github.com/catppuccin/grub.git \
        "$TEMP_DIR/grub-theme"

    sudo mkdir -p /usr/share/grub/themes

    sudo cp -r "$TEMP_DIR/grub-theme/src/catppuccin-mocha-grub-theme" \
        /usr/share/grub/themes/

    backup_file "/etc/default/grub"

    if grep -q '^GRUB_THEME=' /etc/default/grub; then
        sudo sed -i \
            's|^GRUB_THEME=.*|GRUB_THEME="/usr/share/grub/themes/catppuccin-mocha-grub-theme/theme.txt"|' \
            /etc/default/grub
    else
        echo 'GRUB_THEME="/usr/share/grub/themes/catppuccin-mocha-grub-theme/theme.txt"' \
            | sudo tee -a /etc/default/grub >/dev/null
    fi

    sudo grub-mkconfig -o /boot/grub/grub.cfg

else
    info "GRUB configuration not found. Skipping GRUB theme."
fi

# -----------------------------------------
# Default shell
# -----------------------------------------

info "Setting Fish as default shell..."

FISH_PATH="$(command -v fish)"

if ! grep -qxF "$FISH_PATH" /etc/shells; then
    echo "$FISH_PATH" | sudo tee -a /etc/shells >/dev/null
fi

chsh -s "$FISH_PATH"

# -----------------------------------------
# Fastfetch
# -----------------------------------------

info "Configuring Fastfetch..."

mkdir -p "$HOME/.config/fastfetch"

if [[ ! -f "$HOME/.config/fastfetch/config.jsonc" ]]; then
    fastfetch --gen-config
fi

# -----------------------------------------
# Enable user services
# -----------------------------------------

sudo systemctl enable NetworkManager.service

# -----------------------------------------
# Finish
# -----------------------------------------

info "Nixel installation completed."

printf '\n'
printf '\e[1;35m'
printf '  _   _ _          _ \n'
printf ' | \\ | (_)_  _____| |\n'
printf ' |  \\| | \\ \\/ / _ \\ |\n'
printf ' | |\\  | |>  <  __/ |\n'
printf ' |_| \\_|_/_/\\_\\___|_|\n'
printf '\e[0m\n'

info "Configuration backups: $BACKUP"
info "Please reboot to start your new desktop."
