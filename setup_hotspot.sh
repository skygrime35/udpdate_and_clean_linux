#!/usr/bin/env bash

# ==============================================================================
# Hotspot Activation Script v1.0.0
# ==============================================================================
# A utility to quickly activate a Wi-Fi hotspot using NetworkManager (nmcli).
# ==============================================================================

set -euo pipefail

# Configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly SSID="Hotspot"
readonly PASSWORD="123456789"

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# ==============================================================================
# Utility Functions
# ==============================================================================

log() {
  local level="$1"
  local message="$2"
  
  case "$level" in
    INFO)    echo -e "${GREEN}[INFO]${NC} $message" ;;
    WARN)    echo -e "${YELLOW}[WARN]${NC} $message" ;;
    ERROR)   echo -e "${RED}[ERROR]${NC} $message" >&2 ;;
    SUCCESS) echo -e "${GREEN}${BOLD}[SUCCESS]${NC} $message" ;;
  esac
}

check_root() {
  if [ "$(id -u)" != "0" ]; then
    log "ERROR" "This script must be run with sudo or as root."
    exit 1
  fi
}

get_wifi_interface() {
  local iface
  iface=$(nmcli device status | grep -w "wifi" | head -n 1 | awk '{print $1}')
  echo "$iface"
}

# ==============================================================================
# Main
# ==============================================================================

main() {
  check_root

  log "INFO" "Detecting Hotspot status..."
  
  # Check if the "Hotspot" connection is currently active
  if nmcli connection show --active | grep -qW "$SSID"; then
    log "WARN" "Hotspot '$SSID' is currently active."
    log "INFO" "Deactivating hotspot..."
    if nmcli connection down "$SSID" >/dev/null 2>&1; then
      log "SUCCESS" "Hotspot '$SSID' has been deactivated."
    else
      log "ERROR" "Failed to deactivate hotspot."
      exit 1
    fi
    exit 0
  fi

  log "INFO" "Hotspot is inactive. Activating..."
  
  log "INFO" "Detecting Wi-Fi interface..."
  local wifi_iface
  wifi_iface=$(get_wifi_interface)

  if [ -z "$wifi_iface" ]; then
    log "ERROR" "No Wi-Fi interface detected."
    exit 1
  fi

  log "INFO" "Using interface: ${BOLD}$wifi_iface${NC}"

  # Ensure cleaned state before starting
  if nmcli connection show "$SSID" >/dev/null 2>&1; then
    log "DEBUG" "Cleaning up previous '$SSID' configuration..."
    nmcli connection delete "$SSID" >/dev/null 2>&1 || true
  fi

  log "INFO" "Configuring and starting hotspot '$SSID'..."
  
  if nmcli device wifi hotspot \
    ifname "$wifi_iface" \
    con-name "$SSID" \
    ssid "$SSID" \
    password "$PASSWORD"; then
    log "SUCCESS" "Hotspot '$SSID' has been activated!"
    log "INFO" "SSID: ${BOLD}$SSID${NC}"
    log "INFO" "Password: ${BOLD}$PASSWORD${NC}"
  else
    log "ERROR" "Failed to activate hotspot."
    exit 1
  fi
  
  echo ""
  nmcli connection show --active | grep "$SSID" || true
}

main "$@"
