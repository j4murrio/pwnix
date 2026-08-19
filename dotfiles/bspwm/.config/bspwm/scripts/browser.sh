#!/usr/bin/env bash
# Open the web browser this machine actually has.
#
# The keybinding used to name a binary, and a binary is a distribution's decision: Kali
# ships firefox-esr, Arch installs firefox, and Super+F was a dead key on whichever one
# was not the author's. $BROWSER wins over the list, so a machine can pick a different
# one from ~/.zshrc.local without editing a tracked file.

if [[ -n "$BROWSER" ]] && command -v "${BROWSER%% *}" &>/dev/null; then
    # Unquoted on purpose: $BROWSER may carry flags.
    # shellcheck disable=SC2086
    exec $BROWSER "$@"
fi

for candidate in firefox firefox-esr firefox-developer-edition chromium google-chrome-stable; do
    command -v "$candidate" &>/dev/null && exec "$candidate" "$@"
done

notify-send "No browser found" "Install firefox, or set BROWSER in ~/.zshrc.local" 2>/dev/null
exit 1
