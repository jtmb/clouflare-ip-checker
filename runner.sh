#!/bin/bash
# Read the docker environment variables and pass them as arguments
EMAIL="$EMAIL"               # Email for Cloudflare authentication
API_KEY="$API_KEY"           # Cloudflare API Key
ZONE_ID="$ZONE_ID"           # Cloudflare Zone ID
WEBHOOK_URL="$WEBHOOK_URL"   # Discord Webhook URL
PUBLIC_IP=$(curl -s https://api.ipify.org)   # Get the current public IP
DNS_RECORDS=($DNS_RECORDS)   # Array of DNS records to update
REQUEST_TIME_SECONDS="$REQUEST_TIME_SECONDS" # Request time interval in seconds
repo_url="https://github.com/jtmb/clouflare-ip-checker"

# Define colors and formatting codes
GREEN="\033[1;32m"
RED="\033[1;31m"
CYAN="\033[1;36m"
BOLD="\033[1m"
WHITE="\033[1;37m"
YELLOW="\033[38;5;220m"
RESET="\033[0m"

echo -e "${BOLD}${GREEN}CLOUDFLARE IP CHECKER RUNNING!${RESET}"
echo -e "${WHITE}${BOLD}Repository: ${CYAN}${repo_url}${RESET}"


while true; do
  PUBLIC_IP=$(curl -s https://api.ipify.org)   # Get the current public IP
  OLD_PUBLIC_IP="$PUBLIC_IP"
  IP_CHANGED=false
  RECORD_UPDATED=false

  # Remove duplicate entries and keep only records with current public IP
  unique_records=()
  for record in "${DNS_RECORDS[@]}"; do
    if ! echo "${unique_records[@]}" | grep -q "$record"; then
      unique_records+=("$record")
    fi
  done

  # Loop through the unique DNS records
  for record in "${unique_records[@]}"; do
    name=$(echo "$record" | cut -d'/' -f1)
    type=$(echo "$record" | cut -d'/' -f2)

    # Retrieve DNS record information from Cloudflare API
    response=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?type=$type&name=$name" \
      -H "X-Auth-Email: $EMAIL" \
      -H "X-Auth-Key: $API_KEY" \
      -H "Content-Type: application/json")

    success=$(echo "$response" | jq -r '.success')

    if [ "$success" == "true" ]; then
      record_id=$(echo "$response" | jq -r '.result[0].id')
      record_ip=$(echo "$response" | jq -r '.result[0].content')
      if [ "$record_id" != "null" ]; then
        if [ "$record_ip" != "$PUBLIC_IP" ]; then
          # Update existing record
          update_response=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$record_id" \
            -H "X-Auth-Email: $EMAIL" \
            -H "X-Auth-Key: $API_KEY" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"$type\",\"name\":\"$name\",\"content\":\"$PUBLIC_IP\",\"proxied\":true}")

          echo ------------------------------------------------------------------
          echo -e "${RED}${BOLD}DNS Record ${GREEN}$name ($type)${RESET} has changed. ${YELLOW}${BOLD}Updating ...${RESET}"
          echo ----------------------------------------------------------------------
          echo ------------------------------------------------------------------
          echo -e "${WHITE}${BOLD}Updated DNS record ${GREEN}$name ($type)${RESET} with new IP: ${WHITE}${BOLD} $PUBLIC_IP${RESET}"
          echo ----------------------------------------------------------------------
          RECORD_UPDATED=true
        else
          echo ------------------------------------------------------------------
          echo -e "${WHITE}${BOLD}DNS record ${GREEN}$name ($type)${RESET} already up to date with IP: ${WHITE}${BOLD}$PUBLIC_IP${RESET}"
          echo ----------------------------------------------------------------------
        fi
      else
        # Record doesn't exist, add new record
        add_response=$(curl -s -o /dev/null -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
          -H "X-Auth-Email: $EMAIL" \
          -H "X-Auth-Key: $API_KEY" \
          -H "Content-Type: application/json" \
          --data "{\"type\":\"$type\",\"name\":\"$name\",\"content\":\"$PUBLIC_IP\",\"ttl\":120,\"proxied\":true}")
        
          echo ------------------------------------------------------------------
          echo -e "${WHITE}${BOLD}New Record Detected ! ${GREEN}$name ($type)${RESET} has been ${YELLOW}${BOLD}added to Cloudflare ${RESET} with IP: ${WHITE}${BOLD}$PUBLIC_IP${RESET}"
          echo ----------------------------------------------------------------------
        RECORD_UPDATED=true
      fi
    else
      errors=$(echo "$response" | jq -r '.errors[].message')
          echo "----------------------------------------------------------------------"
          echo -e "${RED}${BOLD}Error ${RESET} checking DNS record ${BOLD}$name${RESET} (${BOLD}$type${RESET}): ${YELLOW}$errors${RESET}"
          echo "----------------------------------------------------------------------"
    fi
  done

  # Send Discord webhook notification if IP changed or records updated
  if [ "$IP_CHANGED" == true ] || [ "$RECORD_UPDATED" == true ]; then
    MESSAGE="DNS Records Update Notification:\n"
    
    if [ "$IP_CHANGED" == true ]; then
      MESSAGE+="Your Public IP has changed to $PUBLIC_IP.\n"
    fi
    
    if [ "$RECORD_UPDATED" == true ]; then
      MESSAGE+="Cloudflare DNS Records have been updated:\n"
      
      if [ ${#added_records[@]} -gt 0 ]; then
        MESSAGE+="\nAdded Records:\n"
        for record in "${added_records[@]}"; do
          MESSAGE+="- $record\n"
        done
      fi
      
      if [ ${#changed_records[@]} -gt 0 ]; then
        MESSAGE+="\nChanged Records:\n"
        for record in "${changed_records[@]}"; do
          MESSAGE+="- $record\n"
        done
      fi
    fi

    curl -s -H "Content-Type: application/json" -X POST -d "{\"content\":\"$MESSAGE\"}" "$WEBHOOK_URL"

    echo ------------------------------------------------------------------
    echo -e "${WHITE}${BOLD}Discord Message${RESET} Sent with added and changed records."
    echo ----------------------------------------------------------------------
  fi


  sleep $REQUEST_TIME_SECONDS  # Sleep for the specified time interval before the next loop
done
