#!/bin/bash
#### install.sh
# This script automates the installation and configuration of a customized Arch Linux environment with bspwm.

# --- Colors ---
greenColour="\e[0;32m\033[1m"
endColour="\033[0m\e[0m"
redColour="\e[0;31m\033[1m"
blueColour="\e[0;34m\033[1m"
yellowColour="\e[0;33m\033[1m"
purpleColour="\e[0;35m\033[1m"
turquoiseColour="\e[0;36m\033[1m"
grayColour="\e[0;37m\033[1m"

# --- Global variables ---
dir="$(cd "$(dirname "$0")" && pwd)"
fdir="$HOME/.local/share/fonts"
LOG_FILE="$HOME/install-log.log"

# Everything that differs between Arch and Debian/Kali is asked of this file and
# decided nowhere else.
DISTRO_LIB="$dir/dotfiles/polybar/.config/polybar/theme/scripts/lib/distro.sh"
if [[ ! -r "$DISTRO_LIB" ]]; then
    echo "error: missing $DISTRO_LIB - is the clone complete?" && exit 1
fi
# shellcheck source=dotfiles/polybar/.config/polybar/theme/scripts/lib/distro.sh
. "$DISTRO_LIB"

if [[ "$(distro_id)" == unknown ]]; then
    echo "error: this installer supports Arch and Debian/Kali. /etc/os-release says neither." && exit 1
fi

# --- Logging ---
exec > >(tee -a "$LOG_FILE") 2>&1

# --- Pre-flight checks ---
# Check if the script is run as root, which is not recommended.
[ "$(id -u)" -eq 0 ] && echo "error: Avoid running install.sh as root/sudo." && exit

# --- Password Caching ---
# Ask for the sudo password at the beginning and keep the session alive.
# This avoids prompting for the password repeatedly during the installation.
echo -ne "\n${blueColour}[*]${endColour} Please enter your password to begin the installation.\n"
sudo -v
if [ $? -ne 0 ]; then
    echo -e "${redColour}[!] Incorrect password or sudo permissions denied. Aborting.${endColour}"
    exit 1
fi

# Keep the sudo session alive in the background by updating the timestamp every 50 seconds.
(while true; do sudo -n true; sleep 50; done) &
SUDO_PID=$!
# Ensure the background process is killed when the script exits.
trap "kill $SUDO_PID 2>/dev/null" EXIT

# --- Package Installation ---
# Names here are logical: distro.sh turns each into whatever this distribution calls
# it, drops the ones it has no equivalent for, and installs only what is missing.
# On Kali most of this is already present and is left exactly as it is.
echo -e "\n${blueColour}[*]${endColour} Starting package installation on $(distro_id)..."

# apt cannot tell what is available until its lists are current.
pkg_refresh

PKG_GROUPS=(
    "base system utilities:base build-tools cmake coreutils util-linux linux-headers"
    "network manager:networkmanager"
    "graphical environment:xorg xorg-server xinit lightdm lightdm-gtk-greeter"
    "window manager:bspwm sxhkd polybar picom rofi wmname"
    "terminal and shell:kitty kitty-terminfo zsh zsh-syntax-highlighting zsh-autosuggestions"
    "essential applications:thunar firefox git nano wget unzip zip openvpn man-db man-pages"
    "filesystem and network:gvfs gvfs-mtp udisks2 dosfstools ntfs-3g exfatprogs xdg-utils xdg-user-dirs iproute2"
    "system utilities:xclip ranger scrot imagemagick cmatrix htop fastfetch python-pip procps fzf bat pamixer flameshot net-tools ping checkupdates feh lsd emoji-font pavucontrol libnotify stow"
)

UNAVAILABLE=()
PKG_FAILED=()
for group in "${PKG_GROUPS[@]}"; do
    echo -ne "\n[+] Installing ${group%%:*}...\n"
    # shellcheck disable=SC2086 - the list is ours and deliberately word-split
    pkg_install ${group#*:}
    (( ${#PKG_UNAVAILABLE[@]} )) && UNAVAILABLE+=("${PKG_UNAVAILABLE[@]}")
    (( ${#PKG_FAILED_LAST[@]} )) && PKG_FAILED+=("${PKG_FAILED_LAST[@]}")
done

# Install neovim (skip if already installed — never touch an existing install)
if pkg_installed neovim; then
    echo -e "  ${yellowColour}[✓] neovim already installed, skipping.${endColour}"
else
    echo -ne "\n[+] Installing neovim...\n"
    pkg_install neovim
fi

# LazyVim's requirements, installed with the editor rather than folded into the groups
# above: without them fzf-lua, blink.cmp and treesitter are all degraded and the reason is
# never obvious from inside nvim. The list lives in distro.sh so sync.sh installs the same
# set. git, a C compiler, fzf, the Nerd Font and kitty already come from the groups above.
echo -ne "\n[+] Installing LazyVim requirements...\n"
# shellcheck disable=SC2046 - the list is ours and deliberately word-split
pkg_install $(lazyvim_deps)
(( ${#PKG_UNAVAILABLE[@]} )) && UNAVAILABLE+=("${PKG_UNAVAILABLE[@]}")
(( ${#PKG_FAILED_LAST[@]} )) && PKG_FAILED+=("${PKG_FAILED_LAST[@]}")
ensure_fd_binary

# A fresh install can come up with the sink above 100%, which is unpleasant and easy
# to miss. Set once here; bspwmrc catches the case where no audio daemon was running
# yet at this point.
reset_volume() {
    command -v pamixer &>/dev/null || return 0
    pamixer --set-volume 100 --unmute &>/dev/null || return 0
    mkdir -p "$HOME/.cache" && touch "$HOME/.cache/pwnix-volume-set"
}

# Install audio backend (pipewire is the modern default, fallback to pulseaudio)
if pkg_installed pipewire; then
    echo -ne "\n[+] PipeWire detected, installing PipeWire audio components...\n"
    pkg_install pipewire-pulse pipewire-alsa wireplumber
else
    echo -ne "\n[+] Installing PulseAudio...\n"
    pkg_install pulseaudio pulseaudio-alsa
fi

# --- AUR helper and packages (Arch only) ---
# Debian ships i3lock-fancy in its own repositories and has no AUR to bootstrap, so
# this whole block is skipped there and the equivalents come from pkg_install below.
if is_arch; then
    if pkg_installed yay; then
        echo -e "  ${yellowColour}[✓] yay already installed, skipping.${endColour}"
    else
        echo -ne "\n[+] Installing yay (AUR helper)...\n"
        pkg_install build-tools golang
        git clone https://aur.archlinux.org/yay.git /tmp/yay
        cd /tmp/yay

        # The '-s' flag syncs dependencies using pacman. '-i' is avoided: it is not
        # recommended for automation and can trigger password prompts.
        makepkg -s --noconfirm --needed

        # The built package, excluding any debug one.
        pkg_file=$(find . -maxdepth 1 -name "yay-*.pkg.tar.zst" -not -name "yay-debug*")
        if [[ -f "$pkg_file" ]]; then
            echo "[+] Installing the 'yay' package..."
            sudo pacman -U --noconfirm "$pkg_file"
        else
            echo -e "${redColour}[!] Could not find the built 'yay' package. Skipping.${endColour}"
        fi

        cd "$dir"
        rm -rf /tmp/yay
    fi

    echo -ne "\n[+] Installing AUR packages...\n"
    for aur_pkg in python-pywal i3lock-fancy-git; do
        pkg_installed "$aur_pkg" && continue
        yay -S --noconfirm --sudoloop "$aur_pkg"
    done
else
    echo -ne "\n[+] Installing screen locker...\n"
    pkg_install i3lock-fancy

    # pywal is not packaged for Debian. pipx keeps it out of the system python,
    # which Kali is particular about, and it is only installed if truly absent.
    if ! command -v wal &>/dev/null; then
        echo -ne "\n[+] Installing pywal...\n"
        pkg_install pipx
        pipx install pywal16 2>/dev/null || pipx install pywal 2>/dev/null ||
            echo -e "${yellowColour}[!] pywal could not be installed. Colour theming will be unavailable.${endColour}"
    fi
fi

reset_volume

# --- System Configuration ---
echo -e "\n${blueColour}[*]${endColour} Starting system configuration..."

# Enable system services
echo -ne "\n[+] Enabling system services...\n"
sudo systemctl enable NetworkManager.service 2>/dev/null ||
    sudo systemctl enable network-manager.service 2>/dev/null

# A display manager is only enabled where none is running yet. Kali boots with its
# own and bspwm joins it as another session: switching it here is how a machine ends
# up with no way back to a desktop.
if systemctl list-units --type=service --state=running 2>/dev/null |
        grep -qE 'display-manager|gdm|sddm|lightdm'; then
    echo -e "  ${yellowColour}[✓] A display manager is already running, leaving it alone.${endColour}"
else
    sudo systemctl enable lightdm.service 2>/dev/null
fi

# Create standard user directories
echo -ne "\n[+] Creating standard user directories...\n"
xdg-user-dirs-update

# Configure /etc/hosts
echo -ne "\n[+] Configuring /etc/hosts file...\n"
if ! grep -q "127.0.1.1" /etc/hosts; then
    if ! grep -q "127.0.0.1" /etc/hosts; then
        echo "127.0.0.1     localhost" | sudo tee -a /etc/hosts > /dev/null
    fi
    if ! grep -q "::1" /etc/hosts; then
        echo "::1           localhost" | sudo tee -a /etc/hosts > /dev/null
    fi
    echo "127.0.1.1     ${HOSTNAME}.localdomain ${HOSTNAME}" | sudo tee -a /etc/hosts > /dev/null
    echo -e "  ${greenColour}[✓] /etc/hosts configured.${endColour}"
else
    echo -e "  ${yellowColour}[✓] /etc/hosts already configured.${endColour}"
fi

# ===========================================================================
# DOTFILES AND CUSTOM CONFIGURATION
# ===========================================================================
echo -e "\n${blueColour}[*]${endColour} Applying custom configurations...\n"

# Stow packages to deploy (each is a directory inside dotfiles/)
STOW_PACKAGES=(zsh bspwm sxhkd polybar picom kitty rofi files)

# --- 1. Static resources (copy — no need for live sync) ---
echo -e "${purpleColour}[*] Installing fonts...${endColour}"
mkdir -p "$fdir"
cp -r "$dir/assets/fonts/"* "$fdir" 2>/dev/null
fc-cache -f
echo -e "${greenColour}[+] Done.${endColour}\n"

echo -e "${purpleColour}[*] Installing wallpapers...${endColour}"
mkdir -p "$HOME/Wallpapers"
cp -r "$dir/assets/wallpapers/"* "$HOME/Wallpapers/" 2>/dev/null
# All of them are copied so you can switch by hand, but the configs reference a
# single wallpaper.png and this is what decides which distribution's it is.
if install_wallpaper "$dir/assets/wallpapers"; then
    echo -e "  ${greenColour}[✓] Using $(brand_wallpaper) as the wallpaper.${endColour}"
else
    echo -e "  ${yellowColour}[!] No wallpaper found for $(distro_variant).${endColour}"
fi
echo -e "${greenColour}[+] Done.${endColour}\n"

# --- 2. Install Oh My Zsh + Powerlevel10k (BEFORE stow, so stow overwrites the default .zshrc) ---
echo -e "${purpleColour}[*] Setting up Oh My Zsh...${endColour}"
rm -rf "$HOME/.oh-my-zsh"
sh -c "$(wget -O- https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

echo -e "${purpleColour}[*] Installing Powerlevel10k theme...${endColour}"
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k" 2>/dev/null
echo -e "${greenColour}[+] Done.${endColour}\n"

echo -e "${purpleColour}[*] Changing default shell to zsh...${endColour}"
sudo chsh -s /usr/bin/zsh "$USER"
sudo chsh -s /usr/bin/zsh root
echo -e "${greenColour}[+] Done.${endColour}\n"

# --- VM autostart migration (one-off) ---
# The guest-addition autostart used to be appended to bspwmrc, which stow links into
# the repo, so every dotfiles update discarded it. It now lives in ~/.config/bspwm.local,
# outside the stow tree, and bspwmrc sources it.
VM_AUTOSTART_RE='vmware-user-suid-wrapper|spice-vdagent|vm-display\.sh|xrandr --output Virtual-1'
migrate_vm_autostart() {
    local rc="$dir/dotfiles/bspwm/.config/bspwm/bspwmrc"
    local local_rc="$HOME/.config/bspwm.local"
    [[ -f "$rc" ]] || return 0
    grep -qE "$VM_AUTOSTART_RE" "$rc" 2>/dev/null || return 0

    mkdir -p "$HOME/.config"
    while IFS= read -r line; do
        grep -qxF "$line" "$local_rc" 2>/dev/null || echo "$line" >> "$local_rc"
    done < <(grep -E 'vmware-user-suid-wrapper|spice-vdagent|vm-display\.sh' "$rc")
    sed -i -E "/$VM_AUTOSTART_RE/d" "$rc"

    echo -e "${yellowColour}[!] VM autostart moved from bspwmrc to $local_rc${endColour}"
    echo -e "${yellowColour}    It now survives dotfiles updates.${endColour}\n"
}
migrate_vm_autostart

# --- 3. Deploy dotfiles with GNU Stow (after Oh My Zsh so our .zshrc replaces its template) ---
echo -e "${purpleColour}[*] Deploying dotfiles with stow...${endColour}"
mkdir -p "$HOME/.config"

# Remove existing dirs/files/symlinks that would conflict with stow
# This also removes the default .zshrc that Oh My Zsh just created
for pkg in "${STOW_PACKAGES[@]}"; do
    if [[ "$pkg" == "zsh" ]]; then
        [[ -e "$HOME/.zshrc" || -L "$HOME/.zshrc" ]] && rm -f "$HOME/.zshrc"
        [[ -e "$HOME/.p10k.zsh" || -L "$HOME/.p10k.zsh" ]] && rm -f "$HOME/.p10k.zsh"
    else
        [[ -e "$HOME/.config/$pkg" || -L "$HOME/.config/$pkg" ]] && rm -rf "$HOME/.config/$pkg"
    fi
done

# Stow all packages (target: $HOME, stow dir: dotfiles/)
# stow is what puts every config in place. Carrying on without it produces a machine
# that installs cleanly and then logs into an empty desktop, so it stops here instead.
if ! command -v stow &>/dev/null; then
    echo -e "${redColour}[!] GNU Stow is not installed and the dotfiles cannot be deployed.${endColour}"
    if is_debian; then
        echo -e "${redColour}    Install it and re-run: sudo apt install stow${endColour}"
    else
        echo -e "${redColour}    Install it and re-run: sudo pacman -S stow${endColour}"
    fi
    exit 1
fi

# One at a time, not all eight at once: stow is all-or-nothing, so a single package it
# dislikes used to abort the lot and leave nothing linked at all.
STOW_FAILED=()
for pkg in "${STOW_PACKAGES[@]}"; do
    stow -v -t "$HOME" -d "$dir/dotfiles" "$pkg" || STOW_FAILED+=("$pkg")
done

if (( ${#STOW_FAILED[@]} )); then
    echo -e "${redColour}[!] These packages could not be deployed: ${STOW_FAILED[*]}${endColour}"
else
    echo -e "${greenColour}[+] Done.${endColour}\n"
fi

# --- 3a. Verify the deployment ---
# Running stow and having the dotfiles in place are different claims. These four are
# what a working session needs: without bspwmrc there is no desktop at all.
MISSING_LINKS=()
for link in "$HOME/.config/bspwm/bspwmrc" "$HOME/.config/polybar/launch.sh" \
            "$HOME/.config/sxhkd/sxhkdrc" "$HOME/.zshrc"; do
    [[ -e "$link" ]] || MISSING_LINKS+=("$link")
done

if (( ${#MISSING_LINKS[@]} )); then
    echo -e "${redColour}[!] The dotfiles were not deployed. Missing:${endColour}"
    printf '      %s\n' "${MISSING_LINKS[@]}"
fi

# --- 3b. Install LazyVim (stock, no customization) — skip if already present ---
# LazyVim refuses to start below these two, and what it prints when it does is not a
# version error anybody recognises. Checked and reported rather than enforced: on Arch
# both are always new enough, and on an older Debian base the fix belongs to the
# distribution, not to this script.
VERSION_WARNINGS=()
NVIM_VERSION=$(nvim --version 2>/dev/null | head -n1 | sed 's/^NVIM v//; s/[-+].*//')
version_at_least "$NVIM_VERSION" 0.11.2 ||
    VERSION_WARNINGS+=("neovim ${NVIM_VERSION:-not found} is below the 0.11.2 LazyVim requires")
GIT_VERSION=$(git --version 2>/dev/null | awk '{print $3}')
version_at_least "$GIT_VERSION" 2.19.0 ||
    VERSION_WARNINGS+=("git ${GIT_VERSION:-not found} is below the 2.19.0 LazyVim requires")

NVIM_FAILED=false
if [[ -d "$HOME/.config/nvim" ]]; then
    echo -e "${yellowColour}[✓] LazyVim config already present at ~/.config/nvim, skipping.${endColour}\n"
else
    echo -e "${purpleColour}[*] Installing LazyVim...${endColour}"
    git clone --depth=1 https://github.com/LazyVim/starter "$HOME/.config/nvim"
    rm -rf "$HOME/.config/nvim/.git"

    # Twice, and that is not superstition. On a first sync mason is still installing
    # tree-sitter-cli when LazyVim's treesitter build asks mason for the same thing, and
    # the second request loses: "Package is already installing" aborts the config of
    # nvim-treesitter and the parsers never get built. By the second pass the cli is there
    # and there is nothing left to race.
    nvim --headless "+Lazy! sync" +qa
    if ! nvim --headless "+Lazy! sync" +qa; then
        NVIM_FAILED=true
        echo -e "${yellowColour}[!] LazyVim finished with errors. Run :Lazy sync inside nvim.${endColour}"
    fi
    echo -e "${greenColour}[+] Done.${endColour}\n"
fi

# --- 4. Ensure executable permissions (safety net — should be tracked in git) ---
echo -e "${purpleColour}[*] Setting executable permissions...${endColour}"
find "$dir/dotfiles" -name "*.sh" -exec chmod +x {} +
chmod +x "$dir/dotfiles/bspwm/.config/bspwm/bspwmrc" 2>/dev/null
chmod +x "$dir/dotfiles/bspwm/.config/bspwm/scripts/"* 2>/dev/null
chmod +x "$dir/dotfiles/sxhkd/.config/sxhkd/sxhkdrc" 2>/dev/null
echo -e "${greenColour}[+] Done.${endColour}\n"

# --- Machine-local override files ---
# Created empty so a config that hard-fails on a missing include cannot break, and so
# they are discoverable. picom is deliberately NOT created: its local file *replaces*
# the shipped config rather than extending it, so an empty one would leave the machine
# with no compositor settings at all.
ensure_local_overrides() {
    local f
    for f in "$HOME/.zshrc.local" "$HOME/.config/bspwm.local" "$HOME/.config/sxhkd.local"              "$HOME/.config/kitty.local.conf"; do
        [[ -e "$f" ]] && continue
        mkdir -p "$(dirname "$f")"
        printf '# Machine-local overrides. Loaded last, and survives dotfiles updates.
' > "$f"
    done
    [[ -e "$HOME/.config/polybar.local.ini" ]] ||
        printf ';; Machine-local overrides. Loaded last, and survives dotfiles updates.
'             > "$HOME/.config/polybar.local.ini"
    [[ -e "$HOME/.config/rofi.local.rasi" ]] ||
        printf '/* Machine-local overrides. Loaded last, and survives dotfiles updates. */
'             > "$HOME/.config/rofi.local.rasi"
}
ensure_local_overrides

# --- 5. Ensure target file exists for polybar ---
touch "$dir/dotfiles/files/.config/files/target"

# --- 6. Save repo path for future sync ---
echo "$dir" > "$HOME/.config/.pwnix-repo-path"

# --- 7. Create bspwm.desktop for LightDM ---
echo -e "${purpleColour}[*] Creating bspwm.desktop entry for LightDM...${endColour}"
sudo mkdir -p /usr/share/xsessions
cat <<EOF | sudo tee /usr/share/xsessions/bspwm.desktop > /dev/null
[Desktop Entry]
Name=bspwm
Comment=A lightweight tiling window manager
Exec=bspwm
TryExec=bspwm
Type=Application
DesktopNames=bspwm
EOF
echo -e "${greenColour}[+] Done.${endColour}\n"

# ===========================================================================
# ROOT USER ENVIRONMENT
# ===========================================================================
echo -e "${purpleColour}[*] Configuring root user environment...${endColour}"

# Shell configs — symlink directly to repo (same source as regular user)
sudo ln -sf "$dir/dotfiles/zsh/.zshrc" /root/.zshrc
sudo ln -sf "$dir/dotfiles/zsh/.p10k.zsh" /root/.p10k.zsh

# Shared target file
sudo mkdir -p /root/.config/files
sudo ln -sf "$HOME/.config/files/target" /root/.config/files/target

# Oh My Zsh (not in repo — installed from upstream)
sudo rm -rf /root/.oh-my-zsh
sudo cp -r "$HOME/.oh-my-zsh" /root/.oh-my-zsh
echo -e "${greenColour}[+] Done.${endColour}\n"

# ===========================================================================
# FINAL STEPS
# ===========================================================================

# Security tooling. On Arch that means adding BlackArch; on Kali the tools are the
# distribution and there is nothing to add.
if is_arch; then
    echo -e "${purpleColour}[*] Installing BlackArch repository...${endColour}"
    curl -O https://blackarch.org/strap.sh
    sudo sh strap.sh

    echo -e "${purpleColour}[*] Cleaning up temporary files...${endColour}"
    sudo pacman -Syu --noconfirm archlinux-keyring
    rm -f strap.sh
else
    echo -e "${purpleColour}[*] Security tools already ship with Kali, nothing to add.${endColour}"
    echo -e "${blueColour}[i] For more, see the kali-tools-* metapackages.${endColour}"
fi

# Repo path notice
echo -e "\n${yellowColour}[!] All configs are symlinked from: $dir/dotfiles${endColour}"
echo -e "${yellowColour}    Do not delete or move this directory.${endColour}\n"

# --- Virtual Machine Guest Additions (Optional) ---
echo -e "\n${blueColour}[*]${endColour} Virtual Machine Guest Additions (Optional)\n"
echo -e "    If you are running inside a VM, install guest additions for clipboard"
echo -e "    sharing, drag & drop, auto screen resizing, and shared folders.\n"
echo -e "    1) VMware"
echo -e "    2) QEMU / KVM (SPICE)"
echo -e "    3) Skip (no VM or already installed)\n"

while true; do
    echo -en "${yellowColour}[?] Select your hypervisor (1/2/[3]): ${endColour}"
    read -r vm_choice
    vm_choice=${vm_choice:-3}
    case "$vm_choice" in
        1)
            echo -e "\n${purpleColour}[*] Installing VMware Guest Additions...${endColour}"
            pkg_install vmware-tools
            # shellcheck disable=SC2046 - the unit list is ours and deliberately split
            service_enable $(vm_units vmware)
            # Add autostart to bspwm.local if not already present
            if ! grep -q "vmware-user-suid-wrapper" "$HOME/.config/bspwm.local" 2>/dev/null; then
                echo 'pgrep -x vmware-user-suid-wrapper > /dev/null || vmware-user-suid-wrapper &' >> "$HOME/.config/bspwm.local"
            fi
            echo -e "${greenColour}[+] VMware Guest Additions installed.${endColour}\n"
            break
            ;;
        2)
            echo -e "\n${purpleColour}[*] Installing QEMU/KVM Guest Additions...${endColour}"
            pkg_install spice-vdagent qemu-guest-agent xev
            # shellcheck disable=SC2046 - the unit list is ours and deliberately split
            service_enable $(vm_units spice)
            # Add spice-vdagent autostart to bspwm.local if not already present
            if ! grep -q "spice-vdagent" "$HOME/.config/bspwm.local" 2>/dev/null; then
                echo 'spice-vdagent &' >> "$HOME/.config/bspwm.local"
            fi
            # Drop the legacy one-shot xrandr line (it raced spice-vdagent and
            # needed a manual Super+Alt+R to fit the screen); replaced by the
            # event-driven vm-display.sh helper below.
            sed -i '/xrandr --output Virtual-1 --auto/d' "$HOME/.config/bspwm.local" 2>/dev/null
            # Auto-fit the virtual display on resolution changes (no sleeps)
            if ! grep -q "vm-display.sh" "$HOME/.config/bspwm.local" 2>/dev/null; then
                echo '~/.config/bspwm/scripts/vm-display.sh &' >> "$HOME/.config/bspwm.local"
            fi
            echo -e "${greenColour}[+] QEMU/KVM Guest Additions installed.${endColour}\n"
            break
            ;;
        3)
            echo -e "\n${yellowColour}[*] Skipping VM Guest Additions.${endColour}\n"
            break
            ;;
        *)
            echo -e "\n${redColour}[!] Invalid option. Please enter 1, 2, or 3.${endColour}\n"
            ;;
    esac
done

# A name this distribution does not have is worth knowing about, but it is never a
# reason to have aborted the install.
if (( ${#UNAVAILABLE[@]} )); then
    echo -e "\n${yellowColour}[!] Not available on $(distro_id), skipped:${endColour}"
    printf '      %s\n' "${UNAVAILABLE[@]}"
fi

# Saying "complete" after failing to deploy anything is how a broken install reaches
# the login screen unnoticed. The ending reports what happened.
if (( ${#MISSING_LINKS[@]} || ${#STOW_FAILED[@]} || ${#PKG_FAILED[@]} )); then
    echo -e "\n${redColour}[!] INSTALLATION INCOMPLETE${endColour}"
    (( ${#PKG_FAILED[@]} )) &&
        echo -e "${redColour}    Packages that failed to install: ${PKG_FAILED[*]}${endColour}"
    (( ${#STOW_FAILED[@]} )) &&
        echo -e "${redColour}    Packages that failed to deploy: ${STOW_FAILED[*]}${endColour}"
    (( ${#MISSING_LINKS[@]} )) &&
        echo -e "${redColour}    Configs missing from your home directory.${endColour}"
    echo -e "${yellowColour}    Fix what is reported above, then re-run: bash $dir/sync.sh${endColour}\n"
else
    echo -e "\n${greenColour}[+] DONE!${endColour}"
    echo -e "${greenColour}[✓] Installation complete!${endColour}\n"
fi

# Editor plugins are recoverable from inside nvim, so this is a note rather than a failed
# install — but buried in the log it is a note nobody ever reads.
$NVIM_FAILED &&
    echo -e "${yellowColour}[!] LazyVim did not finish cleanly. Open nvim and run :Lazy sync${endColour}\n"

# Same for a version LazyVim cannot work with: nothing here can fix it, and finding out
# from a broken editor a week later is worse than reading it now.
if (( ${#VERSION_WARNINGS[@]} )); then
    for warning in "${VERSION_WARNINGS[@]}"; do
        echo -e "${yellowColour}[!] $warning${endColour}"
    done
    echo -e "${yellowColour}    Upgrade it through your distribution before using nvim.${endColour}\n"
fi

echo -e "${blueColour}[i] The full installation process has been logged to: $LOG_FILE${endColour}"
echo -e "${blueColour}    You can review it anytime and delete it when no longer needed.${endColour}\n"

# --- System Reboot ---
# Ask for system reboot.
while true; do
    echo -en "${yellowColour}[?] A system restart is required. Would you like to restart now? ([y]/n) ${endColour}"
    read -r response
    response=${response:-"y"}
    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo -e "\n${greenColour}[+] Rebooting the system...${endColour}\n"
        sleep 1
        sudo reboot
        break
    elif [[ "$response" =~ ^[Nn]$ ]]; then
        echo -e "\n${turquoiseColour}After reboot, you can install pentesting tools manually.${endColour}"
        echo -e "${turquoiseColour}Check the README.md for installation instructions.${endColour}\n"
        exit 0
    else
        echo -e "\n${redColour}[!] Invalid response. Please enter 'y' or 'n'.${endColour}\n"
    fi
done
