#!/usr/bin/env bash
# Where updates can come from on this machine, and how many are pending.
#
# Sourced by both update-system.sh (which updates them) and updates.sh (which counts
# them for the polybar). That is the whole point of the file: written twice, the two
# would drift and the number in the bar would stop matching what the update does.
#
# Two sources, deliberately: the package manager, and the pwnix repository. Things
# installed by hand — oh-my-zsh, tools under ~/Tools, python venvs, LazyVim plugins,
# flatpak, pipx, rustup, cargo — are neither counted nor updated, and the README carries
# the command for each.
#
# Counting convention: a count_* function prints a number and returns 0, or prints
# nothing and returns 1 when it cannot tell (offline, or the tool has no way to ask).
# "Cannot tell" is not "zero", and the bar shows them differently.
#
# Anything that differs between Arch and Debian/Kali is asked of distro.sh, never
# decided here.

# shellcheck source=distro.sh
. "$(dirname "${BASH_SOURCE[0]}")/distro.sh" 2>/dev/null

# The pwnix checkout, from the breadcrumb install.sh/sync.sh leave behind.
pwnix_repo() {
    [[ -f "$HOME/.config/.pwnix-repo-path" ]] || return 1
    local repo
    repo=$(cat "$HOME/.config/.pwnix-repo-path" 2>/dev/null)
    [[ -n "$repo" && -d "$repo/.git" ]] || return 1
    printf '%s\n' "$repo"
}

# pacman or apt, whichever this machine has: the distinction lives in distro.sh and the
# counting does not care. Prints nothing and returns 1 when it could not find out, which
# is what stops the bar reporting "None" to someone who is merely offline.
count_packages() {
    declare -F pkg_count_updates >/dev/null || return 1
    pkg_count_updates
}

# Arch only. Elsewhere there is no AUR, which is 0 pending rather than an error.
#
# The exit status is deliberately ignored. Queries in the pacman family exit 1 when
# they match nothing, and yay inherits that (Jguer/yay#1475), so "no AUR updates" —
# the normal state — looks identical to a failure. Reading it is what made the bar
# show a permanent ?. Being offline is still caught, by checkupdates, which is the
# one that actually talks to the mirrors and does report it properly.
count_aur() {
    declare -F is_arch >/dev/null && is_arch || { printf '0\n'; return 0; }
    command -v yay &>/dev/null || { printf '0\n'; return 0; }
    printf '%s\n' "$(yay -Qua 2>/dev/null | grep -c .)"
}
