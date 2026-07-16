#!/bin/bash
set -Eeuo pipefail

#  CONFIGURATION 
readonly PORT_GNIREHTET=31416  # Default port used internally by gnirehtet relay
readonly PORT_SUNSHINE=47989   # Default Sunshine control port

readonly SUNSHINE_UUID="55CABDFE-F984-5F29-4901-E25DF21BDF30"	# UUID from your sunshine instance
readonly SUNSHINE_COMPUTER_NAME="arch-vitor"	# Name of the computer where sunshine is running
readonly DESKTOP_APP_ID="881448767"	    # App_Id for desktop streaming app on sunshine

# had to run `sh -c "echo $SUNSHINE_APP_ID > /tmp/sunshine_id.txt"`
# on Sunshine's Web Interface to grab the AppId
# Let me know if there's a better way to grab the SUNSHINE_APP_ID for the desktop app

readonly RESOLUTION="1920x1200@60"
readonly MON_NAME="Virtual-1"
readonly TIMEOUT=15

PIDS=()

cleanup() {
    local exit_code=$?
    trap - SIGINT SIGTERM EXIT      			# Prevent trap recursion by un-trapping signals
    
    echo -e "\n\n[~] Tearing down sessions..."
    
    for pid in "${PIDS[@]:-}"; do 				# Kill background process groups safely
        kill "$pid" 2>/dev/null || true
    done
    
    if hyprctl monitors | grep -q "^Monitor $MON_NAME"; then	# Destroy headless monitor
        echo "[+] Destroying headless monitor: $MON_NAME"
        hyprctl output destroy "$MON_NAME" >/dev/null 2>&1
    fi
    echo "[+] Done. Goodbye!"
    exit "$exit_code"
}
trap cleanup SIGINT SIGTERM EXIT    # traps Ctrl+C and unexpected crashes in cleanup function above

check_adb(){
    echo "[*] Validation: Checking for attached Android devices..."
    if ! adb get-state &>/dev/null; then
        echo "[-] Error: No Android device detected via ADB or device is unauthorized."
        echo "    Ensure USB debugging is enabled and the cable is firmly plugged in."
        exit 1
    fi
    echo "[+] Device detected successfully!"
}

initialize_vmonitor() {
    echo "[*] Initializing headless monitor layer ($RESOLUTION)..."

    if ! hyprctl monitors | grep -q "^Monitor $MON_NAME"; then
        if ! hyprctl output create headless "$MON_NAME" &>/dev/null; then
            echo "[-] Critical: Failed to spin up virtual output."
            exit 1
        fi
    fi
    # 2. Set geometry and resolution using the new Lua 'eval' syntax
    #    Supressing the output prevents any blank lines from spilling into the terminal.
    hyprctl eval "hl.monitor({ output = \"$MON_NAME\", mode = \"$RESOLUTION\", position = \"auto-center-down\", scale = 1 })" >/dev/null 2>&1
}

start_services(){
    echo "[*] Launching system routing proxies..."
    gnirehtet run &>/dev/null & # Start Gnirehtet routing engine in background
    PIDS+=("$!")
    sunshine &>/dev/null &  # Start Sunshine host service in background
    PIDS+=("$!")
}

port_ready() {
    timeout 1 bash -c "</dev/tcp/127.0.0.1/$1" &>/dev/null
}

wait_for_services(){
    echo -n "[*] Synchronizing services (waiting for initialization flags)"

    for ((i=0; i<TIMEOUT; i++)); do
        echo -n "."

        if port_ready "$PORT_GNIREHTET" &&      # Verify gnirehtet is listening on loopback network socket
        port_ready "$PORT_SUNSHINE"; then    # Verify sunshine web server/streaming stack is initialized
            echo -e "\n[+] Network interfaces synced and active!"
            break
        fi

        sleep 1
    done

    if ! port_ready "$PORT_GNIREHTET" || ! port_ready "$PORT_SUNSHINE"; then
        echo -e "\n[-] Error: Services timed out or failed to initialize correctly."
        exit 1
    fi
}

print_info_and_hold(){
    clear
    
    echo " DASHBOARD MONITOR PIPELINE IS READY!"
    echo " Press [Ctrl+C] to end your workspace."
	
    # Fire the shortcut trampoline to execute the targeted stream pipeline
    adb shell am start -n com.limelight/com.limelight.ShortcutTrampoline \
        --es "UUID" "$SUNSHINE_UUID" \
        --es "Name" "$SUNSHINE_COMPUTER_NAME" \
        --es "AppId" "$DESKTOP_APP_ID" >/dev/null 2>&1
    
    local status=0

    # Wait for ANY background process (Sunshine or Gnirehtet) to exit.
    # Consumes zero CPU and breaks immediately if a service crashes.
    
    wait -n || status=$?    # '|| status=$?' catches the error code without triggering 'set -e'

    if (( status != 0 )); then  # If we reach this line, a background service died unexpectedly.
        echo -e "\n[-] A critical background service stopped unexpectedly. Initiating cleanup..."
    fi
}

# Actually run stuff
check_adb                 # VALIDATE ADB CONNECTIVITY  
initialize_vmonitor       # INITIALIZE HYPRLAND LAYER
start_services            # SPIN UP SERVICES IN BACKGROUND 
wait_for_services         # ACTIVE STATUS PROBING (WAIT UNTIL READY) 
print_info_and_hold       # IDLE BLOCK LOCK
