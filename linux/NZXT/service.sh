#!/bin/bash

# This script installs or uninstalls the NZXT fan control script and sets up/removes a systemd service.

# Exit on error, undefined variables, or pipe failures
set -euo pipefail

# Configuration

readonly SCRIPT_SOURCE_DIR="$(dirname "$0")"

# Script to be installed
readonly SOURCE_SCRIPT_NAME="nzxt-fan-control.sh"
readonly SOURCE_SCRIPT_PATH="${SCRIPT_SOURCE_DIR}/${SOURCE_SCRIPT_NAME}"
readonly DESTINATION_SCRIPT_PATH="/usr/local/bin/${SOURCE_SCRIPT_NAME}"

# Systemd service file path
readonly SERVICE_FILE_SOURCE_NAME="nzxt-fan-control.service"
readonly SERVICE_FILE_SOURCE_PATH="${SCRIPT_SOURCE_DIR}/${SERVICE_FILE_SOURCE_NAME}"
readonly SERVICE_FILE_DESTINATION_PATH="/etc/systemd/system/${SERVICE_FILE_SOURCE_NAME}"
readonly SERVICE_NAME="${SERVICE_FILE_SOURCE_NAME%.*}" # Extracts 'nzxt-fan-control' from 'nzxt-fan-control.service'

# Log informational messages to stdout
function info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') | INFO | $*"
}

# Log error messages to stderr
function error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') | ERROR | $*" >&2
}

# Check if the script is run as root
function check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        error "This script must be run as root."
        error "Please run with: sudo ./service.sh <command>"
        exit 1
    fi
}

# Validates that all necessary source files exist for installation.
function validate_source_files() {
    info "Validating source files for installation..."
    if [[ ! -f "$SOURCE_SCRIPT_PATH" ]]; then
        error "Source script not found at '${SOURCE_SCRIPT_PATH}'."
        error "Please ensure '${SOURCE_SCRIPT_NAME}' is in the same directory as this installer."
        exit 1
    fi

    if [[ ! -f "$SERVICE_FILE_SOURCE_PATH" ]]; then
        error "Service file not found at '${SERVICE_FILE_SOURCE_PATH}'."
        error "Please ensure '${SERVICE_FILE_SOURCE_NAME}' is in the same directory as this installer."
        exit 1
    fi
    info "All source files found."
}

# Copies the main script to its destination and sets executable permissions.
function install_main_script() {
    info "Copying '${SOURCE_SCRIPT_PATH}' to '${DESTINATION_SCRIPT_PATH}'..."
    cp "$SOURCE_SCRIPT_PATH" "$DESTINATION_SCRIPT_PATH"

    info "Setting execute permissions for '${DESTINATION_SCRIPT_PATH}'..."
    chmod +x "$DESTINATION_SCRIPT_PATH"

    info "Main script installed successfully."
}

# Copies the systemd service file to its destination.
function install_service_file() {
    info "Copying systemd service file from '${SERVICE_FILE_SOURCE_PATH}' to '${SERVICE_FILE_DESTINATION_PATH}'..."
    cp "$SERVICE_FILE_SOURCE_PATH" "$SERVICE_FILE_DESTINATION_PATH"
    
    info "Systemd service file copied successfully."
}

# Reloads systemd daemon, enables, and starts the service.
function configure_and_start_service() {
    info "Reloading systemd daemon to recognize new service..."
    systemctl daemon-reload

    info "Enabling '${SERVICE_NAME}' to start on boot..."
    systemctl enable "${SERVICE_NAME}"

    info "Starting '${SERVICE_NAME}'..."
    systemctl start "${SERVICE_NAME}"

    info "Service enabled and started."
}

# --- Uninstall functions ---

# Stops, disables, and removes the systemd service and script.
function uninstall_service() {
    info "Starting uninstallation process for NZXT fan control service..."

    # Stop the service if it's running
    if systemctl is-active --quiet "${SERVICE_NAME}"; then
        info "Stopping '${SERVICE_NAME}'..."
        systemctl stop "${SERVICE_NAME}" || error "Failed to stop service, continuing uninstallation."
    else
        info "'${SERVICE_NAME}' is not running."
    fi

    # Disable the service
    if systemctl is-enabled --quiet "${SERVICE_NAME}"; then
        info "Disabling '${SERVICE_NAME}'..."
        systemctl disable "${SERVICE_NAME}" || error "Failed to disable service, continuing uninstallation."
    else
        info "'${SERVICE_NAME}' is not enabled."
    fi

    # Reload daemon after disabling to ensure changes are picked up
    info "Reloading systemd daemon..."
    systemctl daemon-reload

    # Remove the service file
    if [[ -f "$SERVICE_FILE_DESTINATION_PATH" ]]; then
        info "Removing service file from '${SERVICE_FILE_DESTINATION_PATH}'..."
        rm -f "$SERVICE_FILE_DESTINATION_PATH"
        info "Service file removed."
    else
        info "Service file not found at '${SERVICE_FILE_DESTINATION_PATH}', nothing to remove."
    fi

    # Remove the main script
    if [[ -f "$DESTINATION_SCRIPT_PATH" ]]; then
        info "Removing main script from '${DESTINATION_SCRIPT_PATH}'..."
        rm -f "$DESTINATION_SCRIPT_PATH"
        info "Main script removed."
    else
        info "Main script not found at '${DESTINATION_SCRIPT_PATH}', nothing to remove."
    fi

    info "Uninstallation complete!"
}

# Restarts the systemd service.
function restart_service() {
    info "Restarting '${SERVICE_NAME}'..."
    if systemctl is-active --quiet "${SERVICE_NAME}"; then
        systemctl restart "${SERVICE_NAME}"
        info "'${SERVICE_NAME}' restarted successfully."
    else
        error "'${SERVICE_NAME}' is not active. Cannot restart. Please check its status or try to start it."
        exit 1
    fi
}

# Displays help message for the script.
function display_help() {
    echo "Usage: sudo $(basename "$0") [command]"
    echo ""
    echo "This script installs, uninstalls, or restarts the NZXT Smart Device Fan Control service."
    echo ""
    echo "Commands:"
    echo "  install    Installs the fan control script and sets up the systemd service."
    echo "  uninstall  Stops, disables, and removes the service and the script."
    echo "  restart    Restarts the NZXT fan control systemd service."
    echo ""
    echo "Example:"
    echo "  sudo ./$(basename "$0") install"
    echo "  sudo ./$(basename "$0") uninstall"
    echo "  sudo ./$(basename "$0") restart"
}

function main() {
    check_root

    local command="${1:-}" # Get the first argument, or empty string if none

    case "$command" in
        "install")
            info "Starting NZXT fan control service installation..."
            validate_source_files
            install_main_script
            install_service_file
            configure_and_start_service
            info "Installation complete!"
            info "You can check the service status with: sudo systemctl status ${SERVICE_NAME}"
            info "And view its logs with: sudo journalctl -u ${SERVICE_NAME} -f"
            ;;
        "uninstall")
            uninstall_service
            ;;
        "restart")
            restart_service
            ;;
        *)
            display_help
            exit 1 # Exit with error code for invalid command
            ;;
    esac
}

main "$@"