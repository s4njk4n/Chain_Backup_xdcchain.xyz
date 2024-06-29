This repo shows how to regularly take an automated snapshot of the chain database from the XDC Geth Client and move it to a webserver with (semi)-dynamic access gating

We had this running as a regular service on our website at [xdchain.xyz](https://xdchain.xyz) but have noted there is no real demand for provision of a rapid snapshot so will shortly decommission the server and are releasing this information into the wild :) We've already done the legwork so if you want to learn how to backup your own node's chain database or learn how to create a semi-dynamic access gated webserver please read on!

## General Points:
- It is based on there being 2 servers
- We assume you have set up ssh-key authentication for Server 1 to be able to access Server 2
- For access-gating in this instance there are NO personal or private details on the webserver at all so we don't care too much about storing the user_credentials.csv file in plain text. Each username/password combination can almost be considered as a unique access token that has just been split into 2 pieces

## Server 1 - XDC_Client_Server

- Server 1 is running the XDC Client (Contents are in the XDC_Client_Server folder in this repo.
- On Server 1, the XDC Client is located as normal at /root/XinFin-Node/ (We had this one installed as root)
- On Server 1, the Chain_Backup directory is located at /root/Chain_Backup

### In the Chain_Backup directory:
- chain_backup_bot.sh is the script that performs all the steps of shutting down the XDC node, creating a timestamp, creating a tarball containing the current chain database from the client, cleaning up, securely copying the snapshot to the Download server (Server 2)
- events.log is the log file that the bash scripts log events to. Useful to know where it was up to in case it fails for some reason. Also useful for determining how long it takes your server to perform certain tasks. How long does it take to create the tarball? Ho long does it take the copy the tarball to Server 2 given your available bandwidth?
- generate_credentials.sh is used to generate new sets of download credentials along with an expiry date and how many IP addresses they will each be valid for, along with a "sudo wget" command that integrates the users credentials to make distribution easier for the service operator. Each time it runs it copies the current version of user_credentials.csv from the download server to use as its base. (So the version on Server 2 is your source of truth). After generating credentials, it copies it back to Server 2.
- user_credentials.csv is the generated file containing user credentials
- "snapshot" subdirectory - this is where your snapshot tar files are created
- the chain_backup_bot.sh execution is controlled by a root crontab entry of:
```
0 23 * * * /root/Chain_Backup/chain_backup_bot.sh
```

## Server 2 - Snapshot_Download_Server

- Server 2 has Nginx installed to gate access to our snapshot files
- LetsEncrypt has been used to provide SSL/TLS encryption. Some information on NGinx authentication can be found here: https://www.xdc.dev/s4njk4n/ssltls-encryption-for-xdc-node-rpcs-k15
- Htpasswd has been used to provide basic authentication credentials to Nginx. Some information on using htpasswd with Nginx can be found here: https://www.xdc.dev/s4njk4n/controlling-access-to-xdc-node-rpc-endpoints-3en3
- Nginx IP ACL's have also been used. Further information about Nginx IP ACLs can be found via a link in this article: https://www.xdc.dev/s4njk4n/controlling-access-to-xdc-node-rpc-endpoints-3en3
- /var/log/nginx/ contains access.log , error.log , custom.log . These log files are defined in /etc/nginx.nginx.conf
- /etc/nginx/nginx.conf contains nginx configuration including the log files mentioned above
- /etc/nginx/sites-available/default contains Nginx server blocks for default server, SSL server, and http redirect to https server
- SSL server block contains SSL information and location blocks. The location block for the /snapshot directory is restricted by Nginx IP address ACL AND gated by basic authentication. The "#Add-new-IPs-here" line is used by our scripts to locate whereabouts in the file to insert new IP addresses that should be authorised to access the /snapshot location.

### In the Chain_Backup_DL_Server_Control directory:
- The "users" directory contains a plain text file for each username. The filename is the username. Within the file, the first line is the username, the second lines shows how many IP addresses that username is authorised to access the snapshot from, and the lines below that show any IP addresses that have been used and authorised so far by that user.
- The "users/expired" directory is where expired user files are move to once the associated username's credentials have expired.
- access_manager_bot-pause.sh sets a flag that pauses the actions of access_manager_bot.sh
- access_manager_bot-restart.sh deletes the pause flag created by the script above. This effectively restarts the looping an actions of the access_manger_bot.sh
- access_manager_bot-start_looping.sh starts a loop that keeps running the access_manager_bot.sh script every few seconds
- access_manager_bot.sh is our user management script that controls user management/expiry and dynamic access gating to the snapshot
- events.log is the log file our scripts log events to. Useful fo troubleshooting if any issues occur you can figure out where things were up to
- last_expiry_check is a plain text file containing the date that the last expiry check was run on users
- snapshot_rotation_bot.sh is the script that switches out the old snapshot for the new one (if one exists) when it is run
- user_credentials.csv is our source of truth for user credentials. Even the script on our other server that generates user credentials uses this file as its base to work from when adding more user credentials
- working_custom.log is one of our working files for dynamic user access gating
- the access managemen and timing of snapshot switching is controlled by the following entries in the root crontab:
```
@reboot /bin/bash /root/Chain_Backup_DL_Server_Control/access_manager_bot-start_looping.sh
0 23 * * * /bin/bash /root/Chain_Backup_DL_Server_Control/snapshot_rotation_bot.sh
```

---

Good luck and I hope this script comes in useful for somebody whether it be how to identify and manage the steps to backup an XDC Geth Node, or alternately how to uase log-based (semi)-dynamic access gating to webserver resources.

- @s4njk4n
