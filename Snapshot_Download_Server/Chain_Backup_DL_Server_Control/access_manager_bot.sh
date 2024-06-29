#!/bin/bash

# Variables
credentials_file="/root/Chain_Backup_DL_Server_Control/user_credentials.csv"
events_log="/root/Chain_Backup_DL_Server_Control/events.log"
user_dir="/root/Chain_Backup_DL_Server_Control/users"
expired_user_dir="/root/Chain_Backup_DL_Server_Control/users/expired"
working_log="/root/Chain_Backup_DL_Server_Control/working_custom.log"
custom_log="/var/log/nginx/custom.log"
nginx_config="/etc/nginx/sites-enabled/default"
expiry_check_file="/root/Chain_Backup_DL_Server_Control/last_expiry_check"
nginx_modified=0  # Variable to track if nginx config is modified

# Function for logging events
log_event() {
    local message="$1"
    echo "$(date +"%Y-%m-%d %H:%M:%S") - Access Manager Bot - $message" >> "$events_log"
}

# Function for error handling
log_error() {
    local message="$1"
    echo "$(date +"%Y-%m-%d %H:%M:%S") - Access Manager Bot - Error: $message" >> "$events_log"
    exit 1
}

# Ensure credentials file exists
if [ ! -f "$credentials_file" ]; then
    log_error "Credentials file not found at $credentials_file"
fi

# Ensure expired user directory exists
mkdir -p "$expired_user_dir" || log_error "Failed to create expired user directory at $expired_user_dir"

# Check if we need to run the expiry process
current_date=$(date +%Y-%m-%d)
if [ ! -f "$expiry_check_file" ] || [ "$(cat "$expiry_check_file")" != "$current_date" ]; then
    echo "$current_date" > "$expiry_check_file"

    # Check for expired users
    awk -F',' '$6 == "Active"' "$credentials_file" | while IFS=',' read -r username password created_date validity_days ip_limit status url; do
        expiration_date=$(date -d "$created_date + $validity_days days" +%Y-%m-%d)
        if [[ "$expiration_date" < "$current_date" ]]; then
            user_file="$user_dir/$username"
            
            # Remove IP addresses from nginx ACL
            if [ -f "$user_file" ]; then
                tail -n +3 "$user_file" | while read -r ip_address; do
                    sed -i "/allow $ip_address;/d" "$nginx_config"
                    log_event "Removed IP address $ip_address from nginx ACL for expired user $username"
                    nginx_modified=1
                done

                # Remove user credentials from .htpasswd
                htpasswd -D /etc/nginx/.htpasswd "$username"
                log_event "Removed credentials for expired user $username from .htpasswd"

                # Move user file to expired directory
                mv "$user_file" "$expired_user_dir"
                log_event "Moved file for expired user $username to $expired_user_dir"
            fi

            # Update user status to Expired in credentials file
#            sed -i "s/$username,$password,$created_date,$validity_days,$ip_limit,Active,$url/$username,$password,$created_date,$validity_days,$ip_limit,Expired,$url/" "$credentials_file"
             awk -F',' -v OFS=',' '$1 == "'"$username"'" && $6 == "Active" {$6="Expired"} 1' "$credentials_file" > temp && mv temp "$credentials_file"

            log_event "Updated status to Expired for user $username in credentials file"
        fi
    done
fi

# Copy custom log file to working directory
cp "$custom_log" "$working_log" || log_error "Failed to copy custom log file to working directory"

# Extract active usernames and their IP limits from the credentials file
active_usernames=$(tail -n +2 "$credentials_file" | grep ',Active,' | cut -d',' -f1)
tail -n +2 "$credentials_file" | grep ',Active,' | while IFS=',' read -r username password created_date validity_days ip_limit status url; do
    user_file="$user_dir/$username"
    
    # Check if user file already exists
    if [ ! -f "$user_file" ]; then
        # Create user file with username and IP limit
        {
            echo "$username"
            echo "$ip_limit"
        } > "$user_file"
        
        log_event "Created file for user $username with IP limit $ip_limit"
    fi
done

# Ensure working log file exists
if [ ! -f "$working_log" ]; then
    log_error "Working log file not found at $working_log"
fi

# Process lines in the working log file for " 200 " status
while IFS= read -r line; do
    # Check if the line contains " 200 "
    if [[ "$line" =~ " 200 " ]]; then
        # Extract the username from the line
        username=$(echo "$line" | grep -oP '(?<=\?authorisedip=)[a-zA-Z0-9]{14}')
        
        # Proceed only if a username was found
        if [ -n "$username" ]; then
            # Check if the username is active
            if echo "$active_usernames" | grep -q "$username"; then
                user_file="$user_dir/$username"
                
                # Extract the IP address from the line
                ip_address=$(echo "$line" | awk '{print $1}')
                
                # Check if the IP address is already in the user's file
                if ! grep -q "^$ip_address$" "$user_file"; then
                    # Add the IP address to the user's file
                    echo "$ip_address" >> "$user_file"
                    log_event "Added IP address $ip_address to file for user $username"
                fi
            fi
        fi
    fi
done < "$working_log"

# Process lines in the working log file for " 403 " status
while IFS= read -r line; do
    # Check if the line contains " 403 "
    if [[ "$line" =~ " 403 " ]]; then
        # Extract the username from the line
        username=$(echo "$line" | grep -oP '(?<=\?authorisedip=)[a-zA-Z0-9]{14}')
        
        # Proceed only if a username was found
        if [ -n "$username" ]; then
            # Check if the username is active
            if echo "$active_usernames" | grep -q "$username"; then
                user_file="$user_dir/$username"
                
                # Extract the IP address from the line
                ip_address=$(echo "$line" | awk '{print $1}')
                
                # Check the number of IP addresses in the user's file

                ip_count=$(tail -n +3 "$user_file" | wc -l)
                ip_limit=$(sed -n '2p' "$user_file")

                # If the number of IPs is less than the limit and the IP address is not already in the file
                if [ "$ip_count" -lt "$ip_limit" ] && ! grep -q "^$ip_address$" "$user_file"; then
                    # Add the IP address to the user's file
                    echo "$ip_address" >> "$user_file"
                    log_event "Added IP address $ip_address to file for user $username (403 handling)"
                fi
            fi
        fi
    fi
done < "$working_log"

# Process user files to update nginx ACL
for user_file in "$user_dir"/*; do
    if [ -f "$user_file" ] && [ "$(basename "$user_file")" != "manual_access" ]; then
        username=$(head -n 1 "$user_file")
        ip_limit=$(sed -n '2p' "$user_file")
        
        # Ensure each IP address in the user's file is allowed in nginx ACL
        while read -r ip_address; do
            if ! grep -q "allow $ip_address;" "$nginx_config"; then
                # Add IP address to nginx ACL
                sed -i "/#Add-new-IPs-here/a \\            allow $ip_address;" "$nginx_config"
                log_event "Added IP address $ip_address to nginx ACL for user $username"
                nginx_modified=1
            fi
        done < <(tail -n +3 "$user_file")  # Skip first two lines (username and IP limit)
    fi
done

# Reload nginx to apply changes if the config file was modified
if [ $nginx_modified -eq 1 ]; then
    if sudo systemctl reload nginx; then
        log_event "Successfully reloaded nginx"
    else
        log_error "Failed to reload nginx"
    fi
fi
