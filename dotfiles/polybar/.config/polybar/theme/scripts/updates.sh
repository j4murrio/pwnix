#!/usr/bin/env bash
# Polybar module: how many updates are pending. Clicking it runs update-system.sh.
#
# What counts as a source is defined once, in lib/update-sources.sh, and read by both
# this script and the updater — written twice they would drift, and the number in the
# bar would stop meaning anything.
#
# Only the package manager is counted (pacman with BlackArch and the AUR, or apt), which
# is exactly what the update touches. Hand-installed tooling is neither counted nor
# updated. The pwnix repository is shown separately as a glyph rather than a number:
# new configuration is a different thing from packages to install.
#
# A SIGUSR1 forces an immediate refresh, which is what update-system.sh sends when it
# finishes, so the bar is correct the moment an update ends.

SOURCES_LIB="$(dirname "$(readlink -f "$0")")/lib/update-sources.sh"
# shellcheck source=lib/update-sources.sh
. "$SOURCES_LIB" 2>/dev/null

# Glyph (nerd font, polybar font index 3) shown when the dotfiles repo is behind.
REPO_GLYPH="%{T3}%{T-}"

trap 'check_now=1' SIGUSR1

# True (0) when the pwnix repo is behind its remote.
repo_has_updates() {
    command -v git &>/dev/null || return 1
    local repo branch local_rev remote_rev
    repo=$(pwnix_repo 2>/dev/null) || return 1

    # Timeout + no credential prompt so a slow or offline remote never hangs the bar.
    timeout 10 env GIT_TERMINAL_PROMPT=0 git -C "$repo" fetch --quiet origin 2>/dev/null

    branch=$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null)
    local_rev=$(git -C "$repo" rev-parse HEAD 2>/dev/null)
    remote_rev=$(git -C "$repo" rev-parse "origin/$branch" 2>/dev/null)
    [[ -n "$remote_rev" && "$local_rev" != "$remote_rev" ]]
}

# Sets TOTAL, or returns 1 when it could not find out — being unable to reach a mirror
# is not the same as having nothing to install, and the bar says so.
count_all() {
    local packages aur
    packages=$(count_packages) || return 1
    aur=$(count_aur) || return 1
    TOTAL=$(( packages + aur ))
}

check_now=1
TOTAL=0

# Something on screen straight away, while the first check runs.
echo " ..."

while true; do
    if (( check_now )); then
        check_now=0

        if count_all; then
            ok=1
        else
            ok=0
        fi

        REPO_MARK=""
        repo_has_updates && REPO_MARK=" $REPO_GLYPH"

        if (( ! ok )); then
            # Offline, or the mirrors are unreachable. "None" would be a lie.
            echo "?${REPO_MARK}"
        elif (( TOTAL > 0 )); then
            echo "${TOTAL}${REPO_MARK}"
        elif [[ -n "$REPO_MARK" ]]; then
            # Nothing to install, but the dotfiles repo has new commits.
            echo "$REPO_GLYPH"
        else
            echo "None"
        fi
    fi

    # 30 minutes, slept a second at a time so a signal is caught promptly.
    for ((i=0; i<1800 && !check_now; i++)); do
        sleep 1
    done
done
