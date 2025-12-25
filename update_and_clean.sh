#!/usr/bin/env bash

# ==============================================================================
# System Update and Cleanup Script v3.0.0
# ==============================================================================
# A robust utility for updating and cleaning Debian/Ubuntu-based Linux systems.
# Default: dry-run mode. Use --execute to perform actual changes.
# ==============================================================================

set -euo pipefail

# Configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly LOG_FILE="/var/log/update_and_clean.log"
readonly VERSION="3.0.0"

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# Mode flags - Default: run all (update + clean)
UPDATE_ACTION=true
CLEAN_ACTION=true
EXECUTE_MODE=false  # Default is dry-run
VERBOSE=false

# Warning/Unsafe handling flags
SKIP_WARNINGS=false
SKIP_UNSAFE=false
DO_WARNINGS=false
DO_UNSAFE=false

# Action queues
declare -a SAFE_ACTIONS=()
declare -a WARNING_ACTIONS=()
declare -a UNSAFE_ACTIONS=()
declare -a SAFE_ACTION_NAMES=()
declare -a WARNING_ACTION_NAMES=()
declare -a UNSAFE_ACTION_NAMES=()

# ==============================================================================
# Utility Functions
# ==============================================================================

log() {
  local level="$1"
  local message="$2"
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  
  case "$level" in
    INFO)    echo -e "${GREEN}[INFO]${NC} $message" ;;
    WARN)    echo -e "${YELLOW}[WARN]${NC} $message" ;;
    ERROR)   echo -e "${RED}[ERROR]${NC} $message" >&2 ;;
    DEBUG)   [ "$VERBOSE" = true ] && echo -e "${BLUE}[DEBUG]${NC} $message" ;;
    SUCCESS) echo -e "${GREEN}${BOLD}[SUCCESS]${NC} $message" ;;
  esac
  
  echo "[$timestamp] [$level] $message" >> "$LOG_FILE" 2>/dev/null || true
}

# Queue actions by safety level
queue_safe() {
  local name="$1"
  shift
  SAFE_ACTIONS+=("$*")
  SAFE_ACTION_NAMES+=("$name")
}

queue_warning() {
  local name="$1"
  local reason="$2"
  shift 2
  WARNING_ACTIONS+=("$*")
  WARNING_ACTION_NAMES+=("$name|$reason")
}

queue_unsafe() {
  local name="$1"
  local reason="$2"
  shift 2
  UNSAFE_ACTIONS+=("$*")
  UNSAFE_ACTION_NAMES+=("$name|$reason")
}

# Execute a command
run_cmd() {
  log "DEBUG" "Executing: $*"
  "$@"
}

# Confirm action from user
confirm() {
  local message="$1"
  local response
  
  echo -e "${YELLOW}$message${NC} (yes/no): "
  read -r response
  response=$(echo "$response" | tr '[:upper:]' '[:lower:]')
  [[ "$response" == "y" || "$response" == "yes" ]]
}

display_help() {
  echo -e "${BOLD}${SCRIPT_NAME} v${VERSION}${NC} - System Update and Cleanup Utility"
  echo ""
  echo -e "${BOLD}Usage:${NC} sudo $SCRIPT_NAME [OPTIONS]"
  echo ""
  echo -e "${BOLD}Mode Options:${NC}"
  echo "  -u, --update        Run only system update (skip cleanup)"
  echo "  -c, --clean         Run only system cleanup (skip update)"
  echo "  --execute           Actually perform changes (default is dry-run)"
  echo ""
  echo -e "${BOLD}Warning/Unsafe Handling:${NC}"
  echo "  --skip-warnings     Skip all warning-level actions"
  echo "  --skip-unsafe       Skip all unsafe actions"
  echo "  --do-warnings       Auto-execute warning actions without prompting"
  echo "  --do-unsafe         Auto-execute unsafe actions without prompting"
  echo ""
  echo -e "${BOLD}Other Options:${NC}"
  echo "  -v, --verbose       Enable verbose output"
  echo "  -h, --help          Display this help message"
  echo "  --version           Display version information"
  echo ""
  echo -e "${BOLD}Execution Flow:${NC}"
  echo "  1. Script runs in DRY-RUN mode by default (safe preview)"
  echo "  2. Use --execute to actually perform changes"
  echo "  3. Safe actions run automatically"
  echo "  4. Warning actions prompt for confirmation (or use --do-warnings/--skip-warnings)"
  echo "  5. Unsafe actions prompt for confirmation (or use --do-unsafe/--skip-unsafe)"
  echo ""
  echo -e "${BOLD}Examples:${NC}"
  echo "  sudo $SCRIPT_NAME                            # Dry-run preview (update + clean)"
  echo "  sudo $SCRIPT_NAME --execute                  # Execute with prompts"
  echo "  sudo $SCRIPT_NAME --execute --do-warnings    # Auto-approve warnings"
  echo "  sudo $SCRIPT_NAME -u --execute               # Update only"
  echo ""
  echo "Log file: $LOG_FILE"
}

display_version() {
  echo "$SCRIPT_NAME version $VERSION"
}

# ==============================================================================
# Core Functions
# ==============================================================================

check_root() {
  if [ "$(id -u)" != "0" ]; then
    log "ERROR" "This script must be run with sudo or as root."
    exit 1
  fi
}

init_log() {
  local log_dir
  log_dir=$(dirname "$LOG_FILE")
  [ ! -d "$log_dir" ] && mkdir -p "$log_dir" 2>/dev/null || true
  [ ! -f "$LOG_FILE" ] && touch "$LOG_FILE" 2>/dev/null || true
  
  log "INFO" "========== Script started =========="
  log "INFO" "Mode: $([ "$EXECUTE_MODE" = true ] && echo 'EXECUTE' || echo 'DRY-RUN')"
}

get_current_kernel() {
  uname -r
}

get_kernel_base() {
  echo "$1" | sed 's/-[a-z]*$//'
}

# ==============================================================================
# Analysis Phase - Queue all actions by safety level
# ==============================================================================

analyze_update() {
  log "INFO" "Analyzing system update..."
  queue_safe "Update package lists" apt-get update
  queue_safe "Upgrade packages" apt-get upgrade -y
  log "INFO" "Update analysis complete."
}

analyze_clean() {
  log "INFO" "Analyzing system cleanup..."
  
  # Safe actions
  queue_safe "Remove unused packages" apt-get autoremove -y
  queue_safe "Clean APT cache" apt-get clean
  queue_safe "Deep clean obsolete packages" apt-get autoremove --purge -y
  
  # Analyze kernels
  local current_kernel current_kernel_base old_kernels=""
  current_kernel=$(get_current_kernel)
  current_kernel_base=$(get_kernel_base "$current_kernel")
  
  log "DEBUG" "Current kernel: $current_kernel (base: $current_kernel_base)"
  
  while IFS= read -r line; do
    local pkg_name
    pkg_name=$(echo "$line" | awk '{print $2}')
    
    if echo "$pkg_name" | grep -q "$current_kernel_base"; then
      continue
    fi
    
    if echo "$pkg_name" | grep -qE '^linux-image-[0-9]+\.[0-9]+'; then
      old_kernels="$old_kernels $pkg_name"
    fi
  done < <(dpkg --list 'linux-image-*' 2>/dev/null | grep '^ii' || true)
  
  old_kernels=$(echo "$old_kernels" | xargs)
  
  if [ -n "$old_kernels" ]; then
    if echo "$old_kernels" | grep -q "$current_kernel"; then
      queue_unsafe "Remove old kernels" "CRITICAL: Current kernel detected in removal list!" apt-get purge -y $old_kernels
    else
      queue_warning "Remove old kernels" "Kernels to remove: $old_kernels" apt-get purge -y $old_kernels
    fi
  fi
  
  # Analyze orphaned configs
  local orphaned_packages
  orphaned_packages=$(dpkg --list 2>/dev/null | grep '^rc' | awk '{print $2}' | tr '\n' ' ' || true)
  # Trim whitespace
  orphaned_packages=$(echo "$orphaned_packages" | xargs)
  
  if [ -n "$orphaned_packages" ]; then
    local orphan_count
    orphan_count=$(echo "$orphaned_packages" | wc -w)
    queue_warning "Purge orphaned configs" "$orphan_count package config(s) to remove" dpkg --purge $orphaned_packages
  fi
  
  log "INFO" "Cleanup analysis complete."
}

# ==============================================================================
# Display Summary
# ==============================================================================

display_summary() {
  echo ""
  echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}${BOLD}║                        ACTION SUMMARY                             ║${NC}"
  echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════════════╝${NC}"
  echo ""
  
  # Safe actions
  if [ ${#SAFE_ACTIONS[@]} -gt 0 ]; then
    echo -e "${GREEN}${BOLD}✅ SAFE ACTIONS (${#SAFE_ACTIONS[@]}):${NC} Will execute automatically"
    for name in "${SAFE_ACTION_NAMES[@]}"; do
      echo -e "   ${GREEN}→${NC} $name"
    done
    echo ""
  fi
  
  # Warning actions
  if [ ${#WARNING_ACTIONS[@]} -gt 0 ]; then
    echo -e "${YELLOW}${BOLD}⚠️  WARNING ACTIONS (${#WARNING_ACTIONS[@]}):${NC} Require confirmation"
    for entry in "${WARNING_ACTION_NAMES[@]}"; do
      local name reason
      name="${entry%%|*}"
      reason="${entry#*|}"
      echo -e "   ${YELLOW}!${NC} $name"
      echo -e "      ${YELLOW}Reason:${NC} $reason"
    done
    echo ""
  fi
  
  # Unsafe actions
  if [ ${#UNSAFE_ACTIONS[@]} -gt 0 ]; then
    echo -e "${RED}${BOLD}🚨 UNSAFE ACTIONS (${#UNSAFE_ACTIONS[@]}):${NC} Require explicit confirmation"
    for entry in "${UNSAFE_ACTION_NAMES[@]}"; do
      local name reason
      name="${entry%%|*}"
      reason="${entry#*|}"
      echo -e "   ${RED}✗${NC} $name"
      echo -e "      ${RED}Reason:${NC} $reason"
    done
    echo ""
  fi
  
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  
  if [ "$EXECUTE_MODE" = false ]; then
    echo -e "${BLUE}${BOLD}📋 DRY-RUN MODE${NC} - No changes made"
    echo ""
    echo -e "   To execute: ${CYAN}sudo $SCRIPT_NAME --execute${NC}"
    if [ ${#WARNING_ACTIONS[@]} -gt 0 ]; then
      echo -e "   Auto-approve warnings: ${CYAN}--do-warnings${NC}"
      echo -e "   Skip warnings: ${CYAN}--skip-warnings${NC}"
    fi
    if [ ${#UNSAFE_ACTIONS[@]} -gt 0 ]; then
      echo -e "   Auto-approve unsafe: ${CYAN}--do-unsafe${NC}"
      echo -e "   Skip unsafe: ${CYAN}--skip-unsafe${NC}"
    fi
  fi
  
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
}

# ==============================================================================
# Execution Phase
# ==============================================================================

execute_actions() {
  echo ""
  log "INFO" "========== EXECUTING ACTIONS =========="
  echo ""
  
  # Execute safe actions
  if [ ${#SAFE_ACTIONS[@]} -gt 0 ]; then
    log "SUCCESS" "Executing ${#SAFE_ACTIONS[@]} safe action(s)..."
    for i in "${!SAFE_ACTIONS[@]}"; do
      local name="${SAFE_ACTION_NAMES[$i]}"
      local cmd="${SAFE_ACTIONS[$i]}"
      log "INFO" "→ $name"
      eval "$cmd"
    done
    echo ""
  fi
  
  # Execute warning actions
  if [ ${#WARNING_ACTIONS[@]} -gt 0 ]; then
    echo -e "${YELLOW}${BOLD}Processing warning actions...${NC}"
    for i in "${!WARNING_ACTIONS[@]}"; do
      local entry="${WARNING_ACTION_NAMES[$i]}"
      local name="${entry%%|*}"
      local reason="${entry#*|}"
      local cmd="${WARNING_ACTIONS[$i]}"
      
      echo ""
      echo -e "${YELLOW}⚠️  $name${NC}"
      echo -e "   Reason: $reason"
      
      if [ "$SKIP_WARNINGS" = true ]; then
        log "INFO" "Skipping (--skip-warnings): $name"
        continue
      elif [ "$DO_WARNINGS" = true ]; then
        log "INFO" "Auto-executing (--do-warnings): $name"
        eval "$cmd"
      elif confirm "   Execute this action?"; then
        log "INFO" "Executing: $name"
        eval "$cmd"
      else
        log "INFO" "Skipped by user: $name"
      fi
    done
    echo ""
  fi
  
  # Execute unsafe actions
  if [ ${#UNSAFE_ACTIONS[@]} -gt 0 ]; then
    echo -e "${RED}${BOLD}Processing unsafe actions...${NC}"
    for i in "${!UNSAFE_ACTIONS[@]}"; do
      local entry="${UNSAFE_ACTION_NAMES[$i]}"
      local name="${entry%%|*}"
      local reason="${entry#*|}"
      local cmd="${UNSAFE_ACTIONS[$i]}"
      
      echo ""
      echo -e "${RED}🚨 $name${NC}"
      echo -e "   ${RED}WARNING:${NC} $reason"
      
      if [ "$SKIP_UNSAFE" = true ]; then
        log "INFO" "Skipping (--skip-unsafe): $name"
        continue
      elif [ "$DO_UNSAFE" = true ]; then
        log "WARN" "Auto-executing unsafe action (--do-unsafe): $name"
        eval "$cmd"
      elif confirm "   ⚠️  This is UNSAFE. Are you absolutely sure?"; then
        log "WARN" "User confirmed unsafe action: $name"
        eval "$cmd"
      else
        log "INFO" "Skipped by user: $name"
      fi
    done
    echo ""
  fi
  
  log "SUCCESS" "========== EXECUTION COMPLETE =========="
}

# ==============================================================================
# Argument Parsing
# ==============================================================================

parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      -u|--update)
        CLEAN_ACTION=false
        shift ;;
      -c|--clean)
        UPDATE_ACTION=false
        shift ;;
      --execute)
        EXECUTE_MODE=true
        shift ;;
      --skip-warnings)
        SKIP_WARNINGS=true
        shift ;;
      --skip-unsafe)
        SKIP_UNSAFE=true
        shift ;;
      --do-warnings)
        DO_WARNINGS=true
        shift ;;
      --do-unsafe)
        DO_UNSAFE=true
        shift ;;
      -v|--verbose)
        VERBOSE=true
        shift ;;
      -h|--help)
        display_help
        exit 0 ;;
      --version)
        display_version
        exit 0 ;;
      *)
        log "ERROR" "Unrecognized option: $1"
        display_help
        exit 1 ;;
    esac
  done
}

# ==============================================================================
# Main
# ==============================================================================

main() {
  parse_arguments "$@"
  check_root
  init_log
  

  
  # Analysis phase - always runs
  [ "$UPDATE_ACTION" = true ] && analyze_update
  [ "$CLEAN_ACTION" = true ] && analyze_clean
  
  # Display summary
  display_summary
  
  # Execution phase - only if --execute
  if [ "$EXECUTE_MODE" = true ]; then
    execute_actions
  fi
  
  log "INFO" "========== Script completed =========="
}

main "$@"