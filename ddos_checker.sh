#!/bin/bash

# Function to check logs for DDoS attacks
check_logs() {
    local domain="$1"
    local log_file="$2"
    local timeframe="$3"
    local threshold="$4"
    local attack_url="$5"
    local additional_threshold="$6"
    local additional_timeframe="$7"

    echo "Checking logs for $domain:"
    awk -v domain="$domain" -v timeframe="$timeframe" -v threshold="$threshold" -v additional_threshold="$additional_threshold" -v additional_timeframe="$additional_timeframe" '
        $0 ~ domain {
            total_requests++
            ip=$1
            cmd="date +%s -d\"" substr($4,2) " " substr($5,0,length($5)-1) "\""
            cmd | getline timestamp
            close(cmd)
            if (ip in requests) {
                if (timestamp - requests[ip] <= timeframe) {
                    count[ip]++
                    if (count[ip] >= threshold) {
                        echo "Potential DDoS attack from IP: " ip
                        delete count[ip]
                        cmd = "curl -s -X GET \"" attack_url "?domain=" domain "\""
                        system(cmd)
                    }
                } else {
                    delete requests[ip]
                }
            } else {
                requests[ip] = timestamp
            }
        }
        END {
            if (total_requests >= additional_threshold && (timestamp - first_request) <= (additional_timeframe*60)) {
                print "Potential DDoS attack for domain: " domain " - Total Requests: " total_requests
                cmd = "curl -s -X GET \"" attack_url "?domain=" domain "\""
                system(cmd)
            }
        }
    ' "$log_file"
}

# Main script
config_file="ddos_checker.ini"

if [[ ! -f "$config_file" ]]; then
    echo "Error: Configuration file $config_file not found."
    exit 1
fi

# Read configurations from the INI file
apache_logs_path=$(awk -F "=" '/^apache_logs_path/ {print $2}' "$config_file")
excluded_domains=$(awk -F "=" '/^excluded_domains/ {print $2}' "$config_file")
timeframe=$(awk -F "=" '/^timeframe/ {print $2}' "$config_file")
threshold=$(awk -F "=" '/^threshold/ {print $2}' "$config_file")
attack_url=$(awk -F "=" '/^attack_url/ {print $2}' "$config_file")
additional_threshold=$(awk -F "=" '/^additional_threshold/ {print $2}' "$config_file")
additional_timeframe=$(awk -F "=" '/^additional_timeframe/ {print $2}' "$config_file")

# Check available parked domains in Apache
virtual_hosts=($(ls "$apache_logs_path" | grep -E '^access\.' | sed -E 's/^access\.//g'))

# Check logs for DDoS attacks for each domain
for domain in "${virtual_hosts[@]}"; do
    if [[ "$excluded_domains" =~ "$domain" ]]; then
        echo "Skipping $domain as it is excluded."
    else
        check_logs "$domain" "$apache_logs_path/access.$domain" "$timeframe" "$threshold" "$attack_url" "$additional_threshold" "$additional_timeframe"
    fi
done
