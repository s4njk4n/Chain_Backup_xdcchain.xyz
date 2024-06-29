#!/bin/bash

# Set variables
snapshot_directory="/var/www/html/snapshot/"
snapshot_file="xdcchain.xyz_snapshot.tar"
log_file="/root/Chain_Backup_DL_Server_Control/events.log"

# Function to check command execution status and log errors
check_status() {
    if [ $1 -eq 0 ]; then
        echo "$(date +"%Y-%m-%d %H:%M:%S") - Snapshot Rotation Bot - $2 completed successfully." >> "$log_file"
    else
        echo "$(date +"%Y-%m-%d %H:%M:%S") - Snapshot Rotation Bot - Error: $2 failed. Check the error.log for details." >> "$log_file"
        exit 1
    fi
}

# Log script start time
echo "$(date +"%Y-%m-%d %H:%M:%S") - Snapshot Rotation Bot - Starting snapshot rotation script..." >> "$log_file"

# Find the latest timestamped snapshot file in the snapshot directory
latest_snapshot=$(ls -t "$snapshot_directory"xdcchain.xyz_snapshot_*.tar 2>/dev/null | head -1)
if [ -z "$latest_snapshot" ]; then
    echo "$(date +"%Y-%m-%d %H:%M:%S") - Snapshot Rotation Bot - Error: No timestamped snapshot files found in snapshot directory." >> "$log_file"
    exit 1
fi

# Check if the current snapshot file exists
if [ -f "$snapshot_directory$snapshot_file" ]; then
    # Get the size of the current snapshot file
    current_snapshot_size=$(stat -c%s "$snapshot_directory$snapshot_file")
    
    # Get the size of the latest timestamped snapshot file
    latest_snapshot_size=$(stat -c%s "$latest_snapshot")

    # Compare sizes and delete the current snapshot if the latest one is larger
    if [ $latest_snapshot_size -gt $current_snapshot_size ]; then
        rm -f "$snapshot_directory$snapshot_file"
        check_status $? "Deletion of current snapshot file"
    else
        echo "$(date +"%Y-%m-%d %H:%M:%S") - Snapshot Rotation Bot - No larger timestamped snapshot file found. Current snapshot file retained." >> "$log_file"
        exit 0
    fi
fi

# Rename the latest snapshot file to be the new file for download
mv "$latest_snapshot" "$snapshot_directory$snapshot_file"
check_status $? "Renaming of the latest snapshot file to $snapshot_file"

# Log script end time
echo "$(date +"%Y-%m-%d %H:%M:%S") - Snapshot Rotation Bot - Snapshot rotation script completed successfully." >> "$log_file"
