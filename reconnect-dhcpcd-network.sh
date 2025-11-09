#!/bin/bash
# ============================================================
# reconnect-dhcpcd-network.sh
# ------------------------------------------------------------
# Checks router and Internet connectivity on Raspberry Pi
# systems using dhcpcd, and restarts the service if needed.
#
# Default router: 192.168.1.1
# Default Internet test host: 8.8.8.8
# Optional arguments:
#   --router-ip     - Router IP address (default: 192.168.1.1)
#   --internet-ip   - Internet test IP address (default: 8.8.8.8)
#   --try-reboot    - Attempt system reboot if reconnection fails
#
# Logs only when connectivity fails or recovers.
# Sends a Telegram message when connection is restored.
# ============================================================

# --- Configuration ---
LOG_FILE="/var/log/reconnect-dhcpcd-network.log"
ENV_FILE="/usr/local/etc/raspi-dhcpcd-reconnect/reconnect-dhcpcd-network.env"

# Initialize variables with default values
TRY_REBOOT=false
ROUTER_IP="192.168.1.1"
INTERNET_IP="8.8.8.8"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --try-reboot)
            TRY_REBOOT=true
            shift
            ;;
        --router-ip)
            if [ -n "$2" ]; then
                ROUTER_IP="$2"
                shift 2
            else
                echo "Error: --router-ip requires an IP address"
                exit 1
            fi
            ;;
        --internet-ip)
            if [ -n "$2" ]; then
                INTERNET_IP="$2"
                shift 2
            else
                echo "Error: --internet-ip requires an IP address"
                exit 1
            fi
            ;;
        *)
            echo "Error: Unknown parameter '$1'"
            echo "Usage: $0 [--router-ip IP] [--internet-ip IP] [--try-reboot]"
            exit 1
            ;;
    esac
done

# Number of retry attempts before deciding connection is down
MAX_RETRIES=3
RETRY_DELAY=20

# --- Load Telegram credentials ---
if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
fi

# Function to log messages.
log() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" >> "$LOG_FILE"
}

# Function to check connectivity.
check_connectivity() {
    local target="$1"
    ping -c 1 -W 20 "$target" > /dev/null 2>&1
    return $?  # 0 = success, nonzero = failure
}

# Function to check connectivity with retries.
test_with_retries() {
    local target=$1
    local attempt=1
    while (( attempt <= MAX_RETRIES )); do
        if check_connectivity "$target"; then
            return 0
        fi
        (( attempt++ ))
        sleep "$RETRY_DELAY"
    done
    return 1
}

# Function to send Telegram notification.
send_telegram_message() {
    local text="$1"
    if [[ -n "$TELEGRAM_BOT_TOKEN" && -n "$TELEGRAM_CHAT_ID" ]]; then
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
             -d chat_id="${TELEGRAM_CHAT_ID}" \
             -d text="$text" >/dev/null 2>&1
    else
        log "No Telegram credentials found, skipping notification."
    fi
}

# === Main logic ===

# Step 1: Check connection to router
if test_with_retries "$ROUTER_IP"; then
    # Router reachable → check internet
    if ! test_with_retries "$INTERNET_IP"; then
        # Router OK but internet unreachable → log only
        log "Router OK but no internet (ISP issue)"
    fi
else
    # Router unreachable → restart dhcpcd
    log "Lost connection to router. Restarting dhcpcd..."
    systemctl restart dhcpcd
    sleep 10

    # Try to reconnect
    if test_with_retries "$ROUTER_IP" && test_with_retries "$INTERNET_IP"; then
        message="✅ Raspberry Pi reconnected successfully at $timestamp"
        log "$message"
        send_telegram_message "$message"
    else
        log "dhcpcd restarted but still no connection."
        if [ "$TRY_REBOOT" = true ]; then
            log "Attempting system reboot..."
            /sbin/reboot now
        fi
    fi
fi

exit 0
