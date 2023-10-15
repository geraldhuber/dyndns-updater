#!/bin/bash

# Load configuration from the file and store it in an associative array
declare -A CONFIG
while IFS= read -r line; do
    key=$(echo "$line" | cut -d'=' -f 1 | awk '{gsub(/^ +| +$/,"")}1')
    value=$(echo "$line" | cut -d'=' -f 2 | awk '{gsub(/^ +| +$/,"")}1')
    CONFIG["$key"]="$value"
done < /etc/dyndns-updater.conf

# Determine the file(path) where the last ip is stored
LAST_IP_FILE="${CONFIG[last_ip_file]}"

# Determine date and time of script execution (for logging)
# https://www.cyberciti.biz/faq/linux-unix-formatting-dates-for-display/
NOW="$(date +"%m-%d-%Y %H:%M:%S")"

# Determine the logging method
LOG_METHOD="${CONFIG[log_method]}"

# Function to log a message based on the selected method
log_message() {
    local message="$1"

    if [ "$LOG_METHOD" == "stdout" ]; then
        # Log to the terminal (stdout)
        echo "$NOW: $message"
    elif [ "$LOG_METHOD" == "mqtt" ]; then
        # Log using mosquitto_pub
        log_mqtt "$NOW: $message"
    else
        temp_message="Invalid log_method in configuration: $LOG_METHOD. Logging to stdout."
        LOG_METHOD="stdout"
        log_message "$temp_message"
        log_message "$message"
    fi
}

# Function to log a message via MQTT (mosquitto_pub)
log_mqtt() {
    local message="$1"

    # MQTT broker configuration
    local mqtt_broker="${CONFIG[mqtt_broker]}"
    local mqtt_port="${CONFIG[mqtt_port]}"
    local mqtt_user="${CONFIG[mqtt_user]}"
    local mqtt_password="${CONFIG[mqtt_password]}"
    local mqtt_topic="${CONFIG[mqtt_topic]}"

    mosquitto_pub -h "$mqtt_broker" -p "$mqtt_port" -u "$mqtt_user" -P "$mqtt_password" -t "$mqtt_topic" -m "$message"
}


# Function to update a domain
update_domain() {
    local DOMAIN="$1"
    local USERNAME="$2"
    local PASSWORD="$3"

    # Perform the update for the current domain
    # https://linux.die.net/man/1/curl
    # dyndns: https://members.dyndns.org/nic/update
    # strato.de: https://dyndns.strato.com/nic/update
    RESULT=$(curl --silent --show-error --user $USERNAME:$PASSWORD "https://dyndns.strato.com/nic/update?hostname=$DOMAIN&myip=$CURRENT_IP")    

    # Check the result from the DynDNS service
    if [[ $RESULT == good* ]]; then
        log_message "Dynamic DNS update for $DOMAIN successful."
    elif [[ $RESULT == nochg* ]]; then
        log_message "IP address for $DOMAIN has not changed. No update required."
    else
        # good : IP updated.
        # nochg : IP address has not changed since last update.
        # nohost : the DynDNS hostname could not be found 
        log_message "Dynamic DNS update for $DOMAIN failed with the following error: $RESULT"
    fi
}


# Get your public IP address
CURRENT_IP=$(curl -s https://ipinfo.io/ip)

# Read the last known IP from a file
if [ -f "$LAST_IP_FILE" ]; then
    LAST_IP=$(cat "$LAST_IP_FILE")
else
    LAST_IP=""
fi

# Compare the current IP with the last known IP
if [ "$CURRENT_IP" == "$LAST_IP" ]; then
    log_message "IP address $CURRENT_IP has not changed. No update required."
else
    log_message "IP address has changed: Old $LAST_IP, New $CURRENT_IP. Start dyndns update..."
    
    # Update the last known IP
    echo "$CURRENT_IP" > "$LAST_IP_FILE"

    # Iterate through the associative array and update each domain
    for domain_key in "${!CONFIG[@]}"; do
        if [[ $domain_key == "domain" ]]; then
            DOMAIN="${CONFIG[$domain_key]}"
            USERNAME="${CONFIG["username"]}"
            PASSWORD="${CONFIG["password"]}"

            update_domain "$DOMAIN" "$USERNAME" "$PASSWORD"
        fi
    done
fi