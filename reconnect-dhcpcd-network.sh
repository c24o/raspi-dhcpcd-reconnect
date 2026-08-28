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
DEFAULT_FOLDER="/usr/local/etc/raspi-dhcpcd-reconnect/"
LOG_FILE="/var/log/raspi-dhcpcd-reconnect.log"
ENV_FILE="${DEFAULT_FOLDER}reconnect-dhcpcd-network.env"
LOCK_FILE="${DEFAULT_FOLDER}lock"
REBOOT_STAMP_FILE="${DEFAULT_FOLDER}reboot"
REBOOT_COOLDOWN_SECONDS=$((6 * 3600))

# Prevent overlapping runs (a retry cycle can take a few minutes, and cron
# may fire again before a previous run has finished).
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    exit 0
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: this script must run as root (needed to restart dhcpcd / reboot)." >&2
    exit 1
fi

# Initialize variables with default values
TRY_REBOOT=false
ROUTER_IP="192.168.1.1"
INTERNET_IP="8.8.8.8"

# Validate a string is a dotted-quad IPv4 address with each octet <= 255.
is_valid_ipv4() {
    local ip="$1"
    [[ "$ip" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] || return 1
    local octet
    for octet in "${BASH_REMATCH[@]:1}"; do
        (( octet <= 255 )) || return 1
    done
    return 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --try-reboot)
            TRY_REBOOT=true
            shift
            ;;
        --router-ip)
            if [ -n "$2" ]; then
                if ! is_valid_ipv4 "$2"; then
                    echo "Error: --router-ip must be a valid IPv4 address (got '$2')"
                    exit 1
                fi
                ROUTER_IP="$2"
                shift 2
            else
                echo "Error: --router-ip requires an IP address"
                exit 1
            fi
            ;;
        --internet-ip)
            if [ -n "$2" ]; then
                if ! is_valid_ipv4 "$2"; then
                    echo "Error: --internet-ip must be a valid IPv4 address (got '$2')"
                    exit 1
                fi
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

# Function to log messages.
log() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" >> "$LOG_FILE"
}

# --- Load Telegram credentials ---
# The env file is sourced as shell, so only load it if it's owned by root
# and not readable/writable by anyone else - otherwise it's a path to
# arbitrary root code execution via cron.
if [ -f "$ENV_FILE" ]; then
    env_owner_uid=$(stat -c '%u' "$ENV_FILE")
    env_perms=$(stat -c '%a' "$ENV_FILE")
    if [ "$env_owner_uid" != "0" ] || [ "$env_perms" != "600" ]; then
        log "Refusing to load $ENV_FILE: expected owner root with mode 600 (found uid=$env_owner_uid mode=$env_perms)."
    else
        source "$ENV_FILE"
    fi
fi

# Function to check connectivity.
check_connectivity() {
    local target="$1"
    ping -c 1 -W 2 -- "$target" > /dev/null 2>&1
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
        timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        message="✅ Raspberry Pi reconnected successfully at $timestamp"
        log "$message"
        send_telegram_message "$message"
    else
        log "dhcpcd restarted but still no connection."
        if [ "$TRY_REBOOT" = true ]; then
            now_epoch=$(date +%s)
            last_reboot_epoch=0
            if [ -f "$REBOOT_STAMP_FILE" ]; then
                last_reboot_epoch=$(cat "$REBOOT_STAMP_FILE" 2>/dev/null || echo 0)
            fi
            if (( now_epoch - last_reboot_epoch >= REBOOT_COOLDOWN_SECONDS )); then
                log "Attempting system reboot..."
                echo "$now_epoch" > "$REBOOT_STAMP_FILE"
                /sbin/reboot
            else
                log "Skipping reboot: last reboot was less than $((REBOOT_COOLDOWN_SECONDS / 3600))h ago (probably won't fix this)."
            fi
        fi
    fi
fi

exit 0
