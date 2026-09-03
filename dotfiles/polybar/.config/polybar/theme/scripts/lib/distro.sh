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
            firefox)       printf 'firefox\n' ;;
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
            curl)          printf 'curl\n' ;;
            lazygit)       printf 'lazygit\n' ;;
            ripgrep)       printf 'ripgrep\n' ;;
            fd)            printf 'fd\n' ;;
            tree-sitter-cli) printf 'tree-sitter-cli\n' ;;
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
        curl)           printf 'curl\n' ;;
        lazygit)        printf 'lazygit\n' ;;
        ripgrep)        printf 'ripgrep\n' ;;
        fd)             printf 'fd-find\n' ;;
        tree-sitter-cli) printf 'tree-sitter-cli\n' ;;
        vmware-tools)   printf 'open-vm-tools open-vm-tools-desktop\n' ;;
        *)              printf '%s\n' "$logical" ;;
    esac
}

# ──────────────────────────────────────────────────────────
#  LazyVim
# ──────────────────────────────────────────────────────────

# What LazyVim needs beyond neovim itself, in logical names. Printed rather than held in a
# variable so install.sh and sync.sh read the same list and cannot drift apart. The rest of
# what it asks for already comes with the environment: a C compiler through build-tools, a
# Nerd Font from assets/fonts, fzf among the system utilities, and kitty as the terminal.
lazyvim_deps() {
    printf 'curl git lazygit ripgrep fd tree-sitter-cli\n'
}

# Debian ships fd's binary as fdfind. The .zshrc alias covers an interactive shell, but
# fzf-lua looks the binary up in PATH and never sees it, so LazyVim falls back to find
# without saying so. The link is what Debian's own package documentation suggests.
ensure_fd_binary() {
    is_debian || return 0
    command -v fd &>/dev/null && return 0
    command -v fdfind &>/dev/null || return 0
    sudo ln -sf "$(command -v fdfind)" /usr/local/bin/fd
}

# True when version $1 is at least $2. sort -V knows 0.11.2 comes after 0.9.5; string
# comparison does not.
version_at_least() {
    [[ -n "$1" ]] || return 1
    [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" == "$2" ]]
}

# ──────────────────────────────────────────────────────────
#  Querying
# ──────────────────────────────────────────────────────────

# A pacman group (xorg, base-devel) rather than a package. Debian has no such thing: its
# equivalents are metapackages, which are ordinary packages and need none of this.
pkg_is_group() {
    case "$(distro_id)" in
        arch) pacman -Sg "$1" &>/dev/null ;;
        *)    return 1 ;;
    esac
}

# A group is never "installed": it is a list of names, and having some of them says
# nothing about the rest. Answering false sends it to pacman, where --needed makes the
# already-installed members a no-op.
pkg_installed() {
    case "$(distro_id)" in
        arch)   pkg_is_group "$1" && return 1
                pacman -Qi "$1" &>/dev/null ;;
        debian) [[ "$(dpkg-query -W -f='${Status}' "$1" 2>/dev/null)" == "install ok installed" ]] ;;
        *)      return 1 ;;
    esac
}

# Package *or* group. Asking only `pacman -Si` is what made the installer report
# "xorg -> xorg not available on arch" and skip the whole X utility set on every Arch
# install, while Debian was getting its `xorg` metapackage in full.
pkg_available() {
    case "$(distro_id)" in
        arch)   pacman -Si "$1" &>/dev/null || pkg_is_group "$1" ;;
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

# A package index of this user's own, for apt.
#
# apt has no checkupdates(8), and that gap is what left the Kali counter saying "None" for
# days at a time: it counted against /var/lib/apt/lists as they stood, and nothing on Kali
# refreshes those on its own — apt-daily only does it when APT::Periodic::Update-Package-Lists
# is set, which is unattended-upgrades' doing and Kali does not install it. Arch never had
# the problem: checkupdates syncs a database of its own, as an ordinary user.
#
# So this is that database. Refreshing it needs no root, which is the whole point: a polybar
# module has no terminal and must never ask for a password.

: "${PWNIX_APT_CACHE:=${XDG_CACHE_HOME:-$HOME/.cache}/pwnix/apt}"

# The system's own lists. Overridable for the same reason PWNIX_OS_RELEASE is: so the
# choice between the two indices can be exercised without a machine in each state.
: "${PWNIX_APT_SYSTEM_LISTS:=/var/lib/apt/lists}"

# How long a refresh counts as current. The kali-rolling index is not something to fetch
# every thirty minutes, and apt only fetches diffs after the first time.
: "${PWNIX_APT_TTL:=10800}"

_apt_cache_init() {
    mkdir -p "$PWNIX_APT_CACHE/lists/partial" "$PWNIX_APT_CACHE/cache/archives/partial"
}

# When a lists directory last received an index, as a unix timestamp. Nothing at all when it
# holds none, which is how "never refreshed" stays distinct from "refreshed long ago".
_apt_lists_age() {
    local newest
    newest=$(find "$1" -maxdepth 1 -type f -name '*_Packages*' -printf '%T@\n' 2>/dev/null |
        sort -n | tail -1)
    [[ -n "$newest" ]] || return 1
    printf '%d\n' "${newest%%.*}"
}

# Age of the private index, from the stamp rather than from the files. A mirror with nothing
# new answers 304 and apt leaves every timestamp alone, so the files can say what changed but
# never when the last refresh happened.
_apt_private_age() {
    local stamp="$PWNIX_APT_CACHE/refreshed.stamp" age
    _apt_lists_age "$PWNIX_APT_CACHE/lists" >/dev/null || return 1
    if [[ -f "$stamp" ]] && age=$(stat -c %Y "$stamp" 2>/dev/null) && [[ -n "$age" ]]; then
        printf '%s\n' "$age"
        return 0
    fi
    _apt_lists_age "$PWNIX_APT_CACHE/lists"
}

# "<directory> <timestamp>" for whichever index was refreshed last. Right after sysup — or
# after an apt update of your own — the system's is the fresher of the two, so the ordinary
# case downloads nothing at all.
_apt_newest_lists() {
    local sys="$PWNIX_APT_SYSTEM_LISTS" own="$PWNIX_APT_CACHE/lists" sys_age own_age
    sys_age=$(_apt_lists_age "$sys") || sys_age=0
    own_age=$(_apt_private_age) || own_age=0
    (( sys_age == 0 && own_age == 0 )) && return 1
    if (( own_age > sys_age )); then
        printf '%s %s\n' "$own" "$own_age"
    else
        printf '%s %s\n' "$sys" "$sys_age"
    fi
}

# Refresh the private index. Bounded and silent: the bar must not hang on an unreachable
# mirror, and it would have nowhere to print if it did.
apt_private_refresh() {
    local lists="$PWNIX_APT_CACHE/lists" before after rc=0
    _apt_cache_init || return 1
    before=$(_apt_lists_age "$lists") || before=0

    apt-get update -qq \
        -o Dir::State::Lists="$lists" \
        -o Dir::Cache="$PWNIX_APT_CACHE/cache" \
        -o Acquire::Languages=none \
        -o Acquire::Retries=1 \
        -o Acquire::http::Timeout=10 \
        -o Acquire::https::Timeout=10 \
        >/dev/null 2>&1 || rc=$?

    # The status on its own is not the answer. A Post-Invoke-Success script in apt.conf.d
    # that expects root — cnf-update-db is the usual one — fails long after the indices
    # arrived intact and takes apt-get's status down with it. Being offline, by contrast,
    # leaves every timestamp exactly where it was.
    after=$(_apt_lists_age "$lists") || return 1
    (( rc == 0 || after > before )) || return 1
    touch "$PWNIX_APT_CACHE/refreshed.stamp"
}

# How many packages the given index says are waiting.
_apt_count_against() {
    local out
    _apt_cache_init || return 1
    out=$(apt-get --just-print dist-upgrade \
        -o Dir::State::Lists="$1" \
        -o Dir::Cache="$PWNIX_APT_CACHE/cache" 2>/dev/null) || return 1
    printf '%s\n' "$(printf '%s\n' "$out" | grep -c '^Inst ')"
}

# How many packages are waiting. Prints a number and returns 0, or prints nothing and
# returns 1 when it could not find out — offline is not the same as up to date.
pkg_count_updates() {
    local out rc lists age now
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
            # Packages held by IgnorePkg are dropped: no upgrade will ever clear them, and
            # counting them leaves a number that never reaches zero.
            printf '%s\n' "$(pacman -Qu 2>/dev/null | grep -v '\[ignored\]' | grep -c .)"
            ;;
        debian)
            # Whichever index is current, and a refresh of our own only when neither is.
            # Counting against lists nobody had refreshed is what reported "None" on Kali
            # while apt full-upgrade had hundreds of packages waiting.
            now=$(date +%s)
            read -r lists age <<< "$(_apt_newest_lists)"
            if [[ -n "$lists" ]] && (( now - age < PWNIX_APT_TTL )); then
                _apt_count_against "$lists"
                return
            fi
            apt_private_refresh || return 1
            _apt_count_against "$PWNIX_APT_CACHE/lists"
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

# The newest kernel installed on Arch, by its module directory. Only directories carrying a
# pkgbase file count: pacman leaves the rest behind whenever something wrote into them — a
# DKMS or nvidia module is enough — and a leftover from a kernel that is no longer installed
# is how the bar came to ask for a restart that no restart ever cleared.
_arch_latest_kernel() {
    local latest
    latest=$(find /usr/lib/modules -mindepth 2 -maxdepth 2 -name pkgbase -printf '%h\n' 2>/dev/null |
        sed 's|.*/||' | sort -V | tail -1)
    [[ -n "$latest" ]] || return 1
    printf '%s\n' "$latest"
}

# The kernel Debian would boot next. dpkg names those packages linux-image-<uname -r>, so the
# comparison is direct; the metapackages carry no version in the name and are skipped.
_debian_latest_kernel() {
    local latest
    latest=$(dpkg-query -W -f='${Package} ${Status}\n' 'linux-image-*' 2>/dev/null |
        awk '$2 == "install" && $4 == "installed" { print $1 }' |
        sed -n 's/^linux-image-\([0-9].*\)$/\1/p' | sort -V | tail -1)
    [[ -n "$latest" ]] || return 1
    printf '%s\n' "$latest"
}

# True when the machine is running an older kernel than the one installed. Debian leaves a
# file behind and answering from it is both cheaper and wider, since it also covers the
# non-kernel cases that need a restart — but that file comes from update-notifier-common,
# which Kali does not install, so the kernel is compared directly when it is missing rather
# than reporting that nothing is pending.
reboot_required() {
    local running latest
    case "$(distro_id)" in
        arch)
            running=$(uname -r)
            latest=$(_arch_latest_kernel) || return 1
            [[ "$running" != "$latest" ]]
            ;;
        debian)
            [[ -f /var/run/reboot-required ]] && return 0
            running=$(uname -r)
            latest=$(_debian_latest_kernel) || return 1
            [[ "$running" != "$latest" ]]
            ;;
        *) return 1 ;;
    esac
}

# What to tell the user about the pending restart, in one line.
reboot_reason() {
    local running latest
    case "$(distro_id)" in
        arch)
            running=$(uname -r)
            latest=$(_arch_latest_kernel)
            printf 'Running: %s  ->  Installed: %s\n' "$running" "$latest"
            ;;
        debian)
            if [[ -f /var/run/reboot-required.pkgs ]]; then
                printf 'Packages needing a restart: %s\n' \
                    "$(paste -sd ', ' /var/run/reboot-required.pkgs 2>/dev/null)"
            elif latest=$(_debian_latest_kernel); then
                running=$(uname -r)
                printf 'Running: %s  ->  Installed: %s\n' "$running" "$latest"
            else
                printf 'The system reports that a restart is required.\n'
            fi
            ;;
    esac
}

# ──────────────────────────────────────────────────────────
#  Services
# ──────────────────────────────────────────────────────────

# The units a hypervisor's guest tools bring, by their name *here*. Same software, two
# spellings: on Debian the real unit is open-vm-tools.service, vmtoolsd.service is only a
# linked alias the package has already enabled, and vmware-vmblock-fuse.service does not
# exist at all — which is exactly the two "Failed to enable unit" lines a Kali install
# used to end with.
vm_units() {
    case "$1" in
        vmware)
            if is_arch; then
                printf 'vmtoolsd.service vmware-vmblock-fuse.service\n'
            else
                printf 'open-vm-tools.service\n'
            fi
            ;;
        spice) printf 'spice-vdagentd.service qemu-guest-agent.service\n' ;;
        *)     return 1 ;;
    esac
}

# Enable what is actually here, and say nothing when there is nothing to do. A unit the
# package enabled itself is already on; one linked by the package cannot be enabled again
# and does not need to be. Neither is a problem worth printing at somebody mid-install.
service_enable() {
    local unit state rc=0
    for unit in "$@"; do
        if ! systemctl list-unit-files --no-legend "$unit" 2>/dev/null | grep -q .; then
            continue
        fi
        state=$(systemctl is-enabled "$unit" 2>/dev/null)
        case "$state" in
            enabled|enabled-runtime|static|indirect|alias|linked|linked-runtime) continue ;;
        esac
        if ! sudo systemctl enable "$unit" >/dev/null 2>&1; then
            echo "[!] Could not enable $unit"
            rc=1
        fi
    done
    return "$rc"
}

# Arch keeps its signing keys in packages that must be updated before anything else, or
# every signature check downstream fails. apt has no equivalent step.
pkg_update_keyring() {
    is_arch || return 0
    local -a keyrings=(archlinux-keyring)
    pacman -Qi blackarch-keyring &>/dev/null && keyrings+=(blackarch-keyring)
    sudo pacman -Sy --noconfirm --needed "${keyrings[@]}"
}
