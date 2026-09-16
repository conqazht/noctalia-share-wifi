#!/usr/bin/env bash

ACTION="${1:-status}"

get_active_wifi() {
    nmcli -t -f active,chan,freq dev wifi list --rescan no 2>/dev/null | grep '^yes' | head -n1 || true
}

run_root() {
    # If passwordless sudo is available, use sudo; otherwise fall back to pkexec (Polkit GUI)
    if sudo -n "$1" --help >/dev/null 2>&1 || sudo -n true 2>/dev/null; then
        sudo "$@"
    else
        pkexec "$@"
    fi
}

stop_hotspot() {
    # Stop create_ap instance for ap0
    if iw dev ap0 info >/dev/null 2>&1 || pgrep -f "create_ap.*(wlan0|ap0)" >/dev/null 2>&1; then
        run_root create_ap --stop ap0 >/dev/null 2>&1 || true
    fi

    # Quick check (up to 0.5s with 0.1s intervals)
    local count=0
    while iw dev ap0 info >/dev/null 2>&1 && [ $count -lt 5 ]; do
        sleep 0.1
        count=$((count + 1))
    done

    # Force cleanup if still stubborn
    if iw dev ap0 info >/dev/null 2>&1; then
        run_root pkill -9 -f "create_ap.*(wlan0|ap0)" >/dev/null 2>&1 || true
        run_root iw dev ap0 del >/dev/null 2>&1 || true
    fi
}

case "$ACTION" in
    detect)
        INFO=$(get_active_wifi)
        if [ -n "$INFO" ]; then
            CHAN=$(echo "$INFO" | cut -d: -f2)
            FREQ_STR=$(echo "$INFO" | cut -d: -f3 | awk '{print $1}')
            FREQ=${FREQ_STR:-0}
            if [ "$FREQ" -ge 5000 ]; then
                BAND="5Ghz"
            elif [ "$FREQ" -gt 0 ]; then
                BAND="2.4Ghz"
            else
                BAND="Auto"
            fi
            echo "{\"connected\": true, \"channel\": \"$CHAN\", \"band\": \"$BAND\", \"freq\": $FREQ}"
        else
            echo '{"connected": false, "channel": "6", "band": "2.4Ghz", "freq": 2437}'
        fi
        ;;

    status)
        # Fast non-root status check via kernel wireless interface
        if iw dev ap0 info >/dev/null 2>&1; then
            CLIENT_COUNT=$(iw dev ap0 station dump 2>/dev/null | grep -c "Station" || true)
            CLIENT_COUNT=${CLIENT_COUNT:-0}
            echo "{\"active\": true, \"device\": \"ap0\", \"clients\": $CLIENT_COUNT}"
        elif pgrep -f "create_ap.*wlan0" >/dev/null 2>&1; then
            echo '{"active": true, "device": "ap0", "clients": 0}'
        else
            echo '{"active": false, "clients": 0}'
        fi
        ;;

    start)
        SSID="$2"
        PASS="$3"
        BAND="$4"
        CHAN="$5"
        MAX_CLIENTS="${6:-0}"

        if [ -z "$SSID" ]; then
            echo '{"error": "SSID cannot be empty"}' >&2
            exit 1
        fi

        if [ -z "$PASS" ] || [ ${#PASS} -lt 8 ]; then
            echo '{"error": "Password must be at least 8 characters"}' >&2
            exit 1
        fi

        # Find default internet interface
        INET_IFACE=$(ip route 2>/dev/null | awk '/default/{print $5; exit}' || echo "wlan0")
        [ -z "$INET_IFACE" ] && INET_IFACE="wlan0"

        # If already running or ap0 exists, clean it up first
        if iw dev ap0 info >/dev/null 2>&1 || pgrep -f "create_ap.*wlan0" >/dev/null 2>&1; then
            stop_hotspot
        fi

        CMD_ARGS=(--daemon wlan0 "$INET_IFACE" "$SSID" "$PASS")

        # Add channel if specified and valid
        if [ -n "$CHAN" ] && [ "$CHAN" != "Auto" ] && [ "$CHAN" != "default" ]; then
            CMD_ARGS+=(-c "$CHAN")
        fi

        # Add band if specified
        if [ "$BAND" = "5Ghz" ]; then
            CMD_ARGS+=(--freq-band 5)
        elif [ "$BAND" = "2.4Ghz" ]; then
            CMD_ARGS+=(--freq-band 2.4)
        fi

        # Add max clients limit (strictly 1 to 8, default 2, no unlimited)
        if [ -z "$MAX_CLIENTS" ] || [ "$MAX_CLIENTS" -lt 1 ] 2>/dev/null; then
            MAX_CLIENTS=2
        elif [ "$MAX_CLIENTS" -gt 8 ] 2>/dev/null; then
            MAX_CLIENTS=8
        fi
        DRIVER_ARG=$'nl80211\nmax_num_sta='"$MAX_CLIENTS"
        CMD_ARGS+=(--driver "$DRIVER_ARG")

        # Run create_ap as daemon
        OUTPUT=$(run_root create_ap "${CMD_ARGS[@]}" 2>&1)
        EXIT_CODE=$?

        if [ $EXIT_CODE -eq 0 ]; then
            echo '{"success": true}'
            exit 0
        else
            ERR_MSG=$(echo "$OUTPUT" | grep -i "ERROR:" | head -n1)
            [ -z "$ERR_MSG" ] && ERR_MSG="$OUTPUT"
            echo "{\"error\": $(printf '%s' "$ERR_MSG" | jq -R .)}" >&2
            exit $EXIT_CODE
        fi
        ;;

    stop)
        stop_hotspot
        echo '{"stopped": true}'
        ;;

    *)
        echo "Usage: $0 {detect|status|start|stop}"
        exit 1
        ;;
esac
