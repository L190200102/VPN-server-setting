#!/bin/bash

# =================================================================
#               Initial Server Setup Automation Script
# =================================================================
# Features:
# 1. Updates system packages and installs essential tools.
# 2. Creates and configures a 2GB swap file.
# 3. Flushes firewall rules and saves the configuration.
# 4. Automatically updates a Cloudflare DNS A record.
# 5. Installs Hiddify.
#
# Usage:
# 1. Upload this script to your server or run it directly from a URL.
# 2. Grant execution permission (e.g., chmod +x server_setup.sh).
# 3. Run the script with your Cloudflare API Token and Domain Name as arguments.
#    Example: ./server_setup.sh "YOUR_API_TOKEN" "your.domain.name"
# =================================================================

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Script Arguments ---
# This script requires two arguments to be passed during execution:
# 1. Cloudflare API Token
# 2. Domain Name for the A record update
# -------------------------

if [ "$#" -ne 2 ]; then
    echo "Error: Invalid number of arguments."
    echo "Usage: $0 <CLOUDFLARE_API_TOKEN> <DOMAIN_NAME>"
    exit 1
fi

API_TOKEN="$1"
DOMAIN_NAME="$2"


echo "=================================================="
echo "Starting the initial server setup."
echo "=================================================="

# Step 1: System Update and Package Installation
echo "--> 1/5: Updating system and installing essential packages..."
# Set DEBIAN_FRONTEND to noninteractive to auto-confirm prompts during package installation.
export DEBIAN_FRONTEND=noninteractive
sudo apt update && sudo apt -y upgrade
sudo apt install -y nano vnstat curl jq netfilter-persistent iptables-persistent
echo "--> Package installation complete."
echo "=================================================="

# Step 2: Swap File Creation
echo "--> 2/5: Creating and enabling a 2GB swap file..."
if [ -f /swapfile ]; then
    echo "Swap file already exists. Skipping creation."
else
    sudo fallocate -l 2G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    # Add swap to /etc/fstab to make it permanent
    echo '/swapfile swap swap defaults 0 0' | sudo tee -a /etc/fstab
fi
# Adjust swappiness to reduce swap usage on idle systems
echo "vm.swappiness = 20" | sudo tee /etc/sysctl.d/99-swappiness.conf
sudo sysctl -p /etc/sysctl.d/99-swappiness.conf
echo "--> Swap file setup complete. Current memory status:"
free -h
echo "=================================================="

# Step 3: Firewall (iptables) Configuration
echo "--> 3/5: Flushing firewall rules..."
echo "!!! ATTENTION !!!"
echo "You might be asked to save the current firewall rules for netfilter-persistent."
echo "If you don't have a custom configuration, you can proceed by pressing 'Enter' for the defaults."
read -p "Press Enter to continue when you are ready..."

sudo iptables -F
sudo iptables -X
sudo netfilter-persistent save
sudo netfilter-persistent reload
echo "--> Firewall rules have been flushed."
echo "=================================================="

# Step 4: Cloudflare DNS Update
echo "--> 4/5: Updating Cloudflare DNS record with the current server IP..."
CURRENT_IP=$(curl -s https://api.ipify.org)
if [ -z "$CURRENT_IP" ]; then
    echo "Failed to retrieve the current server IP address. Skipping DNS update."
else
    # Extract the root domain to find the Zone ID (e.g., from sub.example.com to example.com)
    ZONE_NAME=$(expr match "$DOMAIN_NAME" '.*\.\(.*\..*\)')
    ZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$ZONE_NAME" -H "Authorization: Bearer $API_TOKEN" -H "Content-Type:application/json" | jq -r '.result[0].id')

    if [ "$ZONE_ID" = "null" ] || [ -z "$ZONE_ID" ]; then
        echo "Could not find Zone ID on Cloudflare. Please check your domain name and API token."
    else
        RECORD_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?type=A&name=$DOMAIN_NAME" -H "Authorization: Bearer $API_TOKEN" -H "Content-Type:application/json" | jq -r '.result[0].id')

        if [ "$RECORD_ID" = "null" ] || [ -z "$RECORD_ID" ]; then
            echo "No existing A record found. Creating a new A record for '$DOMAIN_NAME'..."
            curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
                 -H "Authorization: Bearer $API_TOKEN" \
                 -H "Content-Type: application/json" \
                 --data "{\"type\":\"A\",\"name\":\"$DOMAIN_NAME\",\"content\":\"$CURRENT_IP\",\"proxied\":false,\"ttl\":1}" | jq
        else
            echo "Updating existing A record to IP: $CURRENT_IP..."
            curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" \
                 -H "Authorization: Bearer $API_TOKEN" \
                 -H "Content-Type: application/json" \
                 --data "{\"type\":\"A\",\"name\":\"$DOMAIN_NAME\",\"content\":\"$CURRENT_IP\",\"proxied\":false,\"ttl\":1}" | jq
        fi
        echo "--> Cloudflare DNS update complete."
    fi
fi
echo "=================================================="

# Step 5: Hiddify Installation
echo "--> 5/5: Starting Hiddify installation..."
echo "!!! ATTENTION !!!"
echo "The Hiddify installation script will now be executed."
echo "You will need to respond to its prompts directly during the installation process."
read -p "Press Enter to begin the Hiddify installation..."

bash <(curl https://i.hiddify.com/custom)

echo "=================================================="
echo "All server setup tasks are complete."
echo "=================================================="

