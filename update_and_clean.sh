#!/bin/bash

# Function to display help
display_help() {
  echo "Usage: $0 [option]"
  echo "Options:"
  echo "  -a, --all       Run the full script without user interaction."
  echo "  -u, --update    Run only the update part of the script."
  echo "  -c, --clean     Run only the cleanup part of the script."
  echo "  -h, --help      Display this help and exit."
  echo
  echo "This script updates and cleans up the system. Requires root privileges."
}

# Check if the script is executed with root (sudo) privileges
if [ "$(id -u)" != "0" ]; then
  echo "This script must be run with sudo or as root."
  exit 1
fi

# Initialize variables
UPDATE_ACTION=false
CLEAN_ACTION=false
ASK_USER=true

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -a|--all)
      UPDATE_ACTION=true
      CLEAN_ACTION=true
      ASK_USER=false
      shift # Remove --all from processing
      ;;
    -u|--update)
      UPDATE_ACTION=true
      ASK_USER=false
      shift # Remove --update from processing
      ;;
    -c|--clean)
      CLEAN_ACTION=true
      ASK_USER=false
      shift # Remove --clean from processing
      ;;
    -h|--help)
      display_help
      exit 0
      ;;
    *) # Handle unrecognized options
      echo "Error: Unrecognized option $1"
      display_help
      exit 1
      ;;
  esac
done

# Function to handle updating
run_update() {
  echo "Running system update..."
  apt update
  apt upgrade -y
  echo "System update completed."
}

# Function to handle cleaning
run_clean() {
  # Remove unused packages and orphaned dependencies
  echo "Removing unused packages and orphaned dependencies..."
  apt-get autoremove -y

  # Clean the APT cache to remove downloaded package files that are no longer needed
  echo "Cleaning up APT cache..."
  apt-get clean

  # Remove old kernels except the one currently in use (This step requires careful attention to avoid removing necessary kernels)
  echo "Removing old kernels except the current one..."
  CURRENT_KERNEL=$(uname -r | sed 's/-[a-z]*$//')
  OLD_KERNELS=$(dpkg --list | awk '{print $2}' | grep -E 'linux-image-[0-9]+' | grep -v "$CURRENT_KERNEL" | tr '\n' ' ')
  if [ -n "$OLD_KERNELS" ]; then
    apt-get purge -y $OLD_KERNELS
  else
    echo "No old kernels found to remove."
  fi

  # Clean up obsolete packages (packages that are no longer in the repositories)
  echo "Cleaning up obsolete packages..."
  apt-get autoremove --purge -y

  # Clean up orphaned package configuration files
  echo "Cleaning up orphaned package configuration files..."
  ORPHANED_PACKAGES=$(dpkg --list | grep '^rc' | awk '{print $2}')
  if [ -n "$ORPHANED_PACKAGES" ]; then
    echo "Orphaned package configuration files found. Purging..."
    echo "$ORPHANED_PACKAGES" | xargs dpkg --purge
  else
    echo "No orphaned package configuration files to remove."
  fi

  echo "Cleanup completed."
}

# Execute actions based on arguments or user input
if [ "$ASK_USER" = true ]; then
  echo "Do you want to update? (yes/no)"
  read response
  response=$(echo "$response" | tr '[:upper:]' '[:lower:]')

  if [[ "$response" == "y" || "$response" == "yes" ]]; then
    run_update
  else
    echo "Update skipped."
  fi

  echo "Do you want to clean up? (yes/no)"
  read response
  response=$(echo "$response" | tr '[:upper:]' '[:lower:]')

  if [[ "$response" == "y" || "$response" == "yes" ]]; then
    run_clean
  else
    echo "Cleanup skipped."
  fi
else
  if [ "$UPDATE_ACTION" = true ]; then
    run_update
  fi

  if [ "$CLEAN_ACTION" = true ]; then
    run_clean
  fi
fi