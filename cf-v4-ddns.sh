#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# Automatically update your CloudFlare DNS record to the IP, Dynamic DNS
# Uses Cloudflare API Token (with Zone:DNS:Edit permissions) for enhanced security

# API token, create at https://dash.cloudflare.com/profile/api-tokens
# Create a token with Zone:DNS:Edit permissions for specific zones
CFTOKEN=

# Zone ID, found in the Cloudflare dashboard overview page
CFZONE_ID=

# Hostname or subdomain to update, eg: homeserver or homeserver.example.com
CFRECORD_NAME=

# Comment for the DNS record (optional)
CFRECORD_COMMENT=""

# Record type, A(IPv4)|AAAA(IPv6), default IPv4
CFRECORD_TYPE=A

# Cloudflare TTL for record, between 120 and 86400 seconds
CFTTL=60

# Ignore local file, update ip anyway
FORCE=false

# Enable debug mode (set to true for verbose output)
DEBUG=false

# get parameter
while getopts k:i:h:t:c:f:d: opts; do
  case ${opts} in
    k) CFTOKEN=${OPTARG} ;;
    i) CFZONE_ID=${OPTARG} ;;
    h) CFRECORD_NAME=${OPTARG} ;;
    t) CFRECORD_TYPE=${OPTARG} ;;
    c) CFRECORD_COMMENT=${OPTARG} ;;
    f) FORCE=${OPTARG} ;;
    d) DEBUG=${OPTARG} ;;
  esac
done

# Debug function
debug() {
  if [ "$DEBUG" = true ]; then
    echo "[DEBUG] $1"
  fi
}

# If required settings are missing just exit
if [ "$CFTOKEN" = "" ]; then
  echo "Missing API token, create at: https://dash.cloudflare.com/profile/api-tokens"
  echo "You need a token with Zone:DNS:Edit permissions for your zone"
  exit 2
fi
if [ "$CFZONE_ID" = "" ]; then
  echo "Missing Zone ID, find it in the Cloudflare dashboard overview page"
  exit 2
fi
if [ "$CFRECORD_NAME" = "" ]; then 
  echo "Missing hostname, what host do you want to update?"
  exit 2
fi

# Determine IP address site based on record type
if [ "$CFRECORD_TYPE" = "A" ]; then
  WANIPSITE="https://api.ipify.org/"
elif [ "$CFRECORD_TYPE" = "AAAA" ]; then
  WANIPSITE="https://api6.ipify.org/"
else
  echo "$CFRECORD_TYPE specified is invalid, CFRECORD_TYPE can only be A(for IPv4)|AAAA(for IPv6)"
  exit 2
fi

# Get current WAN IP with better error handling
debug "Getting current IP from $WANIPSITE"
WAN_IP=$(curl -s -f ${WANIPSITE})
if [ -z "$WAN_IP" ]; then
  echo "Error: Failed to get current IP address"
  exit 1
fi
debug "Current IP: $WAN_IP"

# Check for previously saved IP
WAN_IP_FILE=$HOME/.cf-wan_ip_$CFRECORD_NAME.txt
if [ -f $WAN_IP_FILE ]; then
  OLD_WAN_IP=$(cat $WAN_IP_FILE)
  debug "Old IP: $OLD_WAN_IP"
else
  debug "No previous IP file found. Creating a new one."
  OLD_WAN_IP=""
fi

# If WAN IP is unchanged and not forced, exit here
if [ "$WAN_IP" = "$OLD_WAN_IP" ] && [ "$FORCE" = false ]; then
  echo "WAN IP Unchanged, to update anyway use flag -f true"
  exit 0
fi

# Get zone details to verify token works
debug "Verifying zone access with token"
ZONE_DETAILS=$(curl -s -f -X GET "https://api.cloudflare.com/client/v4/zones/$CFZONE_ID" \
  -H "Authorization: Bearer $CFTOKEN" \
  -H "Content-Type: application/json")

if [ "$(echo $ZONE_DETAILS | grep -c "\"success\":true")" = "0" ]; then
  echo "Error: Failed to access zone. Check your Zone ID and API Token permissions."
  debug "Zone API response: $ZONE_DETAILS"
  exit 1
fi

# Extract zone name from zone details
ZONE_NAME=$(echo $ZONE_DETAILS | grep -Eo '"name":"[^"]*' | head -1 | sed 's/"name":"//')
debug "Zone name: $ZONE_NAME"

# Determine if CFRECORD_NAME is a full domain or just subdomain
if [[ "$CFRECORD_NAME" == *"."* && "$CFRECORD_NAME" != *"$ZONE_NAME"* ]]; then
  echo "Warning: Record name contains dots but doesn't include zone name. Assuming it's a full domain."
  FULL_RECORD_NAME="$CFRECORD_NAME"
elif [[ "$CFRECORD_NAME" == *"$ZONE_NAME"* ]]; then
  debug "Record name includes zone name, using as is"
  FULL_RECORD_NAME="$CFRECORD_NAME"
else
  debug "Record name is a subdomain, appending zone name"
  FULL_RECORD_NAME="${CFRECORD_NAME}.${ZONE_NAME}"
fi
debug "Full record name: $FULL_RECORD_NAME"

# Look up the DNS record
debug "Looking up DNS record"
RECORD_DETAILS=$(curl -s -f -X GET "https://api.cloudflare.com/client/v4/zones/$CFZONE_ID/dns_records?name=$FULL_RECORD_NAME&type=$CFRECORD_TYPE" \
  -H "Authorization: Bearer $CFTOKEN" \
  -H "Content-Type: application/json")

if [ "$(echo $RECORD_DETAILS | grep -c "\"success\":true")" = "0" ]; then
  echo "Error: Failed to lookup DNS record."
  debug "Record lookup response: $RECORD_DETAILS"
  exit 1
fi

# Extract the record ID
CFRECORD_ID=$(echo $RECORD_DETAILS | grep -Eo '"id":"[^"]*' | head -1 | sed 's/"id":"//')

if [ -z "$CFRECORD_ID" ]; then
  echo "Error: DNS record not found. Please create the record first in Cloudflare dashboard."
  exit 1
fi
debug "Record ID: $CFRECORD_ID"

# Save the ID for future use
debug "Saving record ID for future use"
echo "$CFRECORD_ID" > $HOME/.cf-id_$CFRECORD_NAME.txt
echo "$CFZONE_ID" >> $HOME/.cf-id_$CFRECORD_NAME.txt

# Update the DNS record
echo "Updating DNS record '$FULL_RECORD_NAME' to IP: $WAN_IP"

# Build JSON data based on whether comment is provided
if [ -n "$CFRECORD_COMMENT" ]; then
    JSON_DATA="{\"type\":\"$CFRECORD_TYPE\",\"name\":\"$FULL_RECORD_NAME\",\"content\":\"$WAN_IP\",\"ttl\":$CFTTL,\"comment\":\"$CFRECORD_COMMENT\"}"
else
    JSON_DATA="{\"type\":\"$CFRECORD_TYPE\",\"name\":\"$FULL_RECORD_NAME\",\"content\":\"$WAN_IP\",\"ttl\":$CFTTL}"
fi
debug "Request JSON: $JSON_DATA"

RESPONSE=$(curl -s -f -X PUT "https://api.cloudflare.com/client/v4/zones/$CFZONE_ID/dns_records/$CFRECORD_ID" \
  -H "Authorization: Bearer $CFTOKEN" \
  -H "Content-Type: application/json" \
  --data "$JSON_DATA")

if [ "$(echo $RESPONSE | grep -c "\"success\":true")" = "1" ]; then
  echo "DNS record updated successfully!"
  echo "$WAN_IP" > $WAN_IP_FILE
  exit 0
else
  echo "Error: Failed to update DNS record."
  debug "Update response: $RESPONSE"
  exit 1
fi
