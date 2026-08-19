#!/usr/bin/env bash
# Full system update — the `apt update && apt full-upgrade` of this environment.
#
# Two sources, and deliberately only two: whatever the package manager owns (pacman with
# BlackArch and the AUR, or apt) and the pwnix dotfiles themselves, together with the
# static resources that come with them (fonts, wallpapers, xsession entry).
#
# Anything installed by hand — oh-my-zsh, tools cloned under ~/Tools, python venvs,
# LazyVim plugins, flatpak, pipx, rustup, cargo — is left alone on purpose. The README
# lists the command for each. Guessing at somebody's hand-built tooling is how an
# updater breaks the thing it was meant to maintain.
#
# One rule throughout: it updates what is already there and never installs what is not.
# install.sh remains the only installer.
#
# Usage:
#   update-system.sh                  run here, in the current terminal
#   update-system.sh --own-terminal   the caller opened a window just for this (polybar)

set -o pipefail

OWN_TERMINAL=false
[[ "$1" == "--own-terminal" ]] && OWN_TERMINAL=true

UPDATED=()
UPDATED_DETAILS=()
ERRORS=()
MANUAL_CMDS=()
REMOVED=()

PWNIX_DIR=""
[[ -f "$HOME/.config/.pwnix-repo-path" ]] && PWNIX_DIR="$(cat "$HOME/.config/.pwnix-repo-path" 2>/dev/null)"

# Where updates can come from. Shared with updates.sh so the number in the polybar and
# what this script actually does can never drift apart. Resolved from this script's own
# location, which works whether polybar or `sysup` launched it.
SOURCES_LIB="$(dirname "$(readlink -f "$0")")/lib/update-sources.sh"
if [[ -r "$SOURCES_LIB" ]]; then
    # shellcheck source=lib/update-sources.sh
    . "$SOURCES_LIB"
else
    echo "[!] Missing $SOURCES_LIB - run sync.sh. Continuing with packages only."
fi

# ──────────────────────────────────────────────────────────
#  Helpers
# ──────────────────────────────────────────────────────────

# Arch convention: a bare Enter means yes. A spelled-out "yes" means yes too, rather
# than quietly counting as no.
confirm() {
    local reply
    printf ":: %s [Y/n] " "$1"
    read -r reply
    [[ "${reply:-y}" =~ ^([Yy]|[Yy][Ee][Ss])$ ]]
}

record_ok() {
    UPDATED+=("$1")
    [[ -n "$2" ]] && UPDATED_DETAILS+=("      $2")
    return 0
}

record_fail() {
    ERRORS+=("$1")
    MANUAL_CMDS+=("$2")
    return 0
}

echo "══════════════════════════════════════════════════════"
printf "          FULL SYSTEM UPDATE - %s\n" "$(brand_name)"
echo "══════════════════════════════════════════════════════"
echo ""

# ──────────────────────────────────────────────────────────
#  0. Sudo, asked once
# ──────────────────────────────────────────────────────────
# Long AUR builds outlive the default 5 minute timestamp, and without this the run stops
# halfway through to ask again. Same pattern install.sh uses.

echo "[*] Requesting sudo access (asked once, kept alive for the whole run)..."
if ! sudo -v; then
    echo "[!] sudo denied. Aborting."
    exit 1
fi
( while true; do sudo -n true; sleep 50; done ) &
SUDO_KEEPALIVE=$!
trap 'kill "$SUDO_KEEPALIVE" 2>/dev/null' EXIT

# ──────────────────────────────────────────────────────────
#  1. System packages
# ──────────────────────────────────────────────────────────

# Keyrings first, or signature checks fail on everything after. A no-op off Arch,
# where package signing needs no such step.
if is_arch; then
    echo ""
    echo "[*] Updating keyrings..."
    if pkg_update_keyring; then
        record_ok "keyrings" ""
    else
        record_fail "keyring update" "sudo pacman -Sy --needed archlinux-keyring"
    fi
fi

echo ""
echo "[*] Updating system packages..."
# apt cannot upgrade against stale lists, and refreshing them is folded into the
# upgrade on Arch. Either way this is the step that decides what follows.
pkg_refresh
PKG_LOG=$(mktemp)
pkg_update_all 2>&1 | tee "$PKG_LOG"
# PIPESTATUS, not $?: the status wanted is the package manager's, not tee's.
if (( PIPESTATUS[0] == 0 )); then
    if is_arch; then
        UPGRADED=$(grep -oP '(?<=upgrading )\S+' "$PKG_LOG" | sed 's/\.\.\.$//' | paste -sd ', ')
    else
        UPGRADED=$(grep -oP '(?<=^Unpacking )\S+' "$PKG_LOG" | paste -sd ', ')
    fi
    if [[ -n "$UPGRADED" ]]; then
        record_ok "system packages" "packages: $UPGRADED"
    else
        record_ok "system packages (already up to date)" ""
    fi
else
    if is_arch; then
        record_fail "system packages" "sudo pacman -Syu"
    else
        record_fail "system packages" "sudo apt update \&\& sudo apt full-upgrade"
    fi
fi
rm -f "$PKG_LOG"

# Whether a restart is now pending. Arch has to be asked by comparing kernels;
# Debian leaves a marker file behind, which also catches the non-kernel cases.
KERNEL_UPDATED=false
reboot_required && KERNEL_UPDATED=true
REBOOT_REASON=$(reboot_reason)

if command -v yay &>/dev/null; then
    echo ""
    echo "[*] Updating AUR packages..."
    AUR_LOG=$(mktemp)
    yay -Sua --noconfirm --sudoloop 2>&1 | tee "$AUR_LOG"
    if (( PIPESTATUS[0] == 0 )); then
        AUR_PKGS=$(grep -oP '(?<=upgrading )\S+' "$AUR_LOG" | sed 's/\.\.\.$//' | paste -sd ', ')
        if [[ -n "$AUR_PKGS" ]]; then
            record_ok "AUR packages (yay)" "aur: $AUR_PKGS"
        else
            record_ok "AUR packages (already up to date)" ""
        fi
    else
        record_fail "AUR packages (yay)" "yay -Sua"
    fi
    rm -f "$AUR_LOG"
fi

# ──────────────────────────────────────────────────────────
#  2. PWNIX dotfiles
# ──────────────────────────────────────────────────────────

# Bring the working tree to the remote state. Three paths, because "discard everything"
# is only correct in one of them:
#   clean          -> pull --ff-only, which refuses rather than dropping local commits
#   dirty, keeping -> stash, pull, reapply; a conflict leaves the stash intact
#   dirty, discard -> reset --hard, exact and unable to conflict
# Sets PWNIX_APPLIED on success.
pwnix_apply_update() {
    local keep="$1"

    if $keep; then
        if ! git -C "$PWNIX_DIR" stash push --quiet -m "pwnix update auto-stash"; then
            record_fail "pwnix dotfiles stash" "git -C $PWNIX_DIR stash push"
            return 1
        fi
        if ! git -C "$PWNIX_DIR" pull --ff-only --quiet origin "$PWNIX_BRANCH"; then
            git -C "$PWNIX_DIR" stash pop --quiet
            record_fail "pwnix dotfiles pull" "git -C $PWNIX_DIR pull --ff-only"
            return 1
        fi
        if git -C "$PWNIX_DIR" stash pop --quiet; then
            PWNIX_APPLIED=true
            return 0
        fi
        # The stash is still on the stack, so nothing of yours is gone.
        echo "    [!] Your changes conflict with the update. They are safe in the stash:"
        git -C "$PWNIX_DIR" diff --name-only --diff-filter=U 2>/dev/null | sed 's/^/        /'
        record_fail "pwnix dotfiles: local changes conflict with the update"             "cd $PWNIX_DIR && git status   # resolve, then: git stash drop"
        return 1
    fi

    if (( ${#PWNIX_DIRTY[@]} )); then
        if git -C "$PWNIX_DIR" reset --hard "origin/$PWNIX_BRANCH" 2>&1; then
            PWNIX_APPLIED=true
            return 0
        fi
        record_fail "pwnix dotfiles update" "git -C $PWNIX_DIR reset --hard origin/$PWNIX_BRANCH"
        return 1
    fi

    if git -C "$PWNIX_DIR" pull --ff-only --quiet origin "$PWNIX_BRANCH"; then
        PWNIX_APPLIED=true
        return 0
    fi
    record_fail "pwnix dotfiles pull (history has diverged)"         "git -C $PWNIX_DIR pull --ff-only origin $PWNIX_BRANCH"
    return 1
}

PWNIX_PULLED=false
PWNIX_APPLIED=false
PWNIX_DIRTY=()
if command -v git &>/dev/null && [[ -n "$PWNIX_DIR" && -d "$PWNIX_DIR/.git" ]]; then
    echo ""
    echo "[*] Checking PWNIX dotfiles..."
    timeout 60 env GIT_TERMINAL_PROMPT=0 git -C "$PWNIX_DIR" fetch --quiet origin 2>&1
    PWNIX_BRANCH=$(git -C "$PWNIX_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null)
    LOCAL=$(git -C "$PWNIX_DIR" rev-parse HEAD 2>/dev/null)
    REMOTE=$(git -C "$PWNIX_DIR" rev-parse "origin/$PWNIX_BRANCH" 2>/dev/null)

    if [[ -n "$REMOTE" && "$LOCAL" != "$REMOTE" ]]; then
        BEHIND=$(git -C "$PWNIX_DIR" rev-list --count "$LOCAL".."$REMOTE" 2>/dev/null)
        echo ""
        echo "    $BEHIND new commit(s) available:"
        git -C "$PWNIX_DIR" log --oneline "$LOCAL".."$REMOTE" 2>/dev/null | sed 's/^/      /'
        echo ""

        if confirm "Update PWNIX dotfiles now?"; then
            # stow links the configs into this repo, so editing ~/.zshrc or a polybar
            # colour *is* a modification here. HEAD covers staged and unstaged alike.
            mapfile -t PWNIX_DIRTY < <(git -C "$PWNIX_DIR" diff --name-only HEAD 2>/dev/null)

            KEEP_LOCAL=false
            if (( ${#PWNIX_DIRTY[@]} )); then
                echo ""
                echo "    You have local changes in $PWNIX_DIR:"
                printf '      %s
' "${PWNIX_DIRTY[@]}"
                echo ""
                echo "    Keeping them replays your edits on top of the new commits."
                echo "    Answering no discards them. Machine-only tweaks belong in the"
                echo "    .local files instead, which no update ever touches — see the README."
                echo ""
                confirm "Keep your local changes?" && KEEP_LOCAL=true
            fi

            if pwnix_apply_update "$KEEP_LOCAL"; then
                echo "    [*] Re-deploying dotfiles (sync.sh)..."
                if PWNIX_SYNC_QUICK=1 bash "$PWNIX_DIR/sync.sh" 2>&1; then
                    PWNIX_PULLED=true
                    if $KEEP_LOCAL; then
                        record_ok "pwnix dotfiles" "pwnix: ${BEHIND} new commit(s) + re-stow, local changes kept"
                    else
                        record_ok "pwnix dotfiles" "pwnix: ${BEHIND} new commit(s) + re-stow"
                    fi
                else
                    record_fail "pwnix dotfiles re-stow" "bash $PWNIX_DIR/sync.sh"
                fi
            fi
        else
            echo "    skipped"
        fi
    else
        echo "    already up to date"
        record_ok "pwnix dotfiles (already up to date)" ""
    fi
fi

# ──────────────────────────────────────────────────────────
#  3. Static resources
# ──────────────────────────────────────────────────────────
# Fonts and wallpapers are the only things install.sh copies instead of symlinking, so
# without this a new wallpaper in the repo never reaches the machine. Runs after the
# dotfiles block so it copies the files that were just pulled.

# Returns 0 only when something actually moved, so fc-cache is not run for nothing.
copy_if_newer() {
    local src="$1" dst="$2" stamp="$3"
    [[ -d "$src" ]] || return 1
    if [[ -f "$stamp" ]] && [[ -z "$(find "$src" -newer "$stamp" -type f -print -quit 2>/dev/null)" ]]; then
        return 1
    fi
    mkdir -p "$dst" "$(dirname "$stamp")" || return 1
    cp -r "$src/." "$dst/" 2>/dev/null || return 1
    touch "$stamp"
}

if [[ -n "$PWNIX_DIR" && -d "$PWNIX_DIR" ]]; then
    echo ""
    echo "[*] Refreshing static resources..."

    if copy_if_newer "$PWNIX_DIR/assets/fonts" "$HOME/.local/share/fonts" "$HOME/.cache/pwnix-fonts.stamp"; then
        fc-cache -f >/dev/null 2>&1
        record_ok "fonts" ""
    fi

    if copy_if_newer "$PWNIX_DIR/assets/wallpapers" "$HOME/Wallpapers" "$HOME/.cache/pwnix-wallpapers.stamp"; then
        # The configs point at a single wallpaper.png; refresh it from this
        # distribution's own file rather than leaving the previous one in place.
        install_wallpaper "$PWNIX_DIR/assets/wallpapers"
        record_ok "wallpapers" ""
    fi

    # The xsession entry is written by install.sh and lives outside the stow tree, so a
    # change to it would otherwise only ever land on a fresh install.
    XSESSION_TMP=$(mktemp)
    cat > "$XSESSION_TMP" <<'DESKTOPEOF'
[Desktop Entry]
Name=bspwm
Comment=A lightweight tiling window manager
Exec=bspwm
TryExec=bspwm
Type=Application
DesktopNames=bspwm
DESKTOPEOF
    if ! cmp -s "$XSESSION_TMP" /usr/share/xsessions/bspwm.desktop 2>/dev/null; then
        sudo mkdir -p /usr/share/xsessions
        if sudo cp "$XSESSION_TMP" /usr/share/xsessions/bspwm.desktop; then
            record_ok "bspwm.desktop" ""
        else
            record_fail "bspwm.desktop" "sudo cp $XSESSION_TMP /usr/share/xsessions/bspwm.desktop"
        fi
    fi
    rm -f "$XSESSION_TMP"
fi

# ──────────────────────────────────────────────────────────
#  4. Root shell environment
# ──────────────────────────────────────────────────────────
# /root/.zshrc and /root/.p10k.zsh are symlinks into the repo and follow it on their own.
# oh-my-zsh is a copy, and since this script no longer updates it there is nothing to
# propagate: it is only put in place when root does not have it at all.

if [[ -d "$HOME/.oh-my-zsh" && ! -d /root/.oh-my-zsh ]]; then
    echo ""
    echo "[*] Syncing shell environment to root..."
    if sudo rm -rf /root/.oh-my-zsh && sudo cp -r "$HOME/.oh-my-zsh" /root/.oh-my-zsh; then
        record_ok "root shell sync" ""
    else
        record_fail "root shell sync" "sudo cp -r ~/.oh-my-zsh /root/.oh-my-zsh"
    fi
fi

# ──────────────────────────────────────────────────────────
#  5. Mirrorlist
# ──────────────────────────────────────────────────────────
# reflector only, and only when the list is over a week old. rankmirrors against a live
# mirrorlist is how a machine ends up unable to reach any repository at all, and
# reflector is not something install.sh puts here, so its absence is not an error.

if is_arch && command -v reflector &>/dev/null &&
    [[ -n "$(find /etc/pacman.d/mirrorlist -mtime +7 -print -quit 2>/dev/null)" ]]; then
    echo ""
    echo "[*] Refreshing pacman mirrorlist..."
    sudo cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak
    if sudo reflector --latest 20 --sort rate --protocol https --save /etc/pacman.d/mirrorlist; then
        record_ok "pacman mirrorlist" ""
    else
        sudo cp /etc/pacman.d/mirrorlist.bak /etc/pacman.d/mirrorlist
        record_fail "pacman mirrorlist (restored from backup)" \
            "sudo reflector --latest 20 --sort rate --save /etc/pacman.d/mirrorlist"
    fi
fi

# ──────────────────────────────────────────────────────────
#  6. Cleanup
# ──────────────────────────────────────────────────────────

mapfile -t ORPHANS < <(pkg_orphans 2>/dev/null)
if (( ${#ORPHANS[@]} )); then
    echo ""
    echo "[*] Orphaned packages (installed as dependencies, now unused):"
    printf '      %s\n' "${ORPHANS[@]}"
    echo ""
    if confirm "Remove them?"; then
        if pkg_remove_orphans "${ORPHANS[@]}"; then
            REMOVED+=("${ORPHANS[@]}")
        else
            record_fail "orphan removal" "remove the packages listed above by hand"
        fi
    else
        echo "    kept"
    fi
fi

echo ""
echo "[*] Cleaning package cache..."
if pkg_clean_cache; then
    record_ok "package cache cleaned" ""
else
    record_fail "package cache clean" "clean the package cache by hand"
fi

# Refresh the polybar counter now rather than up to 30 minutes from now.
pkill -SIGUSR1 -f "updates.sh" 2>/dev/null

# ──────────────────────────────────────────────────────────
#  Summary
# ──────────────────────────────────────────────────────────

echo ""
echo "══════════════════════════════════════════════════════"
if $KERNEL_UPDATED; then
    echo "       UPDATE COMPLETED — REBOOT REQUIRED             "
elif (( ${#ERRORS[@]} == 0 )); then
    echo "          UPDATE COMPLETED SUCCESSFULLY               "
else
    echo "          UPDATE COMPLETED WITH ERRORS                "
fi
echo "══════════════════════════════════════════════════════"
echo ""

if $KERNEL_UPDATED; then
    echo "  [!!] REBOOT REQUIRED"
    echo "       $REBOOT_REASON"
    echo ""
fi

if (( ${#UPDATED[@]} )); then
    echo "  [✓] Updated:"
    printf '      - %s\n' "${UPDATED[@]}"
    if (( ${#UPDATED_DETAILS[@]} )); then
        echo ""
        echo "  [i] Details:"
        printf '%s\n' "${UPDATED_DETAILS[@]}"
    fi
fi

if (( ${#REMOVED[@]} )); then
    echo ""
    echo "  [−] Removed orphans:"
    printf '      - %s\n' "${REMOVED[@]}"
fi

if (( ${#ERRORS[@]} )); then
    echo ""
    echo "  [✗] Errors:"
    printf '      - %s\n' "${ERRORS[@]}"
    echo ""
    echo "  [!] Fix manually:"
    printf '      $ %s\n' "${MANUAL_CMDS[@]}"
fi

if (( ${#UPDATED[@]} == 0 && ${#REMOVED[@]} == 0 && ${#ERRORS[@]} == 0 )); then
    echo "  [i] Nothing to do."
fi

echo ""
echo "══════════════════════════════════════════════════════"
echo ""

if $PWNIX_PULLED; then
    echo "  [i] Dotfiles changed. Restart bspwm (Super+Alt+R) to pick them all up."
    echo ""
fi

# ──────────────────────────────────────────────────────────
#  Reboot / terminal
# ──────────────────────────────────────────────────────────

if $KERNEL_UPDATED; then
    notify-send -u critical -t 0 \
        "Reboot Required" "$REBOOT_REASON" 2>/dev/null
    if confirm "Reboot now?"; then
        echo ""
        echo "  Rebooting..."
        sleep 1
        sudo reboot
        exit 0
    fi
    echo ""
    echo "  !! Remember: the pending changes are not active until you reboot."
    echo ""
fi

# Closing only means anything when the caller opened a window for this alone.
# exec replaces this process and the EXIT trap never runs, so the sudo keepalive has to
# be stopped by hand here — otherwise it sits there refreshing the timestamp for good.
if $OWN_TERMINAL && ! confirm "Close terminal?"; then
    kill "$SUDO_KEEPALIVE" 2>/dev/null
    exec "${SHELL:-/bin/bash}"
fi
