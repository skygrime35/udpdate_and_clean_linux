#!/usr/bin/env bash

# ==============================================================================
# PC Health Check Script v1.0.0
# ==============================================================================
# A comprehensive utility for checking system health on Linux systems.
# Displays: CPU, Memory, Disk, Network, Services, and more.
# ==============================================================================

set -euo pipefail

# Configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly VERSION="1.0.0"

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# Health thresholds
readonly DISK_WARNING=80
readonly DISK_CRITICAL=90
readonly MEM_WARNING=80
readonly MEM_CRITICAL=90
readonly CPU_WARNING=80
readonly CPU_CRITICAL=90
readonly TEMP_WARNING=70
readonly TEMP_CRITICAL=85

# Options
VERBOSE=false
JSON_OUTPUT=false
WATCH_MODE=false
WATCH_INTERVAL=5

# ==============================================================================
# Utility Functions
# ==============================================================================

print_header() {
  local title="$1"
  echo ""
  echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════════════╗${NC}"
  printf "${CYAN}${BOLD}║${NC} %-66s ${CYAN}${BOLD}║${NC}\n" "$title"
  echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════════════╝${NC}"
}

print_section() {
  local title="$1"
  echo ""
  echo -e "${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE}${BOLD}  $title${NC}"
  echo -e "${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_status() {
  local label="$1"
  local value="$2"
  local status="${3:-}"
  
  local color="$NC"
  local icon=""
  
  case "$status" in
    good)     color="$GREEN"; icon="✅" ;;
    warning)  color="$YELLOW"; icon="⚠️ " ;;
    critical) color="$RED"; icon="🚨" ;;
    info)     color="$CYAN"; icon="ℹ️ " ;;
    *)        color="$NC"; icon="  " ;;
  esac
  
  printf "  ${BOLD}%-25s${NC} ${color}%s %s${NC}\n" "$label:" "$icon" "$value"
}

get_status_by_threshold() {
  local value="$1"
  local warning="$2"
  local critical="$3"
  
  if (( $(echo "$value >= $critical" | bc -l) )); then
    echo "critical"
  elif (( $(echo "$value >= $warning" | bc -l) )); then
    echo "warning"
  else
    echo "good"
  fi
}

display_help() {
  cat <<EOF
${BOLD}${SCRIPT_NAME} v${VERSION}${NC} - PC Health Check Utility

${BOLD}Usage:${NC} $SCRIPT_NAME [OPTIONS]

${BOLD}Options:${NC}
  -v, --verbose       Show detailed information
  -w, --watch [N]     Continuous monitoring mode (refresh every N seconds, default: 5)
  -j, --json          Output in JSON format
  -h, --help          Display this help message
  --version           Display version information

${BOLD}Checks Performed:${NC}
  • System Information (hostname, OS, kernel, uptime)
  • CPU Status (usage, load average, frequency, temperature)
  • Memory Usage (RAM, swap, buffers/cache)
  • Disk Usage (all mounted partitions)
  • Network Status (interfaces, IP addresses, connectivity)
  • System Services (critical services status)
  • Battery Status (if applicable)
  • Recent System Errors (from journalctl)

${BOLD}Status Indicators:${NC}
  ${GREEN}✅ Good${NC}      - Within normal range
  ${YELLOW}⚠️  Warning${NC}  - Approaching threshold
  ${RED}🚨 Critical${NC} - Requires attention

${BOLD}Thresholds:${NC}
  Disk:   Warning >${DISK_WARNING}%, Critical >${DISK_CRITICAL}%
  Memory: Warning >${MEM_WARNING}%, Critical >${MEM_CRITICAL}%
  CPU:    Warning >${CPU_WARNING}%, Critical >${CPU_CRITICAL}%
  Temp:   Warning >${TEMP_WARNING}°C, Critical >${TEMP_CRITICAL}°C

${BOLD}Examples:${NC}
  $SCRIPT_NAME                   # Standard health check
  $SCRIPT_NAME -v                # Verbose output
  $SCRIPT_NAME -w 10             # Watch mode, refresh every 10s
  $SCRIPT_NAME -j                # JSON output
EOF
}

display_version() {
  echo "$SCRIPT_NAME version $VERSION"
}

# ==============================================================================
# System Information
# ==============================================================================

check_system_info() {
  print_section "🖥️  System Information"
  
  local hostname
  local os_name
  local kernel
  local arch
  local uptime_info
  
  hostname=$(hostname 2>/dev/null || echo "Unknown")
  os_name=$(grep -E "^PRETTY_NAME=" /etc/os-release 2>/dev/null | cut -d'"' -f2 || echo "Unknown")
  kernel=$(uname -r 2>/dev/null || echo "Unknown")
  arch=$(uname -m 2>/dev/null || echo "Unknown")
  uptime_info=$(uptime -p 2>/dev/null | sed 's/up //' || echo "Unknown")
  
  print_status "Hostname" "$hostname" "info"
  print_status "OS" "$os_name" "info"
  print_status "Kernel" "$kernel" "info"
  print_status "Architecture" "$arch" "info"
  print_status "Uptime" "$uptime_info" "info"
  
  # Boot time
  local boot_time
  boot_time=$(who -b 2>/dev/null | awk '{print $3, $4}' || echo "Unknown")
  print_status "Last Boot" "$boot_time" "info"
  
  # Current users
  local users
  users=$(who 2>/dev/null | wc -l || echo "0")
  print_status "Logged Users" "$users" "info"
}

# ==============================================================================
# CPU Information
# ==============================================================================

check_cpu() {
  print_section "🔧 CPU Status"
  
  # CPU model
  local cpu_model
  cpu_model=$(grep -m1 "model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo "Unknown")
  print_status "Model" "$cpu_model" "info"
  
  # CPU cores
  local cpu_cores
  cpu_cores=$(nproc 2>/dev/null || echo "Unknown")
  print_status "Cores" "$cpu_cores" "info"
  
  # CPU usage (quick sample)
  local cpu_usage
  cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print 100 - $8}' 2>/dev/null || echo "0")
  cpu_usage=$(printf "%.1f" "$cpu_usage")
  local cpu_status
  cpu_status=$(get_status_by_threshold "$cpu_usage" "$CPU_WARNING" "$CPU_CRITICAL")
  print_status "Usage" "${cpu_usage}%" "$cpu_status"
  
  # Load average
  local load_avg
  load_avg=$(cat /proc/loadavg 2>/dev/null | awk '{print $1", "$2", "$3}' || echo "Unknown")
  print_status "Load Avg (1/5/15m)" "$load_avg" "info"
  
  # CPU frequency
  if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq ]; then
    local cpu_freq
    cpu_freq=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null)
    cpu_freq=$((cpu_freq / 1000))
    print_status "Current Frequency" "${cpu_freq} MHz" "info"
  fi
  
  # CPU temperature
  local cpu_temp=""
  local temp_status="info"
  
  # Try different temperature sources
  if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
    cpu_temp=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
    cpu_temp=$((cpu_temp / 1000))
  elif command -v sensors &>/dev/null; then
    cpu_temp=$(sensors 2>/dev/null | grep -E "Core 0|Package id" | head -1 | grep -oP '\+\K[0-9.]+' || echo "")
    [ -n "$cpu_temp" ] && cpu_temp=$(printf "%.0f" "$cpu_temp")
  fi
  
  if [ -n "$cpu_temp" ] && [ "$cpu_temp" != "" ]; then
    temp_status=$(get_status_by_threshold "$cpu_temp" "$TEMP_WARNING" "$TEMP_CRITICAL")
    print_status "Temperature" "${cpu_temp}°C" "$temp_status"
  elif [ "$VERBOSE" = true ]; then
    print_status "Temperature" "Not available" "info"
  fi
}

# ==============================================================================
# Memory Information
# ==============================================================================

check_memory() {
  print_section "💾 Memory Status"
  
  # Parse memory info
  local mem_total mem_used mem_free mem_available mem_cached mem_buffers
  local swap_total swap_used swap_free
  
  mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
  mem_available=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
  mem_free=$(grep "MemFree:" /proc/meminfo | awk '{print $2}')
  mem_cached=$(grep "^Cached:" /proc/meminfo | awk '{print $2}')
  mem_buffers=$(grep Buffers /proc/meminfo | awk '{print $2}')
  swap_total=$(grep SwapTotal /proc/meminfo | awk '{print $2}')
  swap_free=$(grep SwapFree /proc/meminfo | awk '{print $2}')
  
  # Calculate used memory
  mem_used=$((mem_total - mem_available))
  swap_used=$((swap_total - swap_free))
  
  # Calculate percentages
  local mem_percent swap_percent
  mem_percent=$((mem_used * 100 / mem_total))
  
  if [ "$swap_total" -gt 0 ]; then
    swap_percent=$((swap_used * 100 / swap_total))
  else
    swap_percent=0
  fi
  
  # Convert to human readable
  local mem_total_gb mem_used_gb mem_available_gb
  mem_total_gb=$(echo "scale=1; $mem_total / 1048576" | bc)
  mem_used_gb=$(echo "scale=1; $mem_used / 1048576" | bc)
  mem_available_gb=$(echo "scale=1; $mem_available / 1048576" | bc)
  
  local mem_status
  mem_status=$(get_status_by_threshold "$mem_percent" "$MEM_WARNING" "$MEM_CRITICAL")
  
  print_status "Total RAM" "${mem_total_gb} GB" "info"
  print_status "Used RAM" "${mem_used_gb} GB (${mem_percent}%)" "$mem_status"
  print_status "Available RAM" "${mem_available_gb} GB" "info"
  
  if [ "$VERBOSE" = true ]; then
    local cached_gb buffers_gb
    cached_gb=$(echo "scale=1; $mem_cached / 1048576" | bc)
    buffers_gb=$(echo "scale=1; $mem_buffers / 1048576" | bc)
    print_status "Cached" "${cached_gb} GB" "info"
    print_status "Buffers" "${buffers_gb} GB" "info"
  fi
  
  # Swap
  if [ "$swap_total" -gt 0 ]; then
    local swap_total_gb swap_used_gb
    swap_total_gb=$(echo "scale=1; $swap_total / 1048576" | bc)
    swap_used_gb=$(echo "scale=1; $swap_used / 1048576" | bc)
    
    local swap_status="good"
    [ "$swap_percent" -gt 50 ] && swap_status="warning"
    [ "$swap_percent" -gt 80 ] && swap_status="critical"
    
    print_status "Swap Total" "${swap_total_gb} GB" "info"
    print_status "Swap Used" "${swap_used_gb} GB (${swap_percent}%)" "$swap_status"
  else
    print_status "Swap" "Not configured" "info"
  fi
}

# ==============================================================================
# Disk Information
# ==============================================================================

check_disk() {
  print_section "💿 Disk Usage"
  
  local overall_status="good"
  
  # Using df to get disk usage
  while IFS= read -r line; do
    local filesystem size used avail percent mount
    filesystem=$(echo "$line" | awk '{print $1}')
    size=$(echo "$line" | awk '{print $2}')
    used=$(echo "$line" | awk '{print $3}')
    avail=$(echo "$line" | awk '{print $4}')
    percent=$(echo "$line" | awk '{print $5}' | tr -d '%')
    mount=$(echo "$line" | awk '{print $6}')
    
    local status
    status=$(get_status_by_threshold "$percent" "$DISK_WARNING" "$DISK_CRITICAL")
    
    if [ "$status" = "critical" ]; then
      overall_status="critical"
    elif [ "$status" = "warning" ] && [ "$overall_status" != "critical" ]; then
      overall_status="warning"
    fi
    
    print_status "$mount" "${used}/${size} (${percent}%)" "$status"
    
    if [ "$VERBOSE" = true ]; then
      echo -e "     ${CYAN}→ Device: $filesystem, Available: $avail${NC}"
    fi
    
  done < <(df -h --output=source,size,used,avail,pcent,target -x tmpfs -x devtmpfs -x squashfs 2>/dev/null | tail -n +2)
  
  # Disk health (if smartctl is available)
  if [ "$VERBOSE" = true ] && command -v smartctl &>/dev/null; then
    echo ""
    echo -e "  ${BOLD}Disk Health (S.M.A.R.T.):${NC}"
    
    for disk in /dev/sd?; do
      if [ -b "$disk" ]; then
        local smart_status
        smart_status=$(smartctl -H "$disk" 2>/dev/null | grep -i "SMART overall-health" | awk -F: '{print $2}' | xargs || echo "Unknown")
        if [ "$smart_status" = "PASSED" ]; then
          print_status "$disk" "$smart_status" "good"
        elif [ "$smart_status" = "Unknown" ]; then
          print_status "$disk" "N/A (requires root)" "info"
        else
          print_status "$disk" "$smart_status" "critical"
        fi
      fi
    done
  fi
}

# ==============================================================================
# Network Information
# ==============================================================================

check_network() {
  print_section "🌐 Network Status"
  
  # List network interfaces
  local primary_if
  primary_if=$(ip route | grep default | awk '{print $5}' | head -1 || echo "")
  
  while IFS= read -r iface; do
    [ -z "$iface" ] && continue
    [ "$iface" = "lo" ] && continue
    
    local ip_addr state
    ip_addr=$(ip -4 addr show "$iface" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1 || echo "No IP")
    state=$(cat /sys/class/net/"$iface"/operstate 2>/dev/null || echo "unknown")
    
    local status="info"
    [ "$state" = "up" ] && status="good"
    [ "$state" = "down" ] && status="warning"
    
    local label="$iface"
    [ "$iface" = "$primary_if" ] && label="$iface (primary)"
    
    print_status "$label" "$ip_addr [$state]" "$status"
    
    if [ "$VERBOSE" = true ]; then
      local mac_addr
      mac_addr=$(cat /sys/class/net/"$iface"/address 2>/dev/null || echo "Unknown")
      echo -e "     ${CYAN}→ MAC: $mac_addr${NC}"
    fi
    
  done < <(ls /sys/class/net/ 2>/dev/null)
  
  # Internet connectivity test
  echo ""
  echo -e "  ${BOLD}Connectivity:${NC}"
  
  if ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
    print_status "Internet (IPv4)" "Connected" "good"
  else
    print_status "Internet (IPv4)" "Not reachable" "critical"
  fi
  
  if ping -c 1 -W 2 google.com &>/dev/null; then
    print_status "DNS Resolution" "Working" "good"
  else
    print_status "DNS Resolution" "Failed" "warning"
  fi
  
  # Show default gateway
  local gateway
  gateway=$(ip route | grep default | awk '{print $3}' | head -1 || echo "None")
  print_status "Default Gateway" "$gateway" "info"
}

# ==============================================================================
# Services Status
# ==============================================================================

check_services() {
  print_section "⚙️  Critical Services"
  
  # List of critical services to check
  local services=("ssh" "sshd" "systemd-resolved" "NetworkManager" "cron" "rsyslog")
  
  for service in "${services[@]}"; do
    if systemctl list-unit-files 2>/dev/null | grep -qw "$service"; then
      local status
      if systemctl is-active --quiet "$service" 2>/dev/null; then
        print_status "$service" "Running" "good"
      elif systemctl is-enabled --quiet "$service" 2>/dev/null; then
        print_status "$service" "Stopped (enabled)" "warning"
      else
        print_status "$service" "Stopped (disabled)" "info"
      fi
    fi
  done
  
  # Failed services
  local failed_services
  failed_services=$(systemctl --failed --no-legend 2>/dev/null | wc -l || echo "0")
  
  if [ "$failed_services" -gt 0 ]; then
    print_status "Failed Services" "$failed_services service(s)" "critical"
    
    if [ "$VERBOSE" = true ]; then
      echo ""
      echo -e "  ${RED}Failed services list:${NC}"
      systemctl --failed --no-legend 2>/dev/null | while read -r line; do
        echo -e "     ${RED}→ $(echo "$line" | awk '{print $1}')${NC}"
      done
    fi
  else
    print_status "Failed Services" "None" "good"
  fi
}

# ==============================================================================
# Battery Status (if applicable)
# ==============================================================================

check_battery() {
  local battery_path="/sys/class/power_supply/BAT0"
  
  if [ -d "$battery_path" ] || [ -d "/sys/class/power_supply/BAT1" ]; then
    [ -d "/sys/class/power_supply/BAT1" ] && battery_path="/sys/class/power_supply/BAT1"
    
    print_section "🔋 Battery Status"
    
    local capacity status
    capacity=$(cat "$battery_path/capacity" 2>/dev/null || echo "Unknown")
    status=$(cat "$battery_path/status" 2>/dev/null || echo "Unknown")
    
    local bat_status="good"
    [ "$capacity" != "Unknown" ] && [ "$capacity" -lt 20 ] && bat_status="critical"
    [ "$capacity" != "Unknown" ] && [ "$capacity" -lt 50 ] && bat_status="warning"
    
    print_status "Current Charge" "${capacity}%" "$bat_status"
    print_status "Status" "$status" "info"
    
    # Battery Health - Design vs Full Capacity
    local energy_full energy_full_design health_percent
    
    # Try energy-based values first (in µWh)
    if [ -f "$battery_path/energy_full" ] && [ -f "$battery_path/energy_full_design" ]; then
      energy_full=$(cat "$battery_path/energy_full" 2>/dev/null || echo "0")
      energy_full_design=$(cat "$battery_path/energy_full_design" 2>/dev/null || echo "0")
    # Fall back to charge-based values (in µAh)
    elif [ -f "$battery_path/charge_full" ] && [ -f "$battery_path/charge_full_design" ]; then
      energy_full=$(cat "$battery_path/charge_full" 2>/dev/null || echo "0")
      energy_full_design=$(cat "$battery_path/charge_full_design" 2>/dev/null || echo "0")
    else
      energy_full=0
      energy_full_design=0
    fi
    
    if [ "$energy_full_design" -gt 0 ] && [ "$energy_full" -gt 0 ]; then
      health_percent=$((energy_full * 100 / energy_full_design))
      
      local health_status="good"
      [ "$health_percent" -lt 80 ] && health_status="warning"
      [ "$health_percent" -lt 50 ] && health_status="critical"
      
      # Convert to Wh for display
      local full_wh design_wh
      full_wh=$(echo "scale=2; $energy_full / 1000000" | bc)
      design_wh=$(echo "scale=2; $energy_full_design / 1000000" | bc)
      
      print_status "Battery Health" "${health_percent}%" "$health_status"
      print_status "Current Capacity" "${full_wh} Wh" "info"
      print_status "Design Capacity" "${design_wh} Wh" "info"
      
      # Health interpretation
      if [ "$health_percent" -ge 80 ]; then
        print_status "Condition" "Excellent - Battery in good health" "good"
      elif [ "$health_percent" -ge 60 ]; then
        print_status "Condition" "Good - Normal wear" "good"
      elif [ "$health_percent" -ge 40 ]; then
        print_status "Condition" "Fair - Consider replacement soon" "warning"
      else
        print_status "Condition" "Poor - Replace battery" "critical"
      fi
    fi
    
    # Cycle count (if available)
    if [ -f "$battery_path/cycle_count" ]; then
      local cycles
      cycles=$(cat "$battery_path/cycle_count" 2>/dev/null || echo "0")
      if [ "$cycles" != "0" ]; then
        local cycle_status="good"
        [ "$cycles" -gt 500 ] && cycle_status="warning"
        [ "$cycles" -gt 1000 ] && cycle_status="critical"
        print_status "Charge Cycles" "$cycles" "$cycle_status"
      fi
    fi
    
    # Voltage and Power info
    local voltage power_now
    if [ -f "$battery_path/voltage_now" ]; then
      voltage=$(cat "$battery_path/voltage_now" 2>/dev/null || echo "0")
      voltage=$(echo "scale=2; $voltage / 1000000" | bc)
      print_status "Voltage" "${voltage}V" "info"
    fi
    
    if [ -f "$battery_path/power_now" ]; then
      power_now=$(cat "$battery_path/power_now" 2>/dev/null || echo "0")
      power_now=$(echo "scale=2; $power_now / 1000000" | bc)
      print_status "Power Draw" "${power_now}W" "info"
    fi
    
    # Time remaining estimation using upower if available
    if command -v upower &>/dev/null; then
      local battery_device time_to_empty time_to_full
      battery_device=$(upower -e 2>/dev/null | grep BAT | head -1)
      
      if [ -n "$battery_device" ]; then
        if [ "$status" = "Discharging" ]; then
          time_to_empty=$(upower -i "$battery_device" 2>/dev/null | grep "time to empty" | awk '{print $4, $5}')
          [ -n "$time_to_empty" ] && print_status "Time Remaining" "$time_to_empty" "info"
        elif [ "$status" = "Charging" ]; then
          time_to_full=$(upower -i "$battery_device" 2>/dev/null | grep "time to full" | awk '{print $4, $5}')
          [ -n "$time_to_full" ] && print_status "Time to Full" "$time_to_full" "info"
        fi
      fi
    fi
    
    # Technology
    if [ -f "$battery_path/technology" ]; then
      local tech
      tech=$(cat "$battery_path/technology" 2>/dev/null || echo "Unknown")
      [ "$VERBOSE" = true ] && print_status "Technology" "$tech" "info"
    fi
    
    # Manufacturer info (verbose only)
    if [ "$VERBOSE" = true ]; then
      if [ -f "$battery_path/manufacturer" ]; then
        local manufacturer
        manufacturer=$(cat "$battery_path/manufacturer" 2>/dev/null || echo "Unknown")
        print_status "Manufacturer" "$manufacturer" "info"
      fi
      if [ -f "$battery_path/model_name" ]; then
        local model
        model=$(cat "$battery_path/model_name" 2>/dev/null || echo "Unknown")
        print_status "Model" "$model" "info"
      fi
    fi
  fi
}

# ==============================================================================
# Recent Errors
# ==============================================================================

check_recent_errors() {
  print_section "📋 Recent System Issues"
  
  # Count recent errors from journalctl (last hour)
  local errors warnings
  errors=$(journalctl -p err --since "1 hour ago" --no-pager 2>/dev/null | wc -l || echo "0")
  warnings=$(journalctl -p warning --since "1 hour ago" --no-pager 2>/dev/null | wc -l || echo "0")
  
  local error_status="good"
  [ "$errors" -gt 10 ] && error_status="warning"
  [ "$errors" -gt 50 ] && error_status="critical"
  
  print_status "Errors (last hour)" "$errors" "$error_status"
  print_status "Warnings (last hour)" "$warnings" "info"
  
  if [ "$VERBOSE" = true ] && [ "$errors" -gt 0 ]; then
    echo ""
    echo -e "  ${BOLD}Recent errors:${NC}"
    journalctl -p err --since "1 hour ago" --no-pager -n 5 --output=short 2>/dev/null | while read -r line; do
      echo -e "     ${RED}$line${NC}"
    done
  fi
  
  # Check for high priority kernel messages
  local kern_errors
  kern_errors=$(dmesg -l err,crit,alert,emerg 2>/dev/null | tail -5 | wc -l || echo "0")
  
  if [ "$kern_errors" -gt 0 ]; then
    print_status "Kernel Errors" "$kern_errors recent messages" "warning"
  else
    print_status "Kernel Errors" "None" "good"
  fi
}

# ==============================================================================
# Security Overview
# ==============================================================================

check_security() {
  print_section "🔒 Security Overview"
  
  # Check for pending updates
  if command -v apt &>/dev/null; then
    local updates security_updates
    updates=$(apt list --upgradable 2>/dev/null | tail -n +2 | wc -l || echo "0")
    security_updates=$(apt list --upgradable 2>/dev/null | grep -i security | wc -l || echo "0")
    
    local update_status="good"
    [ "$security_updates" -gt 0 ] && update_status="warning"
    [ "$security_updates" -gt 10 ] && update_status="critical"
    
    print_status "Pending Updates" "$updates package(s)" "info"
    print_status "Security Updates" "$security_updates package(s)" "$update_status"
  fi
  
  # Firewall status
  if command -v ufw &>/dev/null; then
    local ufw_status
    ufw_status=$(ufw status 2>/dev/null | head -1 || echo "Unknown")
    if echo "$ufw_status" | grep -qi "active"; then
      print_status "Firewall (UFW)" "Active" "good"
    else
      print_status "Firewall (UFW)" "Inactive" "warning"
    fi
  elif command -v iptables &>/dev/null; then
    local iptables_rules
    iptables_rules=$(iptables -L 2>/dev/null | wc -l || echo "0")
    print_status "Firewall (iptables)" "$iptables_rules rules" "info"
  fi
  
  # Last login attempts
  if [ "$VERBOSE" = true ]; then
    local failed_logins
    failed_logins=$(journalctl -u sshd --since "24 hours ago" 2>/dev/null | grep -i "failed" | wc -l || echo "0")
    print_status "Failed SSH (24h)" "$failed_logins attempt(s)" "info"
  fi
}

# ==============================================================================
# Summary
# ==============================================================================

display_summary() {
  print_header "📊 System Health Summary"
  
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo ""
  echo -e "  ${BOLD}Report generated:${NC} $timestamp"
  echo ""
  
  # Quick status indicators
  local cpu_usage mem_percent
  cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print 100 - $8}' 2>/dev/null | cut -d. -f1 || echo "0")
  mem_percent=$(free | grep Mem | awk '{print int($3/$2 * 100)}' 2>/dev/null || echo "0")
  
  local disk_max=0
  while read -r percent; do
    percent=$(echo "$percent" | tr -d '%')
    [ "$percent" -gt "$disk_max" ] && disk_max="$percent"
  done < <(df -h --output=pcent -x tmpfs -x devtmpfs -x squashfs 2>/dev/null | tail -n +2)
  
  echo -e "  ${BOLD}Quick Status:${NC}"
  
  local overall_cpu overall_mem overall_disk
  overall_cpu=$(get_status_by_threshold "$cpu_usage" "$CPU_WARNING" "$CPU_CRITICAL")
  overall_mem=$(get_status_by_threshold "$mem_percent" "$MEM_WARNING" "$MEM_CRITICAL")
  overall_disk=$(get_status_by_threshold "$disk_max" "$DISK_WARNING" "$DISK_CRITICAL")
  
  print_status "CPU" "${cpu_usage}%" "$overall_cpu"
  print_status "Memory" "${mem_percent}%" "$overall_mem"
  print_status "Disk (max)" "${disk_max}%" "$overall_disk"
  
  # Overall system health
  local overall_health="good"
  local health_color="$GREEN"
  local health_icon="✅"
  
  if [ "$overall_cpu" = "critical" ] || [ "$overall_mem" = "critical" ] || [ "$overall_disk" = "critical" ]; then
    overall_health="CRITICAL"
    health_color="$RED"
    health_icon="🚨"
  elif [ "$overall_cpu" = "warning" ] || [ "$overall_mem" = "warning" ] || [ "$overall_disk" = "warning" ]; then
    overall_health="WARNING"
    health_color="$YELLOW"
    health_icon="⚠️ "
  else
    overall_health="HEALTHY"
  fi
  
  echo ""
  echo -e "  ${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "  ${BOLD}Overall System Status:${NC} ${health_color}${health_icon} ${overall_health}${NC}"
  echo -e "  ${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
}

# ==============================================================================
# JSON Output
# ==============================================================================

output_json() {
  local cpu_usage mem_total mem_used disk_usage
  
  cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print 100 - $8}' 2>/dev/null || echo "0")
  mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
  mem_available=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
  mem_used=$((mem_total - mem_available))
  mem_percent=$((mem_used * 100 / mem_total))
  
  cat <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "hostname": "$(hostname)",
  "system": {
    "os": "$(grep -E "^PRETTY_NAME=" /etc/os-release 2>/dev/null | cut -d'"' -f2)",
    "kernel": "$(uname -r)",
    "uptime": "$(uptime -p | sed 's/up //')"
  },
  "cpu": {
    "model": "$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | xargs)",
    "cores": $(nproc),
    "usage_percent": $cpu_usage
  },
  "memory": {
    "total_kb": $mem_total,
    "used_kb": $mem_used,
    "usage_percent": $mem_percent
  },
  "disks": [
$(df -h --output=target,pcent -x tmpfs -x devtmpfs -x squashfs 2>/dev/null | tail -n +2 | awk '{printf "    {\"mount\": \"%s\", \"usage_percent\": %d},\n", $1, $2}' | sed '$ s/,$//')
  ]
}
EOF
}

# ==============================================================================
# Argument Parsing
# ==============================================================================

parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      -v|--verbose)
        VERBOSE=true
        shift ;;
      -w|--watch)
        WATCH_MODE=true
        if [[ "${2:-}" =~ ^[0-9]+$ ]]; then
          WATCH_INTERVAL="$2"
          shift
        fi
        shift ;;
      -j|--json)
        JSON_OUTPUT=true
        shift ;;
      -h|--help)
        display_help
        exit 0 ;;
      --version)
        display_version
        exit 0 ;;
      *)
        echo -e "${RED}[ERROR]${NC} Unrecognized option: $1"
        display_help
        exit 1 ;;
    esac
  done
}

# ==============================================================================
# Main
# ==============================================================================

run_health_check() {
  if [ "$JSON_OUTPUT" = true ]; then
    output_json
    return
  fi
  
  clear
  
  print_header "🏥 PC Health Check - $(hostname)"
  
  check_system_info
  check_cpu
  check_memory
  check_disk
  check_network
  check_services
  check_battery
  check_recent_errors
  check_security
  display_summary
}

main() {
  parse_arguments "$@"
  
  if [ "$WATCH_MODE" = true ]; then
    echo -e "${CYAN}${BOLD}Watch mode enabled. Refreshing every ${WATCH_INTERVAL}s. Press Ctrl+C to exit.${NC}"
    sleep 2
    
    while true; do
      run_health_check
      echo -e "\n${CYAN}Next refresh in ${WATCH_INTERVAL}s... (Ctrl+C to exit)${NC}"
      sleep "$WATCH_INTERVAL"
    done
  else
    run_health_check
  fi
}

main "$@"
