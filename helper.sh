#!/usr/bin/env bash

ACTION="${1:-status}"

PID_FILE="/tmp/noctalia-share-wifi.pid"

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
    local pid=""
    if [ -f "$PID_FILE" ]; then
        pid=$(cat "$PID_FILE" 2>/dev/null | tr -d ' \n\r' || true)
    fi

    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        run_root create_ap --stop "$pid" >/dev/null 2>&1 || run_root kill -USR1 "$pid" >/dev/null 2>&1 || true

        # Wait up to 0.5s for process to exit
        local count=0
        while kill -0 "$pid" 2>/dev/null && [ $count -lt 5 ]; do
            sleep 0.1
            count=$((count + 1))
        done

        if kill -0 "$pid" 2>/dev/null; then
            run_root kill -9 "$pid" >/dev/null 2>&1 || true
        fi
    elif iw dev ap0 info >/dev/null 2>&1; then
        run_root create_ap --stop ap0 >/dev/null 2>&1 || true
    fi

    # Cleanup interface ap0 if still remaining
    if iw dev ap0 info >/dev/null 2>&1; then
        run_root iw dev ap0 del >/dev/null 2>&1 || true
    fi

    rm -f "$PID_FILE" 2>/dev/null || true
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
        local is_active=false
        local client_count=0

        if [ -f "$PID_FILE" ]; then
            local pid
            pid=$(cat "$PID_FILE" 2>/dev/null | tr -d ' \n\r' || true)
            if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
                is_active=true
            fi
        fi

        if iw dev ap0 info >/dev/null 2>&1; then
            is_active=true
            client_count=$(iw dev ap0 station dump 2>/dev/null | grep -c "Station" || true)
            client_count=${client_count:-0}
        fi

        if [ "$is_active" = true ]; then
            echo "{\"active\": true, \"device\": \"ap0\", \"clients\": $client_count}"
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
        if iw dev ap0 info >/dev/null 2>&1 || [ -f "$PID_FILE" ]; then
            stop_hotspot
        fi

        CMD_ARGS=(--daemon --pidfile "$PID_FILE" wlan0 "$INET_IFACE" "$SSID" "$PASS")

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
            ERR_CLEAN=$(printf '%s' "$ERR_MSG" | tr -d '\n\r' | sed 's/\\/\\\\/g; s/"/\\"/g')
            echo "{\"error\": \"$ERR_CLEAN\"}" >&2
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
