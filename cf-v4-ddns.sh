#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# Automatically update your CloudFlare DNS record to the IP, Dynamic DNS
# Uses Cloudflare API Token (with Zone:DNS:Edit permissions) for enhanced security

# Place at:
# curl https://raw.githubusercontent.com/aipeach/cloudflare-api-v4-ddns/dev/cf-v4-ddns.sh > /usr/local/bin/cf-ddns.sh && chmod +x /usr/local/bin/cf-ddns.sh
# run `crontab -e` and add next line:
# */1 * * * * /usr/local/bin/cf-ddns.sh >/dev/null 2>&1
# or you need log:
# */1 * * * * /usr/local/bin/cf-ddns.sh >> /var/log/cf-ddns.log 2>&1


# Usage:
# cf-ddns.sh -k cloudflare-api-token \
#            -i zone-id \              # zone ID (required with API token)
#            -h host.example.com \     # fqdn or subdomain of the record you want to update
#            -t A|AAAA \               # specify ipv4/ipv6, default: ipv4
#            -c "comment text"         # optional comment for the DNS record

# Optional flags:
#            -f false|true \           # force dns update, disregard local stored ip

# default config

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

WANIPSITE="http://ipv4.icanhazip.com"

# Site to retrieve WAN ip, other examples are: bot.whatismyipaddress.com, https://api.ipify.org/ ...
if [ "$CFRECORD_TYPE" = "A" ]; then
  :
elif [ "$CFRECORD_TYPE" = "AAAA" ]; then
  WANIPSITE="http://ipv6.icanhazip.com"
else
  echo "$CFRECORD_TYPE specified is invalid, CFRECORD_TYPE can only be A(for IPv4)|AAAA(for IPv6)"
  exit 2
fi

# get parameter
while getopts k:i:h:t:c:f: opts; do
  case ${opts} in
    k) CFTOKEN=${OPTARG} ;;
    i) CFZONE_ID=${OPTARG} ;;
    h) CFRECORD_NAME=${OPTARG} ;;
    t) CFRECORD_TYPE=${OPTARG} ;;
    c) CFRECORD_COMMENT=${OPTARG} ;;
    f) FORCE=${OPTARG} ;;
  esac
done

# If required settings are missing just exit
if [ "$CFTOKEN" = "" ]; then
  echo "Missing API token, create at: https://dash.cloudflare.com/profile/api-tokens"
  echo "You need a token with Zone:DNS:Edit permissions for your zone"
  echo "and save in ${0} or using the -k flag"
  exit 2
fi
if [ "$CFZONE_ID" = "" ]; then
  echo "Missing Zone ID, find it in the Cloudflare dashboard overview page"
  echo "and save in ${0} or using the -i flag"
  exit 2
fi
if [ "$CFRECORD_NAME" = "" ]; then 
  echo "Missing hostname, what host do you want to update?"
  echo "save in ${0} or using the -h flag"
  exit 2
fi

# Get current and old WAN ip
WAN_IP=`curl -s ${WANIPSITE}`
WAN_IP_FILE=$HOME/.cf-wan_ip_$CFRECORD_NAME.txt
if [ -f $WAN_IP_FILE ]; then
  OLD_WAN_IP=`cat $WAN_IP_FILE`
else
  echo "No file, need IP"
  OLD_WAN_IP=""
fi

# If WAN IP is unchanged an not -f flag, exit here
if [ "$WAN_IP" = "$OLD_WAN_IP" ] && [ "$FORCE" = false ]; then
  echo "WAN IP Unchanged, to update anyway use flag -f true"
  exit 0
fi

# Get record_identifier
ID_FILE=$HOME/.cf-id_$CFRECORD_NAME.txt
if [ -f $ID_FILE ] && [ $(wc -l $ID_FILE | cut -d " " -f 1) == 2 ] \
  && [ "$(sed -n '2,1p' "$ID_FILE")" == "$CFZONE_ID" ]; then
    CFRECORD_ID=$(sed -n '1,1p' "$ID_FILE")
else
    echo "Updating record_identifier"
    # First try with the assumption CFRECORD_NAME is a fully qualified domain name
    CFRECORD_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CFZONE_ID/dns_records?name=$CFRECORD_NAME" -H "Authorization: Bearer $CFTOKEN" -H "Content-Type: application/json" | grep -Eo '"id":"[^"]*'|sed 's/"id":"//' | head -1 )
    
    # If not found, try getting zone name and appending record name to it
    if [ -z "$CFRECORD_ID" ]; then
        ZONE_NAME=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CFZONE_ID" -H "Authorization: Bearer $CFTOKEN" -H "Content-Type: application/json" | grep -Eo '"name":"[^"]*'|sed 's/"name":"//' | head -1 )
        if [ -n "$ZONE_NAME" ]; then
            FQDN_RECORD="$CFRECORD_NAME.$ZONE_NAME"
            echo "Trying with FQDN: $FQDN_RECORD"
            CFRECORD_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CFZONE_ID/dns_records?name=$FQDN_RECORD" -H "Authorization: Bearer $CFTOKEN" -H "Content-Type: application/json" | grep -Eo '"id":"[^"]*'|sed 's/"id":"//' | head -1 )
            
            # If found, update CFRECORD_NAME to FQDN
            if [ -n "$CFRECORD_ID" ]; then
                CFRECORD_NAME=$FQDN_RECORD
            fi
        fi
    fi
    
    # If still not found, exit
    if [ -z "$CFRECORD_ID" ]; then
        echo "Error: Could not find DNS record with name $CFRECORD_NAME in zone $CFZONE_ID"
        exit 1
    fi
    
    echo "$CFRECORD_ID" > $ID_FILE
    echo "$CFZONE_ID" >> $ID_FILE
fi

# If WAN is changed, update cloudflare
echo "Updating DNS to $WAN_IP"

# Build JSON data based on whether comment is provided
if [ -n "$CFRECORD_COMMENT" ]; then
    JSON_DATA="{\"type\":\"$CFRECORD_TYPE\",\"name\":\"$CFRECORD_NAME\",\"content\":\"$WAN_IP\",\"ttl\":$CFTTL,\"comment\":\"$CFRECORD_COMMENT\"}"
else
    JSON_DATA="{\"type\":\"$CFRECORD_TYPE\",\"name\":\"$CFRECORD_NAME\",\"content\":\"$WAN_IP\",\"ttl\":$CFTTL}"
fi

RESPONSE=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$CFZONE_ID/dns_records/$CFRECORD_ID" \
  -H "Authorization: Bearer $CFTOKEN" \
  -H "Content-Type: application/json" \
  --data "$JSON_DATA")

if [ "$RESPONSE" != "${RESPONSE%success*}" ] && [ "$(echo $RESPONSE | grep "\"success\":true")" != "" ]; then
  echo "Updated succesfuly!"
  echo $WAN_IP > $WAN_IP_FILE
  exit
else
  echo 'Something went wrong :('
  echo "Response: $RESPONSE"
  exit 1
fi
