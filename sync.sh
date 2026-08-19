#!/bin/bash
#### sync.sh
# Re-deploys dotfiles symlinks using GNU Stow without running a full install.
# Use after cloning the repo, adding new packages, or to repair broken links.
#
# Usage:
#   bash sync.sh           # re-stow all packages (+ git pull, + VM prompt)
#   bash sync.sh polybar   # re-stow only polybar
#
# Env:
#   PWNIX_SYNC_QUICK=1   # re-stow all packages but skip the git pull and the
#                          # VM Guest Additions prompt (used by update-system.sh,
#                          # which already handles git itself)

# --- Colors ---
greenColour="\e[0;32m\033[1m"
endColour="\033[0m\e[0m"
redColour="\e[0;31m\033[1m"
blueColour="\e[0;34m\033[1m"
yellowColour="\e[0;33m\033[1m"
purpleColour="\e[0;35m\033[1m"

# --- Global variables ---
dir="$(cd "$(dirname "$0")" && pwd)"

# Package names and managers differ between Arch and Debian/Kali; distro.sh is the
# only place that knows how.
DISTRO_LIB="$dir/dotfiles/polybar/.config/polybar/theme/scripts/lib/distro.sh"
# shellcheck source=dotfiles/polybar/.config/polybar/theme/scripts/lib/distro.sh
[[ -r "$DISTRO_LIB" ]] && . "$DISTRO_LIB"

# All available stow packages
ALL_PACKAGES=(zsh bspwm sxhkd polybar picom kitty rofi files)

# Use args if provided, otherwise deploy all
if [[ $# -gt 0 ]]; then
    PACKAGES=("$@")
else
    PACKAGES=("${ALL_PACKAGES[@]}")
fi

# --- Validate ---
if ! command -v stow &>/dev/null; then
    if declare -F is_debian >/dev/null && is_debian; then
        echo -e "${redColour}[!] GNU Stow is not installed. Run: sudo apt install stow${endColour}"
    else
        echo -e "${redColour}[!] GNU Stow is not installed. Run: sudo pacman -S stow${endColour}"
    fi
    exit 1
fi

if [[ ! -d "$dir/dotfiles" ]]; then
    echo -e "${redColour}[!] dotfiles/ directory not found in: $dir${endColour}"
    exit 1
fi

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

# --- Git pull (full sync only) ---
if [[ $# -eq 0 && -z "$PWNIX_SYNC_QUICK" ]] && git -C "$dir" rev-parse --is-inside-work-tree &>/dev/null; then
    echo -e "${blueColour}[*]${endColour} Checking for remote updates..."

    if ! git -C "$dir" fetch origin 2>&1; then
        echo -e "${yellowColour}[!] Could not reach remote. Continuing with local files.${endColour}\n"
    else
        BRANCH=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
        LOCAL=$(git -C "$dir" rev-parse HEAD 2>/dev/null)
        REMOTE=$(git -C "$dir" rev-parse "origin/$BRANCH" 2>/dev/null)
        BASE=$(git -C "$dir" merge-base HEAD "origin/$BRANCH" 2>/dev/null)

        if [[ -z "$REMOTE" ]]; then
            echo -e "${yellowColour}[!] No remote tracking branch found. Skipping pull.${endColour}\n"
        elif [[ "$LOCAL" == "$REMOTE" ]]; then
            echo -e "${greenColour}[✓] Already up to date.${endColour}\n"
        elif [[ "$LOCAL" == "$BASE" ]]; then
            echo -e "${purpleColour}[*] Pulling updates (fast-forward)...${endColour}"
            if git -C "$dir" pull --ff-only 2>&1; then
                echo -e "${greenColour}[✓] Updated successfully.${endColour}\n"
            else
                echo -e "${redColour}[!] Fast-forward failed. Falling back to diverged resolution.${endColour}\n"
                LOCAL="diverged"
            fi
        fi

        if [[ "$LOCAL" != "$REMOTE" && "$LOCAL" != "$BASE" ]] || [[ "$LOCAL" == "diverged" ]]; then
            echo -e "${yellowColour}[!] Local and remote have diverged.${endColour}"
            echo -e "    Local:  $(git -C "$dir" log --oneline -1 HEAD 2>/dev/null)"
            echo -e "    Remote: $(git -C "$dir" log --oneline -1 "origin/$BRANCH" 2>/dev/null)\n"
            echo -e "    1) Merge  — integrate remote changes, keep local modifications"
            echo -e "    2) Reset  — discard local changes, match remote exactly"
            echo -e "    3) Skip   — continue without pulling\n"

            while true; do
                echo -en "${yellowColour}[?] Choose ([1]/2/3): ${endColour}"
                read -r git_choice
                git_choice=${git_choice:-1}
                case "$git_choice" in
                    1)
                        STASHED=false
                        if ! git -C "$dir" diff --quiet 2>/dev/null || ! git -C "$dir" diff --cached --quiet 2>/dev/null; then
                            echo -e "${purpleColour}[*] Stashing uncommitted changes...${endColour}"
                            git -C "$dir" stash push -m "sync.sh auto-stash" && STASHED=true
                        fi
                        echo -e "${purpleColour}[*] Merging remote changes...${endColour}"
                        if git -C "$dir" merge "origin/$BRANCH" 2>&1; then
                            $STASHED && git -C "$dir" stash pop
                            echo -e "${greenColour}[✓] Merge completed successfully.${endColour}\n"
                        else
                            echo -e "${redColour}[!] Merge conflicts in:${endColour}"
                            git -C "$dir" diff --name-only --diff-filter=U
                            echo -e "\n${yellowColour}[!] Resolve the conflicts, then run sync.sh again.${endColour}"
                            echo -e "    To reset instead: git -C $dir reset --hard origin/$BRANCH\n"
                            exit 1
                        fi
                        break
                        ;;
                    2)
                        echo -e "${purpleColour}[*] Resetting to remote state...${endColour}"
                        git -C "$dir" reset --hard "origin/$BRANCH" 2>&1
                        echo -e "${greenColour}[✓] Reset to remote state.${endColour}\n"
                        break
                        ;;
                    3)
                        echo -e "${yellowColour}[*] Skipping git pull.${endColour}\n"
                        break
                        ;;
                    *)
                        echo -e "${redColour}[!] Invalid option. Enter 1, 2 or 3.${endColour}\n"
                        ;;
                esac
            done
        fi
    fi
fi

# --- Clean conflicts ---
echo -e "${purpleColour}[*] Checking for conflicts...${endColour}"
for pkg in "${PACKAGES[@]}"; do
    if [[ "$pkg" == "zsh" ]]; then
        [[ -e "$HOME/.zshrc" || -L "$HOME/.zshrc" ]] && rm -f "$HOME/.zshrc"
        [[ -e "$HOME/.p10k.zsh" || -L "$HOME/.p10k.zsh" ]] && rm -f "$HOME/.p10k.zsh"
    else
        [[ -e "$HOME/.config/$pkg" || -L "$HOME/.config/$pkg" ]] && rm -rf "$HOME/.config/$pkg"
    fi
done

# --- Deploy ---
echo -e "${purpleColour}[*] Deploying with stow: ${PACKAGES[*]}${endColour}"
mkdir -p "$HOME/.config"
stow -v -R -t "$HOME" -d "$dir/dotfiles" "${PACKAGES[@]}"

# --- Neovim + LazyVim (install only if missing — never touch an existing install) ---
if pkg_installed neovim; then
    echo -e "${yellowColour}[✓] neovim already installed, skipping.${endColour}"
else
    echo -e "${purpleColour}[*] Installing neovim...${endColour}"
    pkg_install neovim
fi

if [[ -d "$HOME/.config/nvim" ]]; then
    echo -e "${yellowColour}[✓] LazyVim config already present at ~/.config/nvim, skipping.${endColour}"
else
    echo -e "${purpleColour}[*] Installing LazyVim...${endColour}"
    git clone --depth=1 https://github.com/LazyVim/starter "$HOME/.config/nvim"
    rm -rf "$HOME/.config/nvim/.git"
    nvim --headless "+Lazy! sync" +qa
    echo -e "${greenColour}[+] Done.${endColour}"
fi

# --- Permissions (safety net) ---
echo -e "${purpleColour}[*] Setting executable permissions...${endColour}"
find "$dir/dotfiles" -name "*.sh" -exec chmod +x {} +
chmod +x "$dir/dotfiles/bspwm/.config/bspwm/bspwmrc" 2>/dev/null
chmod +x "$dir/dotfiles/bspwm/.config/bspwm/scripts/"* 2>/dev/null
chmod +x "$dir/dotfiles/sxhkd/.config/sxhkd/sxhkdrc" 2>/dev/null

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

# --- Breadcrumb ---
touch "$dir/dotfiles/files/.config/files/target"
echo "$dir" > "$HOME/.config/.pwnix-repo-path"

echo -e "\n${greenColour}[+] Configs synced from: $dir/dotfiles${endColour}\n"

# --- Virtual Machine Guest Additions (Optional) ---
# Only prompted on full sync (no specific package argument), and never in quick mode
if [[ $# -eq 0 && -z "$PWNIX_SYNC_QUICK" ]]; then
    echo -e "${blueColour}[*]${endColour} Virtual Machine Guest Additions (Optional)\n"
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
                sudo systemctl enable vmtoolsd.service
                sudo systemctl enable vmware-vmblock-fuse.service
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
                sudo systemctl enable spice-vdagentd.service
                sudo systemctl enable qemu-guest-agent.service
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
fi
