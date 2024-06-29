#!/bin/bash

while [ ! -f "/tmp/access_manager_bot_stop_signal" ]; do
    bash /root/Chain_Backup_DL_Server_Control/access_manager_bot.sh
    sleep 5
done
