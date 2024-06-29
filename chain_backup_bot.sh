#!/bin/bash

# Set variables
mainnet_directory="/root/XinFin-Node/mainnet"
backup_directory="/root/Chain_Backup/snapshot/"
log_file="/root/Chain_Backup/events.log"
remote_ip="xdcchain.xyz"
remote_destination="/var/www/html/snapshot/"
month_of_log_to_retain=3  # Specify the number of months of log file to retain
max_backup_dir_size_gb=200  # Specify the maximum allowable size for the backup directory in gigabytes

# Function to check command execution status and log errors
check_status() {
    if [ $1 -eq 0 ]; then
        echo "$(date +"%Y-%m-%d %H:%M:%S") - Chain Backup Bot - $2 completed successfully." >> "$log_file"
    else
        echo "$(date +"%Y-%m-%d %H:%M:%S") - Chain Backup Bot - Error: $2 failed. Check the error.log for details." >> "$log_file"
        exit 1
    fi
}

# Function to check and trim log file
trim_log_file() {
    if [ -f "$log_file" ]; then
        temp_log=$(mktemp)
        cutoff_date=$(date -d "-$month_of_log_to_retain months" +"%Y-%m-%d")
        awk -v cutoff="$cutoff_date" '{
            split($1, date, "-");
            log_date = date[1] "-" date[2] "-" date[3];
            if (log_date >= cutoff) print $0;
        }' "$log_file" > "$temp_log"
        mv "$temp_log" "$log_file"
    fi
}

# Function to check and trim backup directory
trim_backup_directory() {
    total_size=$(du -sBG "$backup_directory" | awk '{print $1}' | sed 's/G//')
    while [ "$total_size" -gt "$max_backup_dir_size_gb" ]; do
        # Find and delete the oldest tar file
        oldest_file=$(ls -t "$backup_directory"/*.tar | tail -1)
        if [ -n "$oldest_file" ]; then
            rm -f "$oldest_file"
            echo "$(date +"%Y-%m-%d %H:%M:%S") - Chain Backup Bot - Deleted old backup file: $oldest_file" >> "$log_file"
            total_size=$(du -sBG "$backup_directory" | awk '{print $1}' | sed 's/G//')
        else
            echo "$(date +"%Y-%m-%d %H:%M:%S") - Chain Backup Bot - No old backup files found to delete." >> "$log_file"
            break
        fi
    done
}

# Log script start time
echo "$(date +"%Y-%m-%d %H:%M:%S") - Chain Backup Bot - Starting backup script..." >> "$log_file"

# Trim the log file
trim_log_file

# Check and trim backup directory
trim_backup_directory

# Navigate to the mainnet directory
cd "$mainnet_directory" || exit

# Run docker-down script
sudo bash ./docker-down.sh >> "$log_file" 2>&1
check_status $? "Docker containers shutdown"

# Remove the nodekey file
sudo rm -rf "$mainnet_directory/xdcchain/XDC/nodekey" 2>> "$log_file"
check_status $? "Deletion of nodekey file"

# Generate a date and timestamp
timestamp=$(date +"%Y-%m-%d_%H-%M-%S")

# Create a backup timestamp file
sudo touch "$mainnet_directory/xdcchain/XDC/xdcchain.xyz_snapshot_$timestamp" >> "$log_file" 2>&1
check_status $? "Creation of backup timestamp file"

# Create the tarball
cd "$mainnet_directory"/xdcchain || exit
sudo tar -cvzf "$backup_directory/xdcchain.xyz_snapshot_$timestamp.tar" "XDC" 2>> "$log_file"
check_status $? "Tarball creation"

# Restart Docker container
cd "$mainnet_directory" || exit
sudo bash ./docker-up.sh >> "$log_file" 2>&1
check_status $? "Docker container restart"

# Remove the backup timestamp file
sudo rm -rf "$mainnet_directory/xdcchain/XDC/xdcchain.xyz_snapshot_$timestamp" >> "$log_file" 2>&1
check_status $? "Deletion of backup timestamp file"

# Copy the tarball to the remote server
sudo scp "$backup_directory/xdcchain.xyz_snapshot_$timestamp.tar" "root@$remote_ip:$remote_destination" 2>> "$log_file"
check_status $? "File copy to remote server"

# Change ownership of the tar file on the remote server
sudo ssh root@$remote_ip "chown www-data:www-data $remote_destination/xdcchain.xyz_snapshot_$timestamp.tar" 2>> "$log_file"
check_status $? "Change ownership of tar file on remote server"

# Log script end time
echo "$(date +"%Y-%m-%d %H:%M:%S") - Chain Backup Bot - Backup script completed successfully." >> "$log_file"
