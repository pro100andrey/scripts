#! /bin/bash

# This script installs the NZXT fan control script and sets up a systemd service.

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

# Log messages with timestamp
function info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') | INFO | $*"
}

# Log error messages
function error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') | ERROR | $*" >&2
}
# Check if the script is run as root
function check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        error "This script must be run as root."
        error "Please run with: sudo ./install-nzxt-fan-control.sh"
        exit 1
    fi
}

# Validates that all necessary source files exist.
function validate_source_files() {
    info "Validating source files..."
    if [[ ! -f "$SOURCE_SCRIPT_PATH" ]]; then
        error "ERROR: Source script not found at '${SOURCE_SCRIPT_PATH}'."
        error "Please ensure '${SOURCE_SCRIPT_NAME}' is in the same directory as this installer."
        exit 1
    fi

    if [[ ! -f "$SERVICE_FILE_SOURCE_PATH" ]]; then
        error "ERROR: Service file not found at '${SERVICE_FILE_SOURCE_PATH}'."
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

    info "Main script installed."
}

# Copies the systemd service file to its destination.
function install_service_file() {
    info "Copying systemd service file from '${SERVICE_FILE_SOURCE_PATH}' to '${SERVICE_FILE_DESTINATION_PATH}'..."
    cp "$SERVICE_FILE_SOURCE_PATH" "$SERVICE_FILE_DESTINATION_PATH"

    info "Systemd service file copied."
}

# Reloads systemd daemon, enables, and starts the service.
function configure_and_start_service() {
    info "Reloading systemd daemon..."
    systemctl daemon-reload

    info "Enabling ${SERVICE_FILE_SOURCE_NAME} to start on boot..."
    systemctl enable "${SERVICE_FILE_SOURCE_NAME}"

    info "Starting ${SERVICE_FILE_SOURCE_NAME}..."
    systemctl start "${SERVICE_FILE_SOURCE_NAME}"

    info "Service enabled and started."
}

function main() {
    check_root
    info "Starting NZXT fan control service installation..."

    validate_source_files
    install_main_script
    install_service_file
    configure_and_start_service

    log "Installation complete!"
    log "You can check the service status with: sudo systemctl status ${SERVICE_FILE_SOURCE_NAME}"
    log "And view its logs with: sudo journalctl -u ${SERVICE_FILE_SOURCE_NAME} -f"
}

main "$@"