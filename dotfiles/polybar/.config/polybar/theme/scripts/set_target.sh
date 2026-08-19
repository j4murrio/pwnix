#!/bin/sh

target_file="$HOME/.config/files/target"

# Check if file exists and is not empty
if [ ! -f "$target_file" ] || [ ! -s "$target_file" ]; then
    echo "No target"
    exit 0
fi

ip_target=$(awk '{print $1}' "$target_file")
name_target=$(awk '{print $2}' "$target_file")

if [ -n "$ip_target" ] && [ -n "$name_target" ]; then
    echo "$ip_target - $name_target"
elif [ -n "$ip_target" ]; then
    echo "$ip_target"
else
    echo "No target"
fi
