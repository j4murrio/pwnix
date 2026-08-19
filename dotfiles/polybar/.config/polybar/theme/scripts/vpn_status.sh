#!/bin/sh

# Auto-detect VPN interface (tun, tap, wg, ppp)
for iface in $(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | grep -E '^(tun|tap|wg|ppp)'); do
    VPN_IP=$(ip -4 addr show "$iface" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    if [ -n "$VPN_IP" ]; then
        echo "$VPN_IP"
        exit 0
    fi
done

echo "Disconnected"
