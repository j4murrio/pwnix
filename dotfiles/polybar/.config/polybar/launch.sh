#!/usr/bin/env bash

dir="$HOME/.config/polybar"

# The bar wears the badge of the distribution it is running on. modules.ini reads
# these through ${env:...} and falls back to Arch's if they are unset.
DISTRO_LIB="$dir/theme/scripts/lib/distro.sh"
if [[ -r "$DISTRO_LIB" ]]; then
    # shellcheck source=theme/scripts/lib/distro.sh
    . "$DISTRO_LIB"
    PWNIX_OS_GLYPH=$(printf "$(brand_glyph)")
    PWNIX_OS_COLOR=$(brand_color)
    export PWNIX_OS_GLYPH PWNIX_OS_COLOR
fi

# Terminate already running bar instances
killall -q polybar

# Wait until the processes have been shut down
while pgrep -u $UID -x polybar >/dev/null; do sleep 1; done

# Launch the bar
polybar -q main -c "$dir/theme/config.ini" &
