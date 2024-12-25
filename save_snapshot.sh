#!/bin/bash

# Request container name
read -p "Enter container name: " container_name

# Get list of snapshots
echo "Available snapshots for container $container_name:"
lxc info $container_name | sed -n '/Snapshots:/,/^$/p' | tail -n +2

# Request snapshot name
read -p "Enter snapshot name to save: " snapshot_name

# Generate filename for saving
filename="${container_name}_${snapshot_name}_$(date +"%Y%m%d_%H%M%S")_$(lxc version | awk '/Server version:/ {print $3}')_$(hostname -I | awk '{print $1}')"

# Save snapshot
lxc publish $container_name/$snapshot_name --alias $filename

echo "Snapshot saved as image with name: $filename"
