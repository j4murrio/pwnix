#!/usr/bin/env bash
# The one place that knows the difference between Arch and Debian/Kali.
#
# Everything else in this repository is written once and calls through here. That is the
# deal: a package name, a manager invocation or a "does this distribution even have
# that" question belongs in this file and nowhere else.
#
# Sourced by install.sh, sync.sh, update-system.sh and lib/update-sources.sh. It sets no
# state and runs nothing when sourced.

# ──────────────────────────────────────────────────────────
#  Which distribution
# ──────────────────────────────────────────────────────────

# Which file describes this system. Overridable so the behaviour can be exercised
# against every distribution from one machine, instead of only the one it runs on.
: "${PWNIX_OS_RELEASE:=/etc/os-release}"

# arch | debian | unknown. ID first, then ID_LIKE, so derivatives (Kali says
# ID=kali/ID_LIKE=debian, EndeavourOS says ID_LIKE=arch) land on the right side without
# being listed one by one.
distro_id() {
    if [[ -z "${_DISTRO_ID:-}" ]]; then
        local id="" like=""
        if [[ -r "$PWNIX_OS_RELEASE" ]]; then
            id=$(. "$PWNIX_OS_RELEASE" 2>/dev/null && printf '%s' "${ID:-}")
            like=$(. "$PWNIX_OS_RELEASE" 2>/dev/null && printf '%s' "${ID_LIKE:-}")
        fi
        case "$id" in
            arch|archarm|manjaro|endeavouros|artix) _DISTRO_ID=arch ;;
            debian|kali|ubuntu|parrot|raspbian)     _DISTRO_ID=debian ;;
            *)
                case " $like " in
                    *" arch "*)   _DISTRO_ID=arch ;;
                    *" debian "*) _DISTRO_ID=debian ;;
                    *)            _DISTRO_ID=unknown ;;
                esac
                ;;
        esac
    fi
    printf '%s\n' "$_DISTRO_ID"
}

is_arch()   { [[ "$(distro_id)" == arch ]]; }
is_debian() { [[ "$(distro_id)" == debian ]]; }

# The exact distribution rather than the family. distro_id folds Kali into debian
# because that is what matters for packaging; branding needs to tell them apart.
distro_variant() {
    if [[ -z "${_DISTRO_VARIANT:-}" ]]; then
        _DISTRO_VARIANT=unknown
        [[ -r "$PWNIX_OS_RELEASE" ]] &&
            _DISTRO_VARIANT=$(. "$PWNIX_OS_RELEASE" 2>/dev/null && printf '%s' "${ID:-unknown}")
    fi
    printf '%s\n' "$_DISTRO_VARIANT"
}

# ──────────────────────────────────────────────────────────
#  Branding
# ──────────────────────────────────────────────────────────
# The logo, the accent colour and the wallpaper that go with this distribution.
# Read by the polybar launcher, by the prompt and by the installer, so a machine
# never ends up wearing another distribution's badge.

brand_name() {
    case "$(distro_variant)" in
        arch) printf 'Arch Linux\n' ;;
        kali) printf 'Kali Linux\n' ;;
        *)    [[ -r "$PWNIX_OS_RELEASE" ]] &&
                  (. "$PWNIX_OS_RELEASE" 2>/dev/null && printf '%s\n' "${NAME:-Linux}") ||
                  printf 'Linux\n' ;;
    esac
}

# Nerd Font logos: nf-md-arch for Arch, nf-linux-kali_linux (U+F327) for Kali. Both
# live in ranges the bundled JetBrainsMono Nerd Font carries.
brand_glyph() {
    case "$(distro_variant)" in
        kali) printf '\uf327\n' ;;
        *)    printf '\U000f08c7\n' ;;
    esac
}

brand_color() {
    case "$(distro_variant)" in
        kali) printf '#367BF0\n' ;;
        *)    printf '#0A9CF5\n' ;;
    esac
}

# The wallpaper file for this distribution, inside assets/wallpapers/. Falls back to
# arch.png so an unrecognised distribution still gets a desktop rather than a void.
brand_wallpaper() {
    case "$(distro_variant)" in
        kali) printf 'kali.png\n' ;;
        *)    printf 'arch.png\n' ;;
    esac
}

# Copy the right wallpaper into place under the single name the configs reference.
install_wallpaper() {
    local assets="$1" src
    src="$assets/$(brand_wallpaper)"
    [[ -f "$src" ]] || return 1
    mkdir -p "$HOME/Wallpapers"
    cp -f "$src" "$HOME/Wallpapers/wallpaper.png"
}

# ──────────────────────────────────────────────────────────
#  Package names
# ──────────────────────────────────────────────────────────

# Translate a logical name into what this distribution calls it. Empty output means the
# distribution has no such package, which is a normal answer and not an error: wmname
# does not exist in Debian, checkupdates has no equivalent, and callers skip them.
#
# Anything not listed is assumed to be spelled the same on both, which covers most of
# the list (bspwm, sxhkd, polybar, picom, rofi, kitty, zsh, git, feh, lsd, fzf...).
pkg_name() {
    local logical="$1"
    if is_arch; then
        case "$logical" in
            build-tools)   printf 'base-devel\n' ;;
            linux-headers) printf 'linux-headers\n' ;;
            networkmanager) printf 'networkmanager\n' ;;
            xorg-server)   printf 'xorg-server\n' ;;
            xinit)         printf 'xorg-xinit\n' ;;
            xev)           printf 'xorg-xev\n' ;;
            firefox)       printf 'firefox-developer-edition\n' ;;
            man-pages)     printf 'man-pages\n' ;;
            gvfs-mtp)      printf 'gvfs-mtp\n' ;;
            python-pip)    printf 'python-pip\n' ;;
            procps)        printf 'procps-ng\n' ;;
            ping)          printf 'inetutils\n' ;;
            emoji-font)    printf 'noto-fonts-emoji\n' ;;
            libnotify)     printf 'libnotify\n' ;;
            golang)        printf 'go\n' ;;
            i3lock-fancy)  printf 'i3lock-fancy-git\n' ;;
            pywal)         printf 'python-pywal\n' ;;
            checkupdates)  printf 'pacman-contrib\n' ;;
            pulseaudio-alsa) printf 'pulseaudio-alsa\n' ;;
            vmware-tools)  printf 'open-vm-tools gtkmm3\n' ;;
            *)             printf '%s\n' "$logical" ;;
        esac
        return 0
    fi

    case "$logical" in
        # No Debian equivalent. Callers skip an empty answer.
        base|wmname|checkupdates|pulseaudio-alsa|pywal) printf '\n' ;;

        build-tools)    printf 'build-essential\n' ;;
        linux-headers)  printf 'linux-headers-amd64\n' ;;
        networkmanager) printf 'network-manager\n' ;;
        xorg-server)    printf 'xserver-xorg\n' ;;
        xinit)          printf 'xinit\n' ;;
        xev)            printf 'x11-utils\n' ;;
        firefox)        printf 'firefox-esr\n' ;;
        man-pages)      printf 'manpages\n' ;;
        gvfs-mtp)       printf 'gvfs-backends\n' ;;
        python-pip)     printf 'python3-pip\n' ;;
        procps)         printf 'procps\n' ;;
        ping)           printf 'inetutils-ping\n' ;;
        emoji-font)     printf 'fonts-noto-color-emoji\n' ;;
        libnotify)      printf 'libnotify-bin\n' ;;
        golang)         printf 'golang-go\n' ;;
        i3lock-fancy)   printf 'i3lock-fancy\n' ;;
        vmware-tools)   printf 'open-vm-tools open-vm-tools-desktop\n' ;;
        *)              printf '%s\n' "$logical" ;;
    esac
}

# ──────────────────────────────────────────────────────────
#  Querying
# ──────────────────────────────────────────────────────────

pkg_installed() {
    case "$(distro_id)" in
        arch)   pacman -Qi "$1" &>/dev/null ;;
        debian) [[ "$(dpkg-query -W -f='${Status}' "$1" 2>/dev/null)" == "install ok installed" ]] ;;
        *)      return 1 ;;
    esac
}

pkg_available() {
    case "$(distro_id)" in
        arch)   pacman -Si "$1" &>/dev/null ;;
        debian) apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/{print $2}' | grep -qv '(none)' ;;
        *)      return 1 ;;
    esac
}

# ──────────────────────────────────────────────────────────
#  Installing
# ──────────────────────────────────────────────────────────

# Install the logical packages that are missing, and only those.
#
# Two rules it exists to enforce. Anything already on the machine is left exactly as it
# is — on Kali most of this is present out of the box and reinstalling it would be both
# pointless and a way to pull in surprise upgrades. And a name this distribution does
# not have is *reported*, never fatal: the map cannot be perfect for every release, and
# one wrong entry must not abort an install halfway through.
#
# Leaves the names it could not find in PKG_UNAVAILABLE for the caller to report.
pkg_install() {
    local logical concrete part
    local -a to_install=()
    PKG_UNAVAILABLE=()
    PKG_FAILED_LAST=()

    for logical in "$@"; do
        concrete=$(pkg_name "$logical")
        [[ -n "${concrete// /}" ]] || continue

        # A logical name can map to more than one real package (vmware-tools).
        for part in $concrete; do
            pkg_installed "$part" && continue
            if pkg_available "$part"; then
                to_install+=("$part")
            else
                PKG_UNAVAILABLE+=("$logical -> $part")
            fi
        done
    done

    (( ${#to_install[@]} )) || return 0

    # Both managers are transactional: one package they refuse takes the entire batch
    # down with it, and a batch here is twenty-odd packages. When that happens, go back
    # over them one at a time so the rest still land and the culprit is named.
    if _pkg_install_batch "${to_install[@]}"; then
        return 0
    fi

    echo "[!] The batch failed. Retrying one package at a time..."
    for part in "${to_install[@]}"; do
        _pkg_install_batch "$part" || PKG_FAILED_LAST+=("$part")
    done
    (( ${#PKG_FAILED_LAST[@]} == 0 ))
}

_pkg_install_batch() {
    case "$(distro_id)" in
        arch)   sudo pacman -S --noconfirm --needed "$@" ;;
        debian) sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" ;;
        *)      return 1 ;;
    esac
}

# ──────────────────────────────────────────────────────────
#  Updating
# ──────────────────────────────────────────────────────────

# Refresh the package lists. On Arch this is folded into the upgrade; apt needs it first
# before it can even say what is out of date.
pkg_refresh() {
    case "$(distro_id)" in
        arch)   sudo pacman -Sy --noconfirm ;;
        debian) sudo DEBIAN_FRONTEND=noninteractive apt-get update ;;
        *)      return 1 ;;
    esac
}

pkg_update_all() {
    case "$(distro_id)" in
        arch)
            sudo pacman -Syu --noconfirm
            ;;
        debian)
            # Without these two, a package shipping a new version of a config file you
            # have edited stops the whole run on a (Y/I/N/O/D/Z) prompt that -y does not
            # cover. confold keeps your file; confdef takes the maintainer's default
            # where there is nothing of yours to lose. Answering Y at that prompt would
            # overwrite your configuration, which is why that is not what happens here.
            sudo DEBIAN_FRONTEND=noninteractive apt-get \
                -o Dpkg::Options::=--force-confdef \
                -o Dpkg::Options::=--force-confold \
                dist-upgrade -y
            ;;
        *) return 1 ;;
    esac
}

# How many packages are waiting. Prints a number and returns 0, or prints nothing and
# returns 1 when it could not find out — offline is not the same as up to date.
pkg_count_updates() {
    local out rc
    case "$(distro_id)" in
        arch)
            # checkupdates(8): 0 updates available, 1 failure, 2 none available. It is
            # the only one of the two that tells those apart, which makes it the source
            # of the ? when the mirrors cannot be reached.
            if command -v checkupdates &>/dev/null; then
                out=$(checkupdates 2>/dev/null)
                rc=$?
                (( rc == 0 )) && { printf '%s\n' "$(printf '%s' "$out" | grep -c .)"; return 0; }
                (( rc == 2 )) && { printf '0\n'; return 0; }
                return 1
            fi
            # Without pacman-contrib, count against the local database instead. It can
            # be a sync behind, but a slightly stale number beats a permanent ?. No
            # status check here either: pacman -Qu also exits 1 on an empty result.
            printf '%s\n' "$(pacman -Qu 2>/dev/null | grep -c .)"
            ;;
        debian)
            # Deliberately without apt-get update: refreshing the lists needs root, and a
            # polybar module must never ask for a password. It counts against the lists
            # as they stand, which the update itself refreshes.
            out=$(apt-get --just-print dist-upgrade 2>/dev/null) || return 1
            printf '%s\n' "$(printf '%s\n' "$out" | grep -c '^Inst ')"
            ;;
        *) return 1 ;;
    esac
}

# Packages pulled in as dependencies that nothing needs any more.
pkg_orphans() {
    case "$(distro_id)" in
        arch)
            pacman -Qtdq 2>/dev/null
            ;;
        debian)
            apt-get --just-print autoremove 2>/dev/null |
                awk '/^Remv /{print $2}'
            ;;
        *) return 1 ;;
    esac
}

pkg_remove_orphans() {
    case "$(distro_id)" in
        arch)   sudo pacman -Rns --noconfirm "$@" ;;
        debian) sudo DEBIAN_FRONTEND=noninteractive apt-get autoremove -y ;;
        *)      return 1 ;;
    esac
}

pkg_clean_cache() {
    case "$(distro_id)" in
        arch)
            # Leftover partial downloads first, or pacman -Sc trips over them.
            sudo find /var/cache/pacman/pkg/ -name 'download-*' -delete 2>/dev/null
            sudo pacman -Sc --noconfirm
            ;;
        debian)
            sudo apt-get clean
            ;;
        *) return 1 ;;
    esac
}

# ──────────────────────────────────────────────────────────
#  System state
# ──────────────────────────────────────────────────────────

# True when the machine is running an older kernel than the one installed. Arch has to
# be asked; Debian leaves a file behind and answering from it is both cheaper and more
# accurate, since it also covers the non-kernel cases that need a restart.
reboot_required() {
    case "$(distro_id)" in
        arch)
            local running latest
            running=$(uname -r)
            latest=$(find /usr/lib/modules -maxdepth 1 -mindepth 1 -type d -printf '%f\n' 2>/dev/null |
                sort -V | tail -1)
            [[ -n "$latest" && "$running" != "$latest" ]]
            ;;
        debian)
            [[ -f /var/run/reboot-required ]]
            ;;
        *) return 1 ;;
    esac
}

# What to tell the user about the pending restart, in one line.
reboot_reason() {
    case "$(distro_id)" in
        arch)
            local running latest
            running=$(uname -r)
            latest=$(find /usr/lib/modules -maxdepth 1 -mindepth 1 -type d -printf '%f\n' 2>/dev/null |
                sort -V | tail -1)
            printf 'Running: %s  ->  Installed: %s\n' "$running" "$latest"
            ;;
        debian)
            if [[ -f /var/run/reboot-required.pkgs ]]; then
                printf 'Packages needing a restart: %s\n' \
                    "$(paste -sd ', ' /var/run/reboot-required.pkgs 2>/dev/null)"
            else
                printf 'The system reports that a restart is required.\n'
            fi
            ;;
    esac
}

# Arch keeps its signing keys in packages that must be updated before anything else, or
# every signature check downstream fails. apt has no equivalent step.
pkg_update_keyring() {
    is_arch || return 0
    local -a keyrings=(archlinux-keyring)
    pacman -Qi blackarch-keyring &>/dev/null && keyrings+=(blackarch-keyring)
    sudo pacman -Sy --noconfirm --needed "${keyrings[@]}"
}
