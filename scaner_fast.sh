#!/bin/bash

TARGET="$1"

alive_hosts=()

declare -A open_ports
declare -A host_os

INTERFACE=$(ip route | grep default | awk '{print $5}')

########################################
# COLORS
########################################

RED="\e[1;31m"
GREEN="\e[1;32m"
YELLOW="\e[1;33m"
DARK_BLUE="\e[1;34m"
MAGENTA="\e[1;35m"
CYAN="\e[1;36m"
RESET="\e[0m"

########################################
# PERFORMANCE
########################################

THREADS=1000

## 0.3 FAST LAN
## 0.5 NORMAL LAN
## 1.0 WAN

TIMEOUT=1.5

########################################
# BANNER
########################################

banner() {

    echo -e "${CYAN}"

    cat << "EOF"
╔══════════════════════════════════════════════╗
║            FAST NETWORK SCANNER             ║
╚══════════════════════════════════════════════╝
EOF

    echo -e "${RESET}"

    echo -e "${GREEN}[*] High Performance TCP Scanner${RESET}"
    echo -e "${YELLOW}[*] GitHub:${RESET} https://github.com/Elus1vee-Sync/"
    echo -e "${MAGENTA}[*] Threads:${RESET} ${CYAN}$THREADS${RESET}"
    echo -e "${MAGENTA}[*] Timeout:${RESET} ${CYAN}$TIMEOUT${RESET}"

    echo
}

########################################
# OS DETECTION
########################################

detect_os() {

    TTL="$1"

    if [[ "$TTL" -le 64 ]]; then
        echo "LINUX"

    elif [[ "$TTL" -le 128 ]]; then
        echo "WINDOWS"

    else
        echo "NETWORK DEVICE"
    fi
}

########################################
# DISCOVERY
########################################

is_alive() {

    IP="$1"

    PING_OUTPUT=$(ping -c1 -W1 "$IP" 2>/dev/null)

    ####################################
    # ICMP Detection
    ####################################

    if echo "$PING_OUTPUT" | grep -q "ttl="; then

        TTL=$(echo "$PING_OUTPUT" | grep ttl | sed -E 's/.*ttl=([0-9]+).*/\1/')

        OS=$(detect_os "$TTL")

        host_os["$IP"]="$OS"

        echo -e "${GREEN}[+]${RESET} Host Alive -> ${CYAN}$IP${RESET} [${YELLOW}$OS${RESET} | TTL=${MAGENTA}$TTL${RESET}]"

        return 0
    fi

    ####################################
    # ARP Fallback
    ####################################

    if arping -I "$INTERFACE" -c1 -w1 "$IP" >/dev/null 2>&1; then

        host_os["$IP"]="UNKNOWN"

        echo -e "${GREEN}[+]${RESET} Host Alive -> ${CYAN}$IP${RESET} [${MAGENTA}ARP ONLY${RESET}]"

        return 0
    fi

    return 1
}

discover_hosts() {

    BASE=$(echo "$TARGET" | cut -d'/' -f1 | awk -F. '{print $1"."$2"."$3}')

    echo
    echo -e "${MAGENTA}[*] Discovering alive hosts...${RESET}"
    echo

    for host in $(seq 1 254); do

        IP="$BASE.$host"

        if is_alive "$IP"; then
            alive_hosts+=("$IP")
        fi
    done
}

########################################
# PORT CHECK
########################################

check_port() {

    local IP="$1"
    local PORT="$2"

    timeout "$TIMEOUT" bash -c "
        exec 3<>/dev/tcp/$IP/$PORT
    " 2>/dev/null
}

########################################
# PORT SCAN
########################################

scan_ports() {

    local IP="$1"

    echo
    echo -e "${MAGENTA}[*] Scanning ports on ${CYAN}$IP${RESET}"
    echo

    export -f check_port
    export TIMEOUT
    export IP

    TMP_FILE=$(mktemp)

    ####################################
    # FAST MULTITHREADED SCAN
    ####################################

    seq 1 65535 | xargs -P "$THREADS" -I{} bash -c '

        PORT={}

        check_port "$IP" "$PORT"

        if [[ $? -eq 0 ]]; then
            echo "$PORT" >> "'"$TMP_FILE"'"
        fi

    ' &

    XPID=$!

    ####################################
    # PROGRESS
    ####################################

    while kill -0 "$XPID" 2>/dev/null; do

        OPEN_COUNT=$(wc -l < "$TMP_FILE" 2>/dev/null)

        echo -ne "\r${MAGENTA}[*]${RESET} Open Ports Found: ${RED}$OPEN_COUNT${RESET}"

        sleep 1
    done

    wait "$XPID"

    echo
    echo

    ####################################
    # STORE RESULTS
    ####################################

    while read -r PORT; do

        [[ -z "$PORT" ]] && continue

        echo -e "${GREEN}[+]${RESET} ${CYAN}$IP${RESET}:${RED}$PORT${RESET} OPEN"

        open_ports["$IP"]+="$PORT "
    done < "$TMP_FILE"

    rm -f "$TMP_FILE"

    echo
    echo -e "${MAGENTA}[*] Finished scanning ${CYAN}$IP${RESET}"
    echo
}

########################################
# MAIN
########################################

banner

if [[ -z "$TARGET" ]]; then

    echo
    echo "Usage: $0 <IP | CIDR>"
    echo

    exit 1
fi

########################################
# SINGLE HOST
########################################

if [[ "$TARGET" != */* ]]; then

    if is_alive "$TARGET"; then
        alive_hosts+=("$TARGET")

    else

        echo
        echo -e "${RED}[-] Host appears down${RESET}"
        echo

        exit 1
    fi

########################################
# NETWORK
########################################

else
    discover_hosts
fi

########################################
# SCANNING
########################################

echo
echo -e "${MAGENTA}[*] Starting port scans...${RESET}"
echo

for IP in "${alive_hosts[@]}"; do
    scan_ports "$IP"
done

########################################
# SUMMARY
########################################

echo
echo -e "${MAGENTA}[*] Scan Summary${RESET}"
echo

echo -e "${CYAN}HOST                OS                 OPEN PORTS${RESET}"
echo -e "${CYAN}---------------------------------------------------------------${RESET}"

for IP in "${alive_hosts[@]}"; do

    PORTS="${open_ports[$IP]}"

    [[ -z "$PORTS" ]] && PORTS="NONE"

    OS="${host_os[$IP]}"

    ####################################
    # OS COLORS
    ####################################

    if [[ "$OS" == "LINUX" ]]; then
        OS_COLOR="${YELLOW}"

    elif [[ "$OS" == "WINDOWS" ]]; then
        OS_COLOR="${DARK_BLUE}"

    else
        OS_COLOR="${MAGENTA}"
    fi

    ####################################
    # PRINT SUMMARY
    ####################################

    printf "${CYAN}%-20s${RESET} ${OS_COLOR}%-18s${RESET} ${RED}%s${RESET}\n" "$IP" "$OS" "$PORTS"

done

echo
