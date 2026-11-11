#!/usr/bin/env bash
# =============================================================================
# i3 + Catppuccin Mocha setup for a minimal Arch Linux install
# Run as the normal user (dazaiosamu, with sudo), NOT as root:
#     bash setup-i3-catppuccin.sh
# =============================================================================
set -euo pipefail

USER_NAME="dazaiosamu"
HOME_DIR="$HOME"
CFG="$HOME_DIR/.config"

log()  { printf '\n\033[1;35m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[warn] %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m[error] %s\033[0m\n' "$*"; exit 1; }

[ "$EUID" -ne 0 ] || die "Do not run as root. Run as $USER_NAME (needs sudo)."
[ "$(id -un)" = "$USER_NAME" ] || warn "Running as $(id -un), expected $USER_NAME. Continuing anyway."
command -v sudo >/dev/null || die "sudo is not installed."
sudo -v || die "sudo authentication failed."

backup() {
  for p in "$@"; do
    if [ -e "$p" ] && [ ! -L "$p" ]; then cp -a "$p" "$p.bak.$(date +%s)"; fi
  done
  return 0
}

# -----------------------------------------------------------------------------
log "1/11  Updating system and installing packages"
# -----------------------------------------------------------------------------
PKGS=(
  # build tools (for the AUR theme)
  base-devel git
  # X11 + i3
  xorg-server xorg-xinit xorg-xsetroot xorg-xset xorg-xrdb xf86-input-libinput mesa
  i3-wm xss-lock polybar rofi dunst libnotify
  # terminal, shell, prompt
  alacritty fish starship
  # CLI quality of life
  eza bat fd ripgrep fzf zoxide btop nano unzip xdg-utils
  # rust
  rustup
  # browser
  chromium
  # fonts + icons
  ttf-jetbrains-mono-nerd noto-fonts noto-fonts-emoji papirus-icon-theme adwaita-icon-theme
  # audio (PipeWire)
  pipewire pipewire-pulse pipewire-alsa wireplumber pavucontrol alsa-utils playerctl
  # laptop / desktop utilities
  brightnessctl networkmanager network-manager-applet maim xclip thunar gvfs
)
sudo pacman -Syu --needed --noconfirm "${PKGS[@]}"

# -----------------------------------------------------------------------------
log "2/11  Enabling services and groups"
# -----------------------------------------------------------------------------
# NetworkManager only if no other network manager is already active
if ! systemctl is-active --quiet systemd-networkd && ! systemctl is-active --quiet iwd; then
  sudo systemctl enable --now NetworkManager || warn "Could not enable NetworkManager"
else
  warn "systemd-networkd or iwd is active, leaving networking alone (nm-applet will be idle)."
fi
sudo usermod -aG video "$USER_NAME" || warn "Could not add $USER_NAME to video group"

# PipeWire user services (enabled globally so they start on first login)
sudo systemctl --global enable pipewire.socket pipewire-pulse.socket wireplumber.service \
  || warn "Could not enable PipeWire user services globally"
systemctl --user enable --now pipewire.socket pipewire-pulse.socket wireplumber.service 2>/dev/null \
  || warn "PipeWire will start automatically at your first graphical login"

# Touchpad: tap-to-click
sudo mkdir -p /etc/X11/xorg.conf.d
sudo tee /etc/X11/xorg.conf.d/30-touchpad.conf >/dev/null <<'EOF'
Section "InputClass"
    Identifier "libinput touchpad"
    MatchIsTouchpad "on"
    Driver "libinput"
    Option "Tapping" "on"
    Option "DisableWhileTyping" "on"
EndSection
EOF

# -----------------------------------------------------------------------------
log "3/11  Rust toolchain"
# -----------------------------------------------------------------------------
rustup default stable || warn "rustup default stable failed (network?)"
rustup component add rust-analyzer clippy rustfmt || warn "Could not add rust components"

# -----------------------------------------------------------------------------
log "4/11  Git defaults"
# -----------------------------------------------------------------------------
git config --global init.defaultBranch main
warn "Set your identity later: git config --global user.name 'Name' && git config --global user.email 'you@example.com'"

# -----------------------------------------------------------------------------
log "5/11  i3 window manager (Catppuccin Mocha)"
# -----------------------------------------------------------------------------
backup "$CFG/i3" "$HOME_DIR/.xinitrc"
mkdir -p "$CFG/i3" "$HOME_DIR/Pictures"

cat > "$HOME_DIR/.xinitrc" <<'EOF'
#!/bin/sh
[ -f "$HOME/.Xresources" ] && xrdb -merge "$HOME/.Xresources"
exec i3
EOF
chmod +x "$HOME_DIR/.xinitrc"

cat > "$CFG/i3/config" <<'EOF'
# =============================================================================
# i3 config - Catppuccin Mocha
# =============================================================================
set $mod Mod4
set $term alacritty
set $browser chromium

# --- Catppuccin Mocha palette ---
set $rosewater #f5e0dc
set $mauve     #cba6f7
set $red       #f38ba8
set $peach     #fab387
set $lavender  #b4befe
set $text      #cdd6f4
set $overlay0  #6c7086
set $surface0  #313244
set $base      #1e1e2e
set $mantle    #181825

font pango:JetBrainsMono Nerd Font 10
floating_modifier $mod

default_border pixel 2
default_floating_border pixel 2
hide_edge_borders smart
gaps inner 6
gaps outer 0

# class                 border     background text      indicator  child_border
client.focused          $lavender  $base      $text     $rosewater $lavender
client.focused_inactive $overlay0  $base      $text     $overlay0  $overlay0
client.unfocused        $overlay0  $base      $text     $overlay0  $overlay0
client.urgent           $peach     $base      $peach    $overlay0  $peach
client.placeholder      $overlay0  $base      $text     $overlay0  $overlay0
client.background       $base

# --- Autostart ---
exec --no-startup-id xsetroot -solid "#1e1e2e"
exec --no-startup-id nm-applet
exec --no-startup-id dunst
# Idle: lock after 10 min, screen off after 15 min
exec --no-startup-id xset s 600 5
exec --no-startup-id xset dpms 0 0 900
# Lock automatically on idle, suspend and lid close
exec --no-startup-id xss-lock --transfer-sleep-lock -- ~/.config/i3/lock.sh
exec_always --no-startup-id ~/.config/polybar/launch.sh

# --- Launch apps ---
bindsym $mod+Return exec $term
bindsym $mod+d exec --no-startup-id rofi -show drun
bindsym $mod+Tab exec --no-startup-id rofi -show window
bindsym $mod+b exec $browser
bindsym $mod+e exec thunar
bindsym $mod+x exec --no-startup-id ~/.config/i3/lock.sh
bindsym $mod+Shift+e exec --no-startup-id ~/.config/i3/powermenu.sh
bindsym $mod+F1 exec $term -e less ~/keybinds.txt

# --- Window management ---
bindsym $mod+Shift+q kill
bindsym $mod+h focus left
bindsym $mod+j focus down
bindsym $mod+k focus up
bindsym $mod+l focus right
bindsym $mod+Left focus left
bindsym $mod+Down focus down
bindsym $mod+Up focus up
bindsym $mod+Right focus right

bindsym $mod+Shift+h move left
bindsym $mod+Shift+j move down
bindsym $mod+Shift+k move up
bindsym $mod+Shift+l move right
bindsym $mod+Shift+Left move left
bindsym $mod+Shift+Down move down
bindsym $mod+Shift+Up move up
bindsym $mod+Shift+Right move right

bindsym $mod+g split h
bindsym $mod+v split v
bindsym $mod+f fullscreen toggle
bindsym $mod+s layout stacking
bindsym $mod+w layout tabbed
bindsym $mod+t layout toggle split
bindsym $mod+Shift+space floating toggle
bindsym $mod+space focus mode_toggle
bindsym $mod+a focus parent

bindsym $mod+Shift+minus move scratchpad
bindsym $mod+minus scratchpad show

# --- i3 control ---
bindsym $mod+Shift+c reload
bindsym $mod+Shift+r restart

# --- Resize mode ---
mode "resize" {
    bindsym h resize shrink width 20 px or 2 ppt
    bindsym j resize grow height 20 px or 2 ppt
    bindsym k resize shrink height 20 px or 2 ppt
    bindsym l resize grow width 20 px or 2 ppt
    bindsym Left resize shrink width 20 px or 2 ppt
    bindsym Down resize grow height 20 px or 2 ppt
    bindsym Up resize shrink height 20 px or 2 ppt
    bindsym Right resize grow width 20 px or 2 ppt
    bindsym Return mode "default"
    bindsym Escape mode "default"
    bindsym $mod+r mode "default"
}
bindsym $mod+r mode "resize"

# --- Audio (PipeWire / WirePlumber) ---
bindsym XF86AudioRaiseVolume exec --no-startup-id wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+
bindsym XF86AudioLowerVolume exec --no-startup-id wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
bindsym XF86AudioMute exec --no-startup-id wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
bindsym XF86AudioMicMute exec --no-startup-id wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle
bindsym XF86AudioPlay exec --no-startup-id playerctl play-pause
bindsym XF86AudioNext exec --no-startup-id playerctl next
bindsym XF86AudioPrev exec --no-startup-id playerctl previous

# --- Brightness ---
bindsym XF86MonBrightnessUp exec --no-startup-id brightnessctl set 5%+
bindsym XF86MonBrightnessDown exec --no-startup-id brightnessctl set 5%-

# --- Screenshots ---
bindsym Print exec --no-startup-id maim ~/Pictures/screenshot-$(date +%Y%m%d-%H%M%S).png
bindsym Shift+Print exec --no-startup-id maim -s | xclip -selection clipboard -t image/png
bindsym Ctrl+Print exec --no-startup-id maim -s ~/Pictures/screenshot-$(date +%Y%m%d-%H%M%S).png

# --- Floating rules ---
for_window [class="Pavucontrol"] floating enable
for_window [class="Nm-connection-editor"] floating enable
for_window [window_role="pop-up"] floating enable

# --- Workspaces ---
EOF

# Workspace bindings 1-10
{
  for i in 1 2 3 4 5 6 7 8 9 10; do
    key=$((i % 10))
    echo "bindsym \$mod+$key workspace number $i"
    echo "bindsym \$mod+Shift+$key move container to workspace number $i"
  done
} >> "$CFG/i3/config"

cat > "$CFG/i3/powermenu.sh" <<'EOF'
#!/usr/bin/env bash
choice=$(printf 'Lock\nLogout\nSuspend\nReboot\nShutdown\n' | rofi -dmenu -i -p 'Power')
case "$choice" in
  Lock)     ~/.config/i3/lock.sh ;;
  Logout)   i3-msg exit ;;
  Suspend)  systemctl suspend ;;   # xss-lock locks the screen automatically
  Reboot)   systemctl reboot ;;
  Shutdown) systemctl poweroff ;;
esac
EOF
chmod +x "$CFG/i3/powermenu.sh"

# Catppuccin Mocha lock screen (i3lock-color, falls back to plain i3lock)
cat > "$CFG/i3/lock.sh" <<'EOF'
#!/usr/bin/env bash
# Do nothing if already locked
pgrep -x i3lock >/dev/null && exit 0

if pacman -Qq i3lock-color >/dev/null 2>&1; then
  exec i3lock --nofork \
    --color=1e1e2e \
    --clock --indicator \
    --time-str="%H:%M" --date-str="%A, %d %B" \
    --time-font="JetBrainsMono Nerd Font" --date-font="JetBrainsMono Nerd Font" \
    --time-size=64 --date-size=20 \
    --time-color=cdd6f4ff --date-color=a6adc8ff \
    --radius=120 --ring-width=8 \
    --inside-color=1e1e2eff --ring-color=b4befeff \
    --insidever-color=1e1e2eff --ringver-color=a6e3a1ff \
    --insidewrong-color=1e1e2eff --ringwrong-color=f38ba8ff \
    --line-color=00000000 --separator-color=313244ff \
    --keyhl-color=cba6f7ff --bshl-color=fab387ff \
    --verif-color=a6e3a1ff --wrong-color=f38ba8ff \
    --verif-text="Verifying..." --wrong-text="Wrong password" --noinput-text="" \
    --ignore-empty-password --show-failed-attempts
else
  exec i3lock --nofork --color=1e1e2e
fi
EOF
chmod +x "$CFG/i3/lock.sh"

# -----------------------------------------------------------------------------
log "6/11  Alacritty terminal (Catppuccin Mocha)"
# -----------------------------------------------------------------------------
backup "$CFG/alacritty"
mkdir -p "$CFG/alacritty"
cat > "$CFG/alacritty/alacritty.toml" <<'EOF'
[font]
size = 11.0
[font.normal]
family = "JetBrainsMono Nerd Font"
style = "Regular"

[window]
dynamic_padding = true
[window.padding]
x = 8
y = 8

[scrolling]
history = 10000

[colors.primary]
background = "#1e1e2e"
foreground = "#cdd6f4"
dim_foreground = "#7f849c"
bright_foreground = "#cdd6f4"

[colors.cursor]
text = "#1e1e2e"
cursor = "#f5e0dc"

[colors.vi_mode_cursor]
text = "#1e1e2e"
cursor = "#b4befe"

[colors.search.matches]
foreground = "#1e1e2e"
background = "#a6adc8"

[colors.search.focused_match]
foreground = "#1e1e2e"
background = "#a6e3a1"

[colors.footer_bar]
foreground = "#1e1e2e"
background = "#a6adc8"

[colors.hints.start]
foreground = "#1e1e2e"
background = "#f9e2af"

[colors.hints.end]
foreground = "#1e1e2e"
background = "#a6adc8"

[colors.selection]
text = "#1e1e2e"
background = "#f5e0dc"

[colors.normal]
black = "#45475a"
red = "#f38ba8"
green = "#a6e3a1"
yellow = "#f9e2af"
blue = "#89b4fa"
magenta = "#f5c2e7"
cyan = "#94e2d5"
white = "#bac2de"

[colors.bright]
black = "#585b70"
red = "#f38ba8"
green = "#a6e3a1"
yellow = "#f9e2af"
blue = "#89b4fa"
magenta = "#f5c2e7"
cyan = "#94e2d5"
white = "#a6adc8"

[colors.dim]
black = "#45475a"
red = "#f38ba8"
green = "#a6e3a1"
yellow = "#f9e2af"
blue = "#89b4fa"
magenta = "#f5c2e7"
cyan = "#94e2d5"
white = "#bac2de"

[[colors.indexed_colors]]
index = 16
color = "#fab387"

[[colors.indexed_colors]]
index = 17
color = "#f5e0dc"
EOF

# -----------------------------------------------------------------------------
log "7/11  Polybar (top bar), dunst (notifications), rofi (launcher)"
# -----------------------------------------------------------------------------
backup "$CFG/polybar" "$CFG/dunst" "$CFG/rofi"
mkdir -p "$CFG/polybar" "$CFG/dunst" "$CFG/rofi/themes"

# Detect battery / AC adapter / backlight
BAT=""; ADP=""; BACKLIGHT=""
for f in /sys/class/power_supply/*; do
  [ -e "$f/type" ] || continue
  case "$(cat "$f/type")" in
    Battery) [ -z "$BAT" ] && BAT="$(basename "$f")" ;;
    Mains)   [ -z "$ADP" ] && ADP="$(basename "$f")" ;;
  esac
done
[ -n "$BAT" ] || BAT=""
if [ -d /sys/class/backlight ]; then
  BACKLIGHT="$(ls /sys/class/backlight 2>/dev/null | head -n1 || true)"
fi

MODS="pulseaudio"
if [ -n "$BACKLIGHT" ]; then MODS="$MODS backlight"; fi
MODS="$MODS cpu memory network"
if [ -n "$BAT" ]; then MODS="$MODS battery"; fi

cat > "$CFG/polybar/config.ini" <<'EOF'
[colors]
base = #1e1e2e
mantle = #181825
text = #cdd6f4
subtext0 = #a6adc8
overlay0 = #6c7086
surface0 = #313244
blue = #89b4fa
lavender = #b4befe
mauve = #cba6f7
green = #a6e3a1
yellow = #f9e2af
peach = #fab387
red = #f38ba8
teal = #94e2d5

[bar/main]
width = 100%
height = 28pt
fixed-center = true
background = ${colors.base}
foreground = ${colors.text}
line-size = 2pt
padding-left = 1
padding-right = 1
module-margin = 1
separator = |
separator-foreground = ${colors.overlay0}
font-0 = JetBrainsMono Nerd Font:size=10;2
modules-left = i3
modules-center = date
modules-right = __MODULES_RIGHT__
tray-position = right
tray-padding = 2
cursor-click = pointer
enable-ipc = true
wm-restack = i3

[module/i3]
type = internal/i3
pin-workspaces = true
index-sort = true
label-focused = %index%
label-focused-background = ${colors.surface0}
label-focused-foreground = ${colors.lavender}
label-focused-underline = ${colors.mauve}
label-focused-padding = 1
label-unfocused = %index%
label-unfocused-foreground = ${colors.subtext0}
label-unfocused-padding = 1
label-visible = %index%
label-visible-padding = 1
label-urgent = %index%
label-urgent-background = ${colors.red}
label-urgent-foreground = ${colors.base}
label-urgent-padding = 1

[module/date]
type = internal/date
interval = 1
date = %a %d %b
time = %H:%M
label = %date%  %time%
label-foreground = ${colors.text}

[module/pulseaudio]
type = internal/pulseaudio
format-volume = <label-volume>
format-volume-prefix = "VOL "
format-volume-prefix-foreground = ${colors.mauve}
label-volume = %percentage%%
label-muted = muted
label-muted-foreground = ${colors.overlay0}
click-right = pavucontrol

[module/backlight]
type = internal/backlight
card = __BACKLIGHT__
format-prefix = "BRI "
format-prefix-foreground = ${colors.yellow}
label = %percentage%%

[module/cpu]
type = internal/cpu
interval = 2
format-prefix = "CPU "
format-prefix-foreground = ${colors.blue}
label = %percentage:2%%

[module/memory]
type = internal/memory
interval = 2
format-prefix = "RAM "
format-prefix-foreground = ${colors.teal}
label = %percentage_used:2%%

[module/network]
type = internal/network
interface-type = wireless
interval = 3
format-connected = <label-connected>
format-connected-prefix = "WIFI "
format-connected-prefix-foreground = ${colors.green}
label-connected = %essid% %signal%%
format-disconnected = <label-disconnected>
label-disconnected = no wifi
label-disconnected-foreground = ${colors.overlay0}

[module/battery]
type = internal/battery
battery = __BAT__
adapter = __ADP__
full-at = 99
low-at = 15
poll-interval = 5
time-format = %H:%M
format-charging = <label-charging>
format-charging-prefix = "CHG "
format-charging-prefix-foreground = ${colors.green}
format-discharging = <label-discharging>
format-discharging-prefix = "BAT "
format-discharging-prefix-foreground = ${colors.peach}
format-full = <label-full>
format-full-prefix = "FULL "
format-full-prefix-foreground = ${colors.green}
format-low = <label-low>
format-low-prefix = "LOW "
format-low-prefix-foreground = ${colors.red}
label-charging = %percentage%% (%time% to full)
label-discharging = %percentage%% (%time% left)
label-full = %percentage%%
label-low = %percentage%% (%time% left)

[settings]
screenchange-reload = true
pseudo-transparency = true
EOF
sed -i "s|__MODULES_RIGHT__|$MODS|g; s|__BACKLIGHT__|$BACKLIGHT|g; s|__BAT__|$BAT|g; s|__ADP__|$ADP|g" "$CFG/polybar/config.ini"

cat > "$CFG/polybar/launch.sh" <<'EOF'
#!/usr/bin/env bash
killall -q polybar
while pgrep -u "$UID" -x polybar >/dev/null; do sleep 0.2; done
polybar main >/tmp/polybar.log 2>&1 &
EOF
chmod +x "$CFG/polybar/launch.sh"

cat > "$CFG/dunst/dunstrc" <<'EOF'
[global]
    monitor = 0
    follow = mouse
    width = (0, 350)
    height = (0, 300)
    origin = top-right
    offset = (12, 40)
    notification_limit = 5
    padding = 12
    horizontal_padding = 14
    frame_width = 2
    gap_size = 8
    corner_radius = 8
    font = JetBrainsMono Nerd Font 10
    markup = full
    format = "<b>%s</b>\n%b"
    alignment = left
    icon_position = left
    max_icon_size = 48
    icon_theme = "Papirus-Dark"
    enable_recursive_icon_lookup = true
    separator_color = frame
    mouse_left_click = close_current
    mouse_middle_click = do_action, close_current
    mouse_right_click = close_all

[urgency_low]
    background = "#1e1e2e"
    foreground = "#cdd6f4"
    frame_color = "#6c7086"
    timeout = 5

[urgency_normal]
    background = "#1e1e2e"
    foreground = "#cdd6f4"
    frame_color = "#b4befe"
    timeout = 8

[urgency_critical]
    background = "#1e1e2e"
    foreground = "#cdd6f4"
    frame_color = "#fab387"
    timeout = 0
EOF

cat > "$CFG/rofi/config.rasi" <<'EOF'
configuration {
  modi: "drun,run,window";
  show-icons: true;
  icon-theme: "Papirus-Dark";
  font: "JetBrainsMono Nerd Font 11";
  display-drun: "Apps";
  display-run: "Run";
  display-window: "Windows";
}
@theme "catppuccin-mocha"
EOF

cat > "$CFG/rofi/themes/catppuccin-mocha.rasi" <<'EOF'
* {
  base: #1e1e2e;
  surface0: #313244;
  text: #cdd6f4;
  mauve: #cba6f7;
  lavender: #b4befe;
  overlay0: #6c7086;
  background-color: transparent;
  text-color: @text;
}
window {
  width: 520px;
  background-color: @base;
  border: 2px;
  border-color: @lavender;
  border-radius: 10px;
}
mainbox {
  padding: 12px;
  spacing: 10px;
  children: [inputbar, listview];
}
inputbar {
  background-color: @surface0;
  border-radius: 8px;
  padding: 8px 12px;
  spacing: 8px;
  children: [prompt, entry];
}
prompt { text-color: @mauve; }
entry {
  placeholder: "Search...";
  placeholder-color: @overlay0;
}
listview {
  lines: 8;
  columns: 1;
  fixed-height: false;
  spacing: 4px;
  scrollbar: false;
}
element {
  padding: 8px 10px;
  border-radius: 8px;
  spacing: 8px;
}
element selected.normal {
  background-color: @surface0;
  text-color: @lavender;
}
element-icon { size: 1.2em; }
element-text { vertical-align: 0.5; }
EOF

# -----------------------------------------------------------------------------
log "8/11  Fish shell + Starship prompt (Catppuccin Mocha)"
# -----------------------------------------------------------------------------
backup "$CFG/fish" "$CFG/starship.toml"
mkdir -p "$CFG/fish"

cat > "$CFG/fish/config.fish" <<'EOF'
# --- Auto-start X on tty1 ---
if status is-login
    if test -z "$DISPLAY" -a "$XDG_VTNR" = "1"
        exec startx
    end
end

# --- Environment ---
set -gx EDITOR nano
set -gx BROWSER chromium
fish_add_path -g $HOME/.cargo/bin $HOME/.local/bin

# --- Catppuccin Mocha colors ---
set -g fish_color_normal cdd6f4
set -g fish_color_command 89b4fa
set -g fish_color_param f2cdcd
set -g fish_color_keyword f38ba8
set -g fish_color_quote a6e3a1
set -g fish_color_redirection f5c2e7
set -g fish_color_end fab387
set -g fish_color_comment 7f849c
set -g fish_color_error f38ba8
set -g fish_color_gray 6c7086
set -g fish_color_selection --background=313244
set -g fish_color_search_match --background=313244
set -g fish_color_operator f5c2e7
set -g fish_color_escape f2cdcd
set -g fish_color_autosuggestion 6c7086
set -g fish_color_cancel f38ba8
set -g fish_color_cwd f9e2af
set -g fish_color_user 94e2d5
set -g fish_color_host 89b4fa
set -g fish_color_host_remote a6e3a1
set -g fish_color_status f38ba8
set -g fish_pager_color_progress 6c7086
set -g fish_pager_color_prefix f5c2e7
set -g fish_pager_color_completion cdd6f4
set -g fish_pager_color_description 6c7086
set -g fish_pager_color_selected_background --background=313244

set -gx FZF_DEFAULT_OPTS "--color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8 --color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc --color=marker:#b4befe,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8,selected-bg:#45475a"

if status is-interactive
    set -g fish_greeting

    # Prompt and tools
    type -q starship; and starship init fish | source
    type -q zoxide; and zoxide init fish | source
    type -q fzf; and fzf --fish 2>/dev/null | source

    # --- General ---
    if type -q eza
        alias ls 'eza --icons --group-directories-first'
        alias ll 'eza -l --icons --group-directories-first --git'
        alias la 'eza -la --icons --group-directories-first --git'
        alias lt 'eza --tree --level=2 --icons'
    end
    abbr -a .. 'cd ..'
    abbr -a ... 'cd ../..'
    abbr -a c clear
    abbr -a pac 'sudo pacman -S'
    abbr -a pacu 'sudo pacman -Syu'
    abbr -a pacr 'sudo pacman -Rns'
    abbr -a pacs 'pacman -Ss'

    # --- Git ---
    abbr -a g git
    abbr -a gs 'git status -sb'
    abbr -a ga 'git add'
    abbr -a gaa 'git add --all'
    abbr -a gc 'git commit'
    abbr -a gcm 'git commit -m'
    abbr -a gca 'git commit --amend'
    abbr -a gco 'git checkout'
    abbr -a gsw 'git switch'
    abbr -a gb 'git branch'
    abbr -a gbd 'git branch -d'
    abbr -a gd 'git diff'
    abbr -a gds 'git diff --staged'
    abbr -a gf 'git fetch'
    abbr -a gl 'git pull'
    abbr -a gp 'git push'
    abbr -a gpf 'git push --force-with-lease'
    abbr -a glg 'git log --oneline --graph --decorate'
    abbr -a gst 'git stash'
    abbr -a gstp 'git stash pop'
    abbr -a grb 'git rebase'
    abbr -a gr 'git restore'
    abbr -a grs 'git restore --staged'
    abbr -a gcl 'git clone'

    # --- Rust ---
    abbr -a cb 'cargo build'
    abbr -a cbr 'cargo build --release'
    abbr -a cr 'cargo run'
    abbr -a crr 'cargo run --release'
    abbr -a ct 'cargo test'
    abbr -a ck 'cargo check'
    abbr -a cl 'cargo clippy --all-targets -- -D warnings'
    abbr -a cf 'cargo fmt'
    abbr -a cn 'cargo new'
    abbr -a cad 'cargo add'
    abbr -a cu 'cargo update'
    abbr -a cdo 'cargo doc --open'
    abbr -a ccl 'cargo clean'
    abbr -a cin 'cargo install --path .'
    abbr -a ru rustup
    abbr -a rup 'rustup update'
end

function mkcd --description 'mkdir and cd into it'
    mkdir -p $argv[1]; and cd $argv[1]
end
EOF

cat > "$CFG/starship.toml" <<'EOF'
"$schema" = 'https://starship.rs/config-schema.json'

add_newline = true
palette = 'catppuccin_mocha'
command_timeout = 500

format = """
$username$hostname$directory$git_branch$git_status$rust$python$nodejs$cmd_duration
$character"""

[character]
success_symbol = '[❯](bold green)'
error_symbol = '[❯](bold red)'
vimcmd_symbol = '[❮](bold mauve)'

[username]
show_always = false
style_user = 'bold teal'
format = '[$user]($style)@'

[hostname]
ssh_only = true
style = 'bold blue'
format = '[$hostname]($style) '

[directory]
style = 'bold lavender'
truncation_length = 3
truncation_symbol = '…/'
read_only = ' (ro)'
format = '[$path]($style)[$read_only]($read_only_style) '

[git_branch]
symbol = ''
style = 'bold mauve'
format = '[on $symbol$branch(:$remote_branch)]($style) '

[git_status]
style = 'bold red'
format = '([\[$all_status$ahead_behind\]]($style) )'

[rust]
symbol = '🦀 '
style = 'bold peach'
format = '[$symbol($version )]($style)'

[python]
style = 'yellow'
format = '[${symbol}${pyenv_prefix}(${version} )(\($virtualenv\) )]($style)'

[nodejs]
style = 'green'
format = '[$symbol($version )]($style)'

[cmd_duration]
min_time = 3000
style = 'yellow'
format = '[took $duration]($style) '

[palettes.catppuccin_mocha]
rosewater = '#f5e0dc'
flamingo = '#f2cdcd'
pink = '#f5c2e7'
mauve = '#cba6f7'
red = '#f38ba8'
maroon = '#eba0ac'
peach = '#fab387'
yellow = '#f9e2af'
green = '#a6e3a1'
teal = '#94e2d5'
sky = '#89dceb'
sapphire = '#74c7ec'
blue = '#89b4fa'
lavender = '#b4befe'
text = '#cdd6f4'
subtext1 = '#bac2de'
subtext0 = '#a6adc8'
overlay2 = '#9399b2'
overlay1 = '#7f849c'
overlay0 = '#6c7086'
surface2 = '#585b70'
surface1 = '#45475a'
surface0 = '#313244'
base = '#1e1e2e'
mantle = '#181825'
crust = '#11111b'
EOF

sudo chsh -s /usr/bin/fish "$USER_NAME" || warn "Could not set fish as default shell"

# -----------------------------------------------------------------------------
log "9/11  AUR packages: i3lock-color (lock screen) + Catppuccin GTK theme"
# -----------------------------------------------------------------------------
ensure_yay() {
  command -v yay >/dev/null 2>&1 && return 0
  local tmp; tmp="$(mktemp -d)"
  git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin" \
    && (cd "$tmp/yay-bin" && makepkg -si --noconfirm --needed)
}
if ensure_yay; then
  yay -S --needed --noconfirm i3lock-color \
    || { warn "i3lock-color failed, installing plain i3lock (basic lock screen)."; sudo pacman -S --needed --noconfirm i3lock; }
  yay -S --needed --noconfirm catppuccin-gtk-theme-mocha \
    || warn "AUR Catppuccin GTK theme failed, falling back to Adwaita-dark."
else
  warn "Could not install yay. Using plain i3lock and Adwaita-dark."
  sudo pacman -S --needed --noconfirm i3lock || true
fi

GTK_THEME_NAME="$(ls /usr/share/themes 2>/dev/null | grep -i '^catppuccin-mocha' | head -n1 || true)"
[ -n "$GTK_THEME_NAME" ] || GTK_THEME_NAME="Adwaita-dark"

backup "$CFG/gtk-3.0/settings.ini" "$CFG/gtk-4.0/settings.ini"
mkdir -p "$CFG/gtk-3.0" "$CFG/gtk-4.0"
for v in 3.0 4.0; do
  cat > "$CFG/gtk-$v/settings.ini" <<EOF
[Settings]
gtk-theme-name=$GTK_THEME_NAME
gtk-icon-theme-name=Papirus-Dark
gtk-font-name=Noto Sans 10
gtk-application-prefer-dark-theme=1
EOF
done

# -----------------------------------------------------------------------------
log "10/11  Chromium (dark + Catppuccin base color)"
# -----------------------------------------------------------------------------
sudo mkdir -p /etc/chromium/policies/managed
sudo tee /etc/chromium/policies/managed/catppuccin.json >/dev/null <<'EOF'
{
  "BrowserThemeColor": "#1e1e2e",
  "BrowserColorScheme": "dark"
}
EOF
cat > "$CFG/chromium-flags.conf" <<'EOF'
--force-dark-mode
--enable-features=WebUIDarkMode
EOF
xdg-settings set default-web-browser chromium.desktop 2>/dev/null || true

# -----------------------------------------------------------------------------
log "11/11  Writing ~/keybinds.txt"
# -----------------------------------------------------------------------------
cat > "$HOME_DIR/keybinds.txt" <<'EOF'
=====================================================================
 KEYBINDINGS  (Mod = Super / Windows key)        Open this file: Mod+F1
=====================================================================

--- APPS ---
Mod+Return              Open terminal (Alacritty)
Mod+d                   App launcher (rofi)
Mod+Tab                 Window switcher (rofi)
Mod+b                   Browser (Chromium)
Mod+e                   File manager (Thunar)
Mod+x                   Lock screen (also auto-locks after 10 min idle,
                        on suspend, and when the laptop lid closes)
Mod+Shift+e             Power menu (lock/logout/suspend/reboot/shutdown)
Mod+F1                  Show this keybind list

--- WINDOWS ---
Mod+Shift+q             Close focused window
Mod+h/j/k/l             Focus left/down/up/right
Mod+Arrow keys          Focus left/down/up/right
Mod+Shift+h/j/k/l       Move window left/down/up/right
Mod+Shift+Arrow keys    Move window left/down/up/right
Mod+g                   Next window opens horizontally (split h)
Mod+v                   Next window opens vertically (split v)
Mod+f                   Toggle fullscreen
Mod+s                   Stacking layout
Mod+w                   Tabbed layout
Mod+t                   Toggle split layout
Mod+Shift+Space         Toggle floating
Mod+Space               Toggle focus between tiling / floating
Mod+a                   Focus parent container
Mod+Shift+Minus         Send window to scratchpad
Mod+Minus               Show / hide scratchpad
Mod+Left-drag           Move floating window
Mod+Right-drag          Resize floating window

--- RESIZE MODE ---
Mod+r                   Enter resize mode
  h / Left              Shrink width
  l / Right             Grow width
  k / Up                Shrink height
  j / Down              Grow height
  Enter / Esc / Mod+r   Leave resize mode

--- WORKSPACES ---
Mod+1 ... Mod+9, Mod+0  Switch to workspace 1-10
Mod+Shift+1 ... 0       Move window to workspace 1-10

--- i3 ---
Mod+Shift+c             Reload config
Mod+Shift+r             Restart i3 in place

--- AUDIO (PipeWire) ---
XF86AudioRaiseVolume    Volume +5%
XF86AudioLowerVolume    Volume -5%
XF86AudioMute           Mute / unmute speakers
XF86AudioMicMute        Mute / unmute microphone
XF86AudioPlay           Play / pause
XF86AudioNext / Prev    Next / previous track
(Click the VOL module on the bar with right-click for pavucontrol)

--- BRIGHTNESS ---
XF86MonBrightnessUp     Brightness +5%
XF86MonBrightnessDown   Brightness -5%

--- SCREENSHOTS (saved to ~/Pictures) ---
Print                   Full screen -> file
Ctrl+Print              Select area -> file
Shift+Print             Select area -> clipboard

--- FISH ABBREVIATIONS (type, then Space to expand) ---
Git:   g gs ga gaa gc gcm gca gco gsw gb gbd gd gds gf gl gp gpf glg gst gstp grb gr grs gcl
Rust:  cb cbr cr crr ct ck cl cf cn cad cu cdo ccl cin ru rup
Other: pac pacu pacr pacs  mkcd <dir>  ls/ll/la/lt (eza)

--- TERMINAL (Alacritty) ---
Ctrl+Shift+C / V        Copy / paste
Ctrl+Shift+Space        Vi mode
Ctrl+Shift+F            Search
EOF

# -----------------------------------------------------------------------------
cat <<'EOF'

============================================================
 DONE.
 - Log out and log in on tty1: X and i3 start automatically.
   (Or run: startx)
 - Press Super+F1 to see ~/keybinds.txt
 - Lock screen: Super+x (auto-locks after 10 min idle, on suspend, lid close)
 - Chromium: dark mode + Catppuccin base color are applied.
   For the full Catppuccin Mocha theme, open the Chrome Web Store,
   search "Catppuccin Chrome Theme - Mocha" and click Add.
 - Set your git identity:
     git config --global user.name  "Your Name"
     git config --global user.email "you@example.com"
============================================================
EOF
