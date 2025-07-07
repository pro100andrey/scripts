#!/bin/bash

# This script controls the NZXT Smart Device to set the fan speed.

# Exit on error, undefined variables, or pipe failures
set -euo pipefail

# Configuration
readonly DEVICE="NZXT Smart Device"
readonly FANS=(fan1 fan2 fan3)

# Temperature thresholds and corresponding fan speeds
# (Celsius to percentage mapping)
# Ensure 0 is included for the lowest default speed if no other threshold is met.
declare -A FAN_CURVE=(
  [70]=100
  [60]=85
  [50]=65
  [40]=40
  [0]=30 # Default speed for temperatures 0C and below
)

# How often to check temperature and update fan speed (in seconds)
readonly CHECK_INTERVAL_SECONDS=10

# Log informational messages to stdout
function info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') | INFO | $*"
}

# Log error messages to stderr
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
        error "Failed to set ${fan} speed to ${speed}% for device '${DEVICE}'. Continuing with other fans."
        # Decided to continue with other fans instead of exiting.
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
    info "All required dependencies are installed."
}

# Get the current CPU temperature.
# Returns:
#   CPU temperature in Celsius (float). Returns 0 on success, 1 on failure.
function get_cpu_temp() {
    local temp_output
    # Add || true to prevent set -e from exiting if grep finds nothing
    temp_output=$(sensors | grep 'Tctl:' | awk '{print $2}' | tr -d '+°C' || true)

    if [[ -z "$temp_output" ]]; then
        error "Could not retrieve CPU temperature from 'sensors Tctl:' output."
        return 1 # Indicate failure
    fi

    echo "$temp_output"
    return 0 # Indicate success
}

# Calculate the fan speed based on CPU temperature and defined curve.
# Arguments:
#   $1 - CPU temperature in Celsius
# Returns:
#   Fan speed percentage (0-100)
function calculate_speed() {
  local temp="$1"
  # Default to the speed defined for 0C, or 30% if 0C is not a key in FAN_CURVE.
  local speed_to_set=${FAN_CURVE[0]:-30}
  local threshold

  # Iterate through thresholds in descending order to find the highest applicable one
  # Use printf to handle spaces in values properly if they were ever there
  local sorted_thresholds
  sorted_thresholds=$(printf "%s\n" "${!FAN_CURVE[@]}" | sort -rn)

  for threshold in $sorted_thresholds; do
    # Use bc -l for floating point comparison
    if (( $(echo "$temp >= $threshold" | bc -l) )); then
      speed_to_set=${FAN_CURVE["$threshold"]}
      break # Found the appropriate speed, exit loop
    fi
  done

  echo "$speed_to_set"
}

# Performs a single fan speed adjustment based on current temperature.
# Arguments: None
# Returns: None
function perform_single_adjustment() {
    local current_temp
    local desired_speed

    if ! current_temp=$(get_cpu_temp); then
        # get_cpu_temp already logged an error.
        # In single-shot mode, we usually want to exit on failure.
        error "Cannot proceed in single-shot mode without CPU temperature. Aborting."
        exit 1 # Crucial: Exit on failure for single-shot mode
    fi

    desired_speed=$(calculate_speed "$current_temp")
    set_fan_speed "$desired_speed"
    info "Fan speed set to ${desired_speed}% based on CPU temperature of ${current_temp}°C."
}

function run_continuous_mode() {
    info "Running in continuous mode..."
    local last_set_speed=-1 # Initialize with a value that won't match any valid speed

    while true; do
      local current_temp
      if ! current_temp=$(get_cpu_temp); then
          info "Could not retrieve CPU temperature. Skipping this iteration and will retry."
          sleep "$CHECK_INTERVAL_SECONDS"
          continue # Skip to the next iteration if temperature cannot be retrieved
      fi

      local desired_speed
      desired_speed=$(calculate_speed "$current_temp")

      # Only set fan speed if it has changed from the last setting
      if [[ "$desired_speed" -ne "$last_set_speed" ]]; then
        set_fan_speed "$desired_speed"
        info "Fan speed set to ${desired_speed}% based on CPU temperature of ${current_temp}°C."
        last_set_speed="$desired_speed"
      fi

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