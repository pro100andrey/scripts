#!/bin/bash

# This script controls the NZXT Smart Device to set the fan speed.

# Exit on error, undefined variables, or pipe failures
set -euo pipefail

# Configuration
readonly DEVICE="NZXT Smart Device"
readonly FANS=(fan1 fan2 fan3)

# Temperature thresholds and corresponding fan speeds 
# (Celsius to percentage mapping)
declare -A FAN_CURVE=(
  [70]=100
  [60]=80
  [50]=60
  [40]=40
  [0]=30
)

# How often to check temperature and update fan speed (in seconds)
readonly CHECK_INTERVAL_SECONDS=5

# Log messages with timestamp
function info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') | INFO | $*"
}

# Log error messages
function error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') | ERROR | $*" >&2
}
# Set the fan speed for configured fans on specified device.
# Arguments:
#   $1 - Speed percentage (0-100)
# Returns:
#   None
function set_fan_speed() {
    local speed="$1"
    local fan

    for fan in "${FANS[@]}"; do
      if ! liquidctl set "$fan" speed "${speed}" --match "${DEVICE}"; then
        error "Failed to set ${fan} speed for device '${DEVICE}'."
        # Optionally, you can exit here or try to continue with other fans
        # exit 1
      fi
    done
}

# Check if all required dependencies are installed.
function check_dependencies() {
    local cmd
    for cmd in sensors liquidctl awk grep bc tr; do
      if ! command -v "$cmd" >/dev/null 2>&1; then
        error "Required command '${cmd}' is not installed! Please install it."
        exit 1
      fi
    done
}

# Get the current CPU temperature.
# Returns:
#   CPU temperature in Celsius (float).
function get_cpu_temp() {
    local temp
    temp=$(sensors | grep 'Tctl:' | awk '{print $2}' | tr -d '+°C')

    if [[ -z "$temp" ]]; then
        error "ERROR: Could not retrieve CPU temperature!"
        exit 1
    fi

    echo "$temp"
}

# Calculate the fan speed based on CPU temperature and defined curve.
# Arguments:
#   $1 - CPU temperature in Celsius
# Returns:
#   Fan speed percentage (0-100)
function calculate_speed() {
  local temp="$1"
  local speed_to_set=0
  local threshold

  # Iterate through thresholds in descending order to find the highest applicable one
  # Bash array keys are not ordered, so we need to sort them numerically.
  local sorted_thresholds
  sorted_thresholds=$(for threshold in "${!FAN_CURVE[@]}"; do echo "$threshold"; done | sort -rn)

  for threshold in $sorted_thresholds; do
    if (( $(echo "$temp >= $threshold" | bc -l) )); then
      speed_to_set=${FAN_CURVE["$threshold"]}
      break # Found the appropriate speed, exit loop
    fi
  done

  # If no threshold was met (e.g., temp is very low), fall back to the lowest defined speed
  if [[ "$speed_to_set" -eq 0 ]]; then
      # Use 0 as a default key for the lowest speed, or default to 30 if not defined.
      speed_to_set=${FAN_CURVE[0]:-30}
  fi

  echo "$speed_to_set"
}


# Performs a single fan speed adjustment based on current temperature.
# Arguments: None
# Returns: None
function perform_single_adjustment() {
    local current_temp
    local desired_speed

    # Attempt to get temperature; if it fails, get_cpu_temp will return 1,
    # causing the 'if ! ...' condition to be true.
    if ! current_temp=$(get_cpu_temp); then
        # get_cpu_temp already logged an error. Here we exit the script.
        error "ERROR: Cannot proceed in single-shot mode without CPU temperature. Aborting."
        exit 1 # Crucial: Exit on failure for single-shot mode
    fi

    desired_speed=$(calculate_speed "$current_temp")
    set_fan_speed "$desired_speed"
    info "Fan speed set to ${desired_speed}% based on CPU temperature of ${current_temp}°C."
}

function run_continuous_mode() {
    info "Running in continuous mode..." # To avoid setting speed if it hasn't changed

    while true; do
      perform_single_adjustment

      info "Next check in ${CHECK_INTERVAL_SECONDS} seconds..."
      sleep "$CHECK_INTERVAL_SECONDS"
    done
}

function main() {
  check_dependencies

   # Check if running as a systemd service (SYSTEMD_EXEC_PID is typically set by systemd)
  if [[ -n "${SYSTEMD_EXEC_PID:-}" ]]; then
    run_continuous_mode
  else
    perform_single_adjustment
  fi
}

main "$@"