#!/bin/bash

# Variables
remote_user="root"                # SSH username for remote VPS
remote_VPS="xdcchain.xyz"          # IP address or domain of remote VPS
REMOTE_CSV_FILE="/root/Chain_Backup_DL_Server_Control/user_credentials.csv"  # Path to the CSV file on remote VPS
LOCAL_CSV_FILE="/home/anon/Chain_Backup/user_credentials.csv"  # Path to the CSV file on local machine
LOG_FILE="events.log"               # Path to the log file

# Function to generate random alphanumeric string
generate_random_string() {
    cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w "${1:-14}" | head -n 1
}

# Function for error handling and logging
log_error() {
    local message="$1"
    echo "$(date +"%Y-%m-%d %H:%M:%S") - Error: $message" >> "$LOG_FILE"
    exit 1
}

# Function for logging script events
log_event() {
    local event="$1"
    echo "$(date +"%Y-%m-%d %H:%M:%S") - Credential Generation Script - $event" >> "$LOG_FILE"
}

# Log script start time
log_event "Starting script..."

# Copy the CSV file from remote VPS to local machine
scp "$remote_user@$remote_VPS:$REMOTE_CSV_FILE" "$LOCAL_CSV_FILE" || log_error "Failed to copy CSV file from remote VPS"

# Prompt for user input
read -p "How many username/passwords do you want to create on this execution of the script? " count
read -p "How long will these new username/passwords be valid for (in days)? " validity_days
read -p "How many IP addresses should each username/password being created on this execution be allowed to download the snapshot file to? " ip_limit

# Loop to generate credentials
for ((i=1; i<=$count; i++)); do
    username=$(generate_random_string)
    password=$(generate_random_string)
    expiry_date=$(date -d "+$validity_days days" +%Y-%m-%d)

    # Construct the wget command for the 7th field
    wget_command="sudo wget -c -O xdcchain.xyz_snapshot.tar \"https://$username:$password@$remote_VPS/snapshot/xdcchain.xyz_snapshot.tar?authorisedip=$username\""
    
    # Add credentials to CSV file
    echo "$username,$password,$(date +%Y-%m-%d),$validity_days,$ip_limit,Active,$wget_command" >> "$LOCAL_CSV_FILE" || log_error "Failed to write to CSV file"
    


    
    # Add credentials to CSV file
#    echo "$username,$password,$(date +%Y-%m-%d),$validity_days,$ip_limit,Active,https://$username:$password@$remote_VPS/snapshot/xdcchain.xyz_snapshot.tar?authorisedip=$username" >> "$LOCAL_CSV_FILE" || log_error "Failed to write to CSV file"
    
    # Log username added
    log_event "Added username: $username"
    
    # SSH to remote VPS and add credentials to htpasswd
    ssh "$remote_user"@"$remote_VPS" "sudo htpasswd -b /etc/nginx/.htpasswd $username $password" || log_error "Failed to add username/password to htpasswd on remote VPS"
done

# Copy the CSV file to remote VPS
scp "$LOCAL_CSV_FILE" "$remote_user@$remote_VPS:$REMOTE_CSV_FILE" || log_error "Failed to copy CSV file to remote VPS"

# Log script end time
log_event "Script completed successfully."
