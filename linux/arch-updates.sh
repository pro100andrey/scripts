#!/bin/bash

function get_updates() {
    # Export necessary environment variables for cron
    # This connects the script to your user's DBUS session
    export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
    export DISPLAY=:0
    # Check dependencies
    if ! command -v checkupdates >/dev/null 2>&1; then
        notify-send -u critical "Error" "Install 'pacman-contrib' for checkupdates"
        return 1
    fi

    # Check for available Arch Linux updates
    local updates_arch=()
    local updates_aur=()

    readarray -t updates_arch < <(checkupdates 2>/dev/null)

    # Check for AUR updates (yay or paru)
    if command -v yay >/dev/null 2>&1; then
        readarray -t updates_aur < <(yay -Qu --aur 2>/dev/null)
    elif command -v paru >/dev/null 2>&1; then
        readarray -t updates_aur < <(paru -Qu --aur 2>/dev/null)
    fi

    local count_arch=${#updates_arch[@]}
    local count_aur=${#updates_aur[@]}
    local total_count=$((count_arch + count_aur))

    if ((total_count > 0)); then
        # Format package list (show first 10 packages)
        local display_limit=10
        local package_list=""
        local shown_count=0

        # Helper function to format lines
        add_to_list() {
            local source="$1"
            shift
            local pkg_info="$1"
            local pkg_name=$(echo "$pkg_info" | awk '{print $1}')
            local old_ver=$(echo "$pkg_info" | awk '{print $2}')
            local new_ver=$(echo "$pkg_info" | awk '{print $4}')

            if [[ -n "$new_ver" ]]; then
                package_list+="• $pkg_name: $old_ver → $new_ver\n"
            else
                package_list+="• $pkg_name\n"
            fi
        }

        for pkg in "${updates_arch[@]}"; do
            if ((shown_count >= display_limit)); then break; fi
            add_to_list "Repo" "$pkg"
            ((shown_count++))
        done

        for pkg in "${updates_aur[@]}"; do
            if ((shown_count >= display_limit)); then break; fi
            add_to_list "AUR" "$pkg"
            ((shown_count++))
        done

        # Add "and X more" if there are more packages
        if ((total_count > display_limit)); then
            package_list+="... and $((total_count - display_limit)) more packages"
        fi

        # Determine urgency based on number of updates
        local urgency="normal"
        local icon

        if ((total_count >= 50)); then
            urgency="critical"
            icon="update-high"
        elif ((total_count >= 20)); then
            urgency="normal"
            icon="update-medium"
        else
            urgency="low"
            icon="update-low"
        fi

        # Send notification with improved formatting
        RESPONSE=$(notify-send \
            -u "$urgency" \
            -i "$icon" \
            --action="do_update=Update Now" \
            -a "System Updates" \
            -t 5000 \
            "System Updates Available" \
            "Found $total_count update(s) ($count_arch Repo, $count_aur AUR):\n$package_list")

        if [[ "$RESPONSE" == "do_update" ]]; then
            nohup konsole -e bash -c "sudo pacman -Syu && paru -Syu" >/dev/null 2>&1 &
        fi
    fi
}

function main() {
    get_updates
}

main
