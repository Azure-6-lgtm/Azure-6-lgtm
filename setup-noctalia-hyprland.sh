#!/usr/bin/env bash
# Hyprland + Noctalia v5 (floating rounded bar, notifications, launcher, lock, wallpaper)
# Catppuccin Mocha everywhere, for a minimal Arch install.
# Run as your normal user (NOT root). The user needs sudo rights.
#   chmod +x setup-noctalia-hyprland.sh && ./setup-noctalia-hyprland.sh
set -euo pipefail

log()  { printf '\n\033[1;35m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
bak()  { [[ -f "$1" ]] && cp "$1" "$1.bak.$(date +%s)" || true; }

[[ $EUID -eq 0 ]] && { echo "Run as a normal user, not root."; exit 1; }

# ---------------------------------------------------------------- 1. base
log "Updating system and installing base tools"
sudo pacman -Syu --needed --noconfirm base-devel git curl

# ------------------------------------------------------- 2. AUR helper
if ! command -v paru >/dev/null 2>&1; then
  log "Installing paru (AUR helper)"
  tmp="$(mktemp -d)"
  git clone https://aur.archlinux.org/paru-bin.git "$tmp/paru-bin"
  (cd "$tmp/paru-bin" && makepkg -si --noconfirm)
  rm -rf "$tmp"
fi

# ---------------------------------------------------------- 3. packages
log "Installing Hyprland, Noctalia and system pieces"
sudo pacman -S --needed --noconfirm \
  hyprland noctalia foot vim \
  xorg-xwayland xdg-desktop-portal-hyprland xdg-desktop-portal-gtk \
  pipewire pipewire-pulse wireplumber \
  networkmanager bluez bluez-utils brightnessctl \
  grim slurp wl-clipboard cliphist \
  noto-fonts noto-fonts-emoji ttf-jetbrains-mono-nerd \
  papirus-icon-theme adw-gtk-theme \
  qt5ct qt6ct kvantum \
  firefox

sudo systemctl enable --now NetworkManager.service || warn "NetworkManager enable failed"
sudo systemctl enable --now bluetooth.service      || warn "bluetooth enable failed"

log "Installing Catppuccin cursor + folder icons from AUR (best effort)"
paru -S --needed --noconfirm catppuccin-cursors-mocha        || warn "cursor theme failed"
paru -S --needed --noconfirm papirus-folders-catppuccin-git  || warn "catppuccin papirus folders failed"
if command -v papirus-folders >/dev/null 2>&1; then
  sudo papirus-folders -C cat-mocha-mauve --theme Papirus-Dark || warn "papirus-folders recolor failed"
fi

# ------------------------------------------------------------- 4. vim
log "Setting up Vim with Catppuccin Mocha"
mkdir -p ~/.vim/pack/themes/start ~/.vim/undo
if [[ -d ~/.vim/pack/themes/start/catppuccin/.git ]]; then
  git -C ~/.vim/pack/themes/start/catppuccin pull --ff-only
else
  git clone --depth 1 https://github.com/catppuccin/vim.git ~/.vim/pack/themes/start/catppuccin
fi
bak ~/.vimrc
cat > ~/.vimrc <<'EOF'
set nocompatible
syntax on
filetype plugin indent on
set termguicolors
set background=dark
silent! colorscheme catppuccin_mocha
set number relativenumber
set cursorline
set mouse=a
set clipboard=unnamedplus
set tabstop=4 shiftwidth=4 expandtab smartindent
set ignorecase smartcase incsearch hlsearch
set scrolloff=8
set signcolumn=yes
set laststatus=2
set noshowmode
set splitright splitbelow
set undofile undodir=~/.vim/undo
set updatetime=300
EOF

# ------------------------------------------------------------ 5. noctalia
log "Writing Noctalia config: floating rounded bar + Catppuccin theme"
mkdir -p ~/.config/noctalia ~/Pictures/Wallpapers ~/Pictures/Screenshots
if [[ -f ~/.config/noctalia/config.toml ]]; then
  bak ~/.config/noctalia/config.toml
  warn "Existing Noctalia config.toml backed up and replaced."
fi
cat > ~/.config/noctalia/config.toml <<'EOF'
[theme]
mode = "dark"
shell_mode = "follow"
source = "builtin"
builtin = "Catppuccin"
sync_color_scheme = true

[theme.templates]
enable_builtin_templates = true
builtin_ids = ["foot", "gtk3", "gtk4"]

# Floating, rounded, slightly translucent top bar
[bar.main]
enabled = true
position = "top"
thickness = 36
background_opacity = 0.85
margin_edge = 10        # gap from screen edge = floating
margin_ends = 10        # gap from left/right edges
radius = 18             # rounded corners
padding = 14
widget_spacing = 8
reserve_space = true    # windows don't slide under the bar
start  = ["launcher", "workspaces"]
center = ["clock"]
end    = ["media", "tray", "notifications", "clipboard", "network", "bluetooth", "volume", "brightness", "battery", "control-center", "session"]
EOF

# --------------------------------------------------------------- 6. hyprland
log "Writing Hyprland config (Lua, per Noctalia docs)"
mkdir -p ~/.config/hypr
bak ~/.config/hypr/hyprland.lua
cat > ~/.config/hypr/hyprland.lua <<'EOF'
-- Hyprland + Noctalia v5 + Catppuccin Mocha
local mainMod  = "SUPER"
local terminal = "foot"
local ipc      = "noctalia msg"
local function sh(cmd) return hl.dsp.exec_cmd(cmd) end
local function hc(cmd) return hl.dsp.exec_cmd("hyprctl dispatch " .. cmd) end

-- Autostart: Noctalia = bar + notifications + launcher + lock + wallpaper + OSD
hl.on("hyprland.start", function()
  hl.exec_cmd("noctalia")
  hl.exec_cmd("wl-paste --watch cliphist store")
end)

hl.config({
  general = {
    gaps_in = 5,
    gaps_out = 10,
    border_size = 2,
    col = {
      active_border   = "rgb(cba6f7)",   -- mauve
      inactive_border = "rgb(313244)",   -- surface0
    },
  },
  decoration = {
    rounding = 20,
    rounding_power = 2,
    shadow = { enabled = true, range = 4, render_power = 3, color = 0xee1a1a1a },
    blur = { enabled = true, size = 3, passes = 2, vibrancy = 0.1696 },
  },
  input = {
    kb_layout = "us",
    follow_mouse = 1,
    touchpad = { natural_scroll = true },
  },
  misc = {
    disable_hyprland_logo = true,
    disable_splash_rendering = true,
  },
})

-- Blur behind Noctalia's bar, panels, notifications, OSD
hl.layer_rule({
  name = "noctalia",
  match = { namespace = "^noctalia-(bar-.+|notification|dock|panel|attached-panel|osd)$" },
  ignore_alpha = 0.5,
  blur = true,
  blur_popups = true,
})

-- Noctalia: launcher, control center, settings
hl.bind(mainMod .. "+Space",       sh(ipc .. " panel-toggle launcher"))
hl.bind(mainMod .. "+S",           sh(ipc .. " panel-toggle control-center"))
hl.bind(mainMod .. "+comma",       sh(ipc .. " settings-toggle"))

-- Volume / brightness (shows Noctalia OSD)
hl.bind("XF86AudioRaiseVolume",    sh(ipc .. " volume-up"))
hl.bind("XF86AudioLowerVolume",    sh(ipc .. " volume-down"))
hl.bind("XF86AudioMute",           sh(ipc .. " volume-mute"))
hl.bind("XF86MonBrightnessUp",     sh(ipc .. " brightness-up"))
hl.bind("XF86MonBrightnessDown",   sh(ipc .. " brightness-down"))

-- Apps / windows
hl.bind(mainMod .. "+Return",       sh(terminal))
hl.bind(mainMod .. "+B",            sh("firefox"))
hl.bind(mainMod .. "+Q",            hc("killactive"))
hl.bind(mainMod .. "+F",            hc("fullscreen 0"))
hl.bind(mainMod .. "+SHIFT+Space",  hc("togglefloating"))
hl.bind(mainMod .. "+SHIFT+E",      hc("exit"))

-- Focus / move
hl.bind(mainMod .. "+H", hc("movefocus l"))
hl.bind(mainMod .. "+L", hc("movefocus r"))
hl.bind(mainMod .. "+K", hc("movefocus u"))
hl.bind(mainMod .. "+J", hc("movefocus d"))
hl.bind(mainMod .. "+SHIFT+H", hc("movewindow l"))
hl.bind(mainMod .. "+SHIFT+L", hc("movewindow r"))
hl.bind(mainMod .. "+SHIFT+K", hc("movewindow u"))
hl.bind(mainMod .. "+SHIFT+J", hc("movewindow d"))

-- Screenshots (to clipboard)
hl.bind("Print",                 sh('grim -g "$(slurp)" - | wl-copy'))
hl.bind(mainMod .. "+Print",     sh("grim - | wl-copy"))

-- Workspaces 1-9
for i = 1, 9 do
  hl.bind(mainMod .. "+" .. i,            hc("workspace " .. i))
  hl.bind(mainMod .. "+SHIFT+" .. i,      hc("movetoworkspace " .. i))
end
EOF

# ------------------------------------------------- 7. GTK / icons / cursor
log "Setting GTK icon + cursor theme"
for v in 3.0 4.0; do
  mkdir -p ~/.config/gtk-$v
  cat > ~/.config/gtk-$v/settings.ini <<'EOF'
[Settings]
gtk-theme-name=adw-gtk3-dark
gtk-icon-theme-name=Papirus-Dark
gtk-cursor-theme-name=catppuccin-mocha-mauve-cursors
gtk-cursor-theme-size=24
gtk-font-name=Noto Sans 10
gtk-application-prefer-dark-theme=1
EOF
done
mkdir -p ~/.icons/default
cat > ~/.icons/default/index.theme <<'EOF'
[Icon Theme]
Inherits=catppuccin-mocha-mauve-cursors
EOF

# ------------------------------------------------------ 8. session env
log "Setting Wayland environment and auto-start on tty1"
mkdir -p ~/.config/environment.d
cat > ~/.config/environment.d/10-wayland.conf <<'EOF'
XCURSOR_THEME=catppuccin-mocha-mauve-cursors
XCURSOR_SIZE=24
MOZ_ENABLE_WAYLAND=1
QT_QPA_PLATFORM=wayland;xcb
QT_QPA_PLATFORMTHEME=qt6ct
EDITOR=vim
EOF

if ! grep -q 'Hyprland' ~/.bash_profile 2>/dev/null; then
  cat >> ~/.bash_profile <<'EOF'

# Start Hyprland automatically on tty1
if [ -z "${WAYLAND_DISPLAY:-}" ] && [ "${XDG_VTNR:-}" = "1" ]; then
  export XDG_CURRENT_DESKTOP=Hyprland XDG_SESSION_TYPE=wayland XDG_SESSION_DESKTOP=Hyprland
  export XCURSOR_THEME=catppuccin-mocha-mauve-cursors XCURSOR_SIZE=24
  export MOZ_ENABLE_WAYLAND=1 EDITOR=vim
  if command -v start-hyprland >/dev/null 2>&1; then exec start-hyprland; else exec Hyprland; fi
fi
EOF
fi

log "Done. Reboot (or log in on tty1) to start Hyprland + Noctalia."
cat <<'EOF'

Keys: Super+Enter terminal | Super+Space launcher | Super+S control center
      Super+, settings     | Super+Q close         | Super+Shift+E exit
      Super+1..9 workspaces | Super+hjkl focus     | Print screenshot

Drop wallpapers in ~/Pictures/Wallpapers, pick one from the launcher/bar.
If Hyprland shows a config error banner, run: hyprctl configerrors
EOF
