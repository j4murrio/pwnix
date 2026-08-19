#!/bin/sh

# Get ethernet interface name (can be eth0, enp0s3, ens33, etc.)
ETH_INTERFACE=$(ip -o link show | awk -F': ' '$2 !~ /^(lo|wl|tun|tap|wg|ppp|docker|veth|br-)/ {print $2; exit}')

if [ -n "$ETH_INTERFACE" ]; then
    ETH_IP=$(ip -4 addr show "$ETH_INTERFACE" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    if [ -n "$ETH_IP" ]; then
        echo "$ETH_IP"
    else
        echo "Disconnected"
    fi
else
    echo "No interface"
fi
