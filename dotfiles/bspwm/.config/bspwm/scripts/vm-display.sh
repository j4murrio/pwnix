#!/bin/sh
#### vm-display.sh
# Auto-apply the SPICE / virtio display resolution and refresh the screen-sized
# visuals after spice-vdagent settles the size, event-driven (no sleeps).
#
# Cold-boot problem: X starts at QEMU's default mode (e.g. 1280x800). A moment
# later spice-vdagent negotiates the SPICE client size with the host and marks
# that larger mode (e.g. 1920x975) as the output's *preferred* one -- but nothing
# reapplies it, so the active mode stays 1280x800. Worse, the autostarted
# screen-sized visuals (feh wallpaper, polybar) were drawn at 1280x800 and do not
# re-draw on their own. So the desktop is mis-sized until a manual `bspc wm -r`
# (Super+Alt+R) re-runs xrandr --auto AND relaunches the visuals at the new size.
#
# Fix: do exactly that, automatically, when a RandR change shows the preferred
# mode differs from the active one (i.e. right when vdagent settles the size):
#   1. xrandr --output <out> --auto   -> switch X to the preferred (host) mode
#   2. refresh_visuals                -> redraw wallpaper / polybar / picom
# We listen on real X RandR events via xev, because the trigger is a new
# *preferred* mode appearing -- bspwm's monitor_geometry does NOT fire for that
# (the active geometry hasn't changed yet). No polling, no sleep. Once active ==
# preferred the step is a no-op, so it can't loop. We do NOT act on login:
# bspwmrc has just drawn the visuals and re-drawing then would race its
# feh/polybar. Output name is auto-detected (Virtual-1, Virtual-0, QXL-0, ...).

# Keep a single instance across `bspc wm -r` restarts.
for pid in $(pgrep -f vm-display.sh); do
    [ "$pid" = "$$" ] || kill "$pid" 2>/dev/null
done

# Active mode = resolution part of the output's geometry (always present, even
# when no mode line carries '*').
active_mode() {
    xrandr -q | awk '/ connected/{
        for (i = 1; i <= NF; i++)
            if ($i ~ /^[0-9]+x[0-9]+\+[0-9]+\+[0-9]+$/) { sub(/\+.*/, "", $i); print $i; exit }
    }'
}

# Preferred mode = first indented mode line carrying '+'.
pref_mode() { xrandr -q | awk '/^[[:space:]].*\+/{print $1; exit}'; }

# Re-draw the screen-sized autostart components at the current resolution.
# NOTE: keep this in sync with the visual autostart block in bspwmrc.
refresh_visuals() {
    feh --bg-fill ~/Wallpapers/wallpaper.png &
    ~/.config/polybar/launch.sh &
    picom_conf="$HOME/.config/picom/picom.conf"
    [ -f "$HOME/.config/picom.local.conf" ] && picom_conf="$HOME/.config/picom.local.conf"
    pkill -x picom; picom --config "$picom_conf" &
}

fit() {
    out=$(xrandr -q | awk '/ connected/{print $1; exit}')
    [ -n "$out" ] || return
    pref=$(pref_mode)
    # Only act when X is not yet on the preferred (host-negotiated) mode.
    [ -n "$pref" ] && [ "$pref" != "$(active_mode)" ] || return
    xrandr --output "$out" --auto   # synchronous: X is on the new mode on return
    refresh_visuals                 # redraw wallpaper/polybar/picom at that size
}

# Re-fit on RandR changes (spice-vdagent registering/preferring the host mode).
# xev blocks on events -- no polling, no sleep. If xorg-xev is missing we fall
# back to bspwm's monitor events (catches fewer cases, but no hard dependency).
if command -v xev >/dev/null 2>&1; then
    xev -root -event randr 2>/dev/null | while read -r l; do
        case "$l" in *RRScreenChangeNotify*|*RRNotify*) fit ;; esac
    done
else
    bspc subscribe monitor | while read -r _; do fit; done
fi
