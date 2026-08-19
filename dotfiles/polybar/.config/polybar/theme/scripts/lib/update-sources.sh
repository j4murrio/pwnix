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

# The branch this checkout follows: its configured upstream, or origin/<branch> when it
# has none. Nothing at all on a detached HEAD — where `rev-parse --abbrev-ref HEAD` says
# "HEAD" and origin/HEAD then resolves to the default branch, which is how the bar came
# to report updates against a branch this checkout is not on.
pwnix_upstream() {
    local repo="$1" upstream branch
    upstream=$(git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)
    if [[ -z "$upstream" ]]; then
        branch=$(git -C "$repo" symbolic-ref --quiet --short HEAD 2>/dev/null) || return 1
        upstream="origin/$branch"
    fi
    git -C "$repo" rev-parse --verify --quiet "$upstream" >/dev/null 2>&1 || return 1
    printf '%s\n' "$upstream"
}

# "<behind> <ahead>": commits the remote has and this checkout does not, then the ones
# only this checkout has.
#
# Behind is the only one that means "there is an update". Reading the two as a single
# "local != remote" is what kept the glyph lit for good on any machine where a config had
# been committed — which the README actively invites, since stow makes editing ~/.zshrc an
# edit of this repository.
pwnix_repo_counts() {
    local repo="$1" upstream counts ahead behind
    upstream=$(pwnix_upstream "$repo") || return 1
    counts=$(git -C "$repo" rev-list --left-right --count "HEAD...$upstream" 2>/dev/null) || return 1
    read -r ahead behind <<< "$counts"
    [[ -n "$behind" ]] || return 1
    printf '%s %s\n' "$behind" "$ahead"
}

# A fetch that can never turn into a question. GIT_TERMINAL_PROMPT only covers the
# terminal, and a polybar module has no terminal: without the rest, a graphical askpass or
# an ssh key with a passphrase opens a window every thirty minutes. Failing silently is
# the right answer here — the caller reports "cannot tell", not "up to date".
pwnix_fetch() {
    local repo="$1" secs="${2:-10}"
    timeout "$secs" env \
        GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/bin/true SSH_ASKPASS=/bin/true \
        SSH_ASKPASS_REQUIRE=never GIT_SSH_COMMAND='ssh -o BatchMode=yes' \
        git -C "$repo" fetch --quiet origin 2>/dev/null
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
