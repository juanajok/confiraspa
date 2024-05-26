#!/bin/bash
### Description: *Arr .NET Debian install script
### Version: 3.0.6
### Last Updated: 2022-04-26
### Authors: Bakerboy448, DoctorArr, brightghost, aeramor, VP-EN, *Arr Community

set -euo pipefail

# Constants
SCRIPT_VERSION="3.0.6"
SCRIPT_DATE="2022-04-26"
INSTALL_BASE_DIR="/opt"
DATA_BASE_DIR="/var/lib"

# Logging function
log() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$0] [${FUNCNAME[1]}] $message"
}

# Show script version info
show_version_info() {
    log "Running *Arr Install Script - Version [$SCRIPT_VERSION] as of [$SCRIPT_DATE]"
}

# Verify if the script is running as root
verify_root() {
    if [ "$EUID" -ne 0 ]; then
        log "Please run as root."
        exit 1
    fi
}

# Get user and group
get_user_group() {
    app_uid=$(logname)
    app_guid=$(id -gn "$app_uid")
}

# Create user and group if they do not exist
create_user_group() {
    if [ "$app_guid" != "$app_uid" ]; then
        if ! getent group "$app_guid" >/dev/null; then
            groupadd "$app_guid"
            log "Created group [$app_guid]"
        fi
    fi
    if ! getent passwd "$app_uid" >/dev/null; then
        adduser --system --no-create-home --ingroup "$app_guid" "$app_uid"
        log "Created and added user [$app_uid] to group [$app_guid]"
    fi
    if ! getent group "$app_guid" | grep -qw "$app_uid"; then
        usermod -a -G "$app_guid" "$app_uid"
        log "Added user [$app_uid] to group [$app_guid]"
    fi
}

# Stop application if running
stop_application() {
    local app=$1
    if systemctl is-active --quiet "$app"; then
        systemctl stop "$app"
        systemctl disable "$app"
        log "Stopped and disabled existing $app"
    fi
}

# Configure directories
configure_directories() {
    local app_name=$1
    local user=$2
    local group=$3

    local install_dir="${INSTALL_BASE_DIR}/${app_name}"
    local data_dir="${DATA_BASE_DIR}/${app_name}"

    for dir in "$install_dir" "$data_dir"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            chown "$user:$group" "$dir"
            chmod 775 "$dir"
            log "Created and set permissions for $dir"
        else
            log "Directory $dir already exists"
        fi
    done
}

# Check if a package is installed
is_package_installed() {
    dpkg -s "$1" >/dev/null 2>&1
}

# Install required packages
install_required_packages() {
    local packages=$1
    for package in $packages; do
        if ! is_package_installed "$package"; then
            log "Installing package: $package"
            apt-get install -y "$package"
        else
            log "Package already installed: $package"
        fi
    done
}

# Download and install application
download_install_application() {
    local app=$1
    local branch=$2
    local bindir=$3
    local datadir=$4
    local user=$5
    local group=$6

    ARCH=$(dpkg --print-architecture)
    dlbase="https://${app}.servarr.com/v1/update/${branch}/updatefile?os=linux&runtime=netcore"

    case "$ARCH" in
        "amd64") DLURL="${dlbase}&arch=x64" ;;
        "armhf") DLURL="${dlbase}&arch=arm" ;;
        "arm64") DLURL="${dlbase}&arch=arm64" ;;
        *)
            log "Architecture not supported: $ARCH"
            exit 1
            ;;
    esac

    log "Downloading $app from $DLURL"
    wget --content-disposition "$DLURL"
    filename=$(ls ${app^}.*.tar.gz)
    tar -xvzf "$filename"
    log "Installation files downloaded and extracted"

    log "Removing existing installation in $bindir"
    rm -rf "$bindir"
    mv "${app^}" "$bindir"
    chown -R "$user:$group" "$bindir"
    chmod -R 755 "$bindir"
    find "$bindir" -type f -name "${app^}" -exec chmod +x {} \;
    log "$app installed to $bindir"

    rm "$filename"
}

# Configure systemd service
configure_systemd_service() {
    local app=$1
    local bindir=$2
    local datadir=$3

    log "Creating systemd service for $app"
    cat >"/etc/systemd/system/${app}.service" <<EOL
[Unit]
Description=${app^} Daemon
After=syslog.target network.target

[Service]
User=${app_uid}
Group=${app_guid}
Type=simple
ExecStart=${bindir}/${app^} -nobrowser -data=${datadir}
TimeoutStopSec=20
KillMode=process
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
EOL

    log "Enabling and starting $app service"
    systemctl enable "${app}.service"
    systemctl start "${app}"
}

# Start application
start_application() {
    local app=$1
    log "Starting $app"
    systemctl status "$app"
}

# Install specific application
install_application() {
    local app_name=$1
    local app_port=$2
    local app_prerequisites=$3
    local app_umask=$4
    local app_branch=$5
    local user=$6
    local group=$7

    log "Installing $app_name"
    stop_application "$app_name"
    configure_directories "$app_name" "$user" "$group"
    install_required_packages "$app_prerequisites"
    download_install_application "$app_name" "$app_branch" "${INSTALL_BASE_DIR}/${app_name^}" "${DATA_BASE_DIR}/${app_name}" "$user" "$group"
    configure_systemd_service "$app_name" "${INSTALL_BASE_DIR}/${app_name}" "${DATA_BASE_DIR}/${app_name}"
    start_application "$app_name"
}

# Main function
main() {
    show_version_info
    verify_root
    get_user_group
    create_user_group

    # Read JSON file and process each application
    jq -c '.[]' apps.json | while read -r app_data; do
        app_name=$(jq -r '.name' <<< "$app_data")
        app_port=$(jq -r '.port' <<< "$app_data")
        app_prerequisites=$(jq -r '.prerequisites' <<< "$app_data")
        app_umask=$(jq -r '.umask' <<< "$app_data")
        app_branch=$(jq -r '.branch' <<< "$app_data")

        install_application "$app_name" "$app_port" "$app_prerequisites" "$app_umask" "$app_branch" "$app_uid" "$app_guid"
    done

    log "Script completed"
}

main
