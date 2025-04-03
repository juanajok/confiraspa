#!/usr/bin/env bash

# Script Name: install_transmission.sh
# Description: Instala y configura Transmission de forma idempotente usando un archivo JSON de configuración.
# Author: [Tu Nombre]
# Version: 2.0.0
# License: MIT

set -euo pipefail
source /opt/confiraspa/lib/utils.sh

# --- Configuración Global ---
readonly TRANSMISSION_CONFIG="/etc/transmission-daemon/settings.json"
readonly TRANSMISSION_SERVICE="transmission-daemon"
readonly JSON_CONFIG="${CONFIG_DIR}/transmission.json"

# --- Funciones Principales ---

main() {
    initialize
    install_transmission
    configure_transmission
    manage_service
    log "SUCCESS" "Instalación y configuración completadas."
}

initialize() {
    check_root
    setup_error_handling
    setup_paths
    install_dependencies "jq"
    check_internet_connection
    validate_json_config
}

install_transmission() {
    if ! dpkg -l | grep -qw transmission-daemon; then
        log "INFO" "Instalando Transmission..."
        apt-get -o Acquire::ForceIPv4=true update
        apt-get -o Acquire::ForceIPv4=true install -y transmission-daemon || {
            log "ERROR" "Fallo en la instalación."
            exit 1
        }
    else
        log "INFO" "Transmission ya está instalado."
    fi
}

configure_transmission() {
    local user=$(get_transmission_user)
    stop_service
    backup_config
    apply_json_config
    setup_directories
    set_permissions "$user"
}

manage_service() {
    start_service
    verify_service
}

# --- Funciones de Soporte ---

check_internet_connection() {
    log "INFO" "Verificando conectividad a Internet..."
    if ! ping -c 2 8.8.8.8 &>/dev/null || ! ping -c 2 google.com &>/dev/null; then
        log "ERROR" "Sin conexión a Internet."
        exit 1
    fi
    log "INFO" "Conectividad verificada."
}


validate_json_config() {
    [ -f "$JSON_CONFIG" ] || { log "ERROR" "Archivo $JSON_CONFIG no encontrado."; exit 1; }
    jq -e '.["download-dir"] and .["incomplete-dir"]' "$JSON_CONFIG" >/dev/null || {
        log "ERROR" "Configuración JSON incompleta."
        exit 1
    }
}

get_transmission_user() {
    local user=$(systemctl show -p User "$TRANSMISSION_SERVICE" | cut -d= -f2)
    if id -u "$user" &>/dev/null; then
        echo "$user"
    else
        for fallback_user in "debian-transmission" "transmission"; do
            if id -u "$fallback_user" &>/dev/null; then  # <- ¡Faltaba &>/dev/null aquí!
                echo "$fallback_user"
                return
            fi
        done
        log "ERROR" "Usuario de Transmission no encontrado."
        exit 1
    fi  # <- Correcto: cierre con fi
}

stop_service() {
    if systemctl is-active --quiet "$TRANSMISSION_SERVICE"; then
        systemctl stop "$TRANSMISSION_SERVICE"
        log "INFO" "Servicio detenido."
    fi
}

backup_config() {
    local backup="${TRANSMISSION_CONFIG}.backup_$(date +%Y%m%d%H%M%S)"
    cp "$TRANSMISSION_CONFIG" "$backup" || {
        log "ERROR" "Fallo al crear backup."
        exit 1
    }
}

apply_json_config() {
    jq -s '.[0] * .[1]' "$TRANSMISSION_CONFIG" "$JSON_CONFIG" > "${TRANSMISSION_CONFIG}.tmp" && 
    mv "${TRANSMISSION_CONFIG}.tmp" "$TRANSMISSION_CONFIG" || {
        log "ERROR" "Error al aplicar configuración."
        exit 1
    }
}

setup_directories() {
    local dirs=(
        $(jq -r '.["download-dir"]' "$JSON_CONFIG")
        $(jq -r '.["incomplete-dir"]' "$JSON_CONFIG")
    )
    for dir in "${dirs[@]}"; do
        mkdir -p "$dir" || {
            log "ERROR" "No se pudo crear $dir."
            exit 1
        }
    done
}

set_permissions() {
    local user="$1"
    local dirs=(
        $(jq -r '.["download-dir"]' "$JSON_CONFIG")
        $(jq -r '.["incomplete-dir"]' "$JSON_CONFIG")
    )
    for dir in "${dirs[@]}"; do
        chown -R "$user:$user" "$dir"
        find "$dir" -type d -exec chmod 755 {} \;
        find "$dir" -type f -exec chmod 640 {} \;
    done
}

start_service() {
    systemctl enable "$TRANSMISSION_SERVICE" && 
    systemctl start "$TRANSMISSION_SERVICE" || {
        log "ERROR" "Fallo al iniciar el servicio."
        exit 1
    }
}

verify_service() {
    sleep 3
    systemctl is-active --quiet "$TRANSMISSION_SERVICE" || {
        log "ERROR" "El servicio no está activo."
        exit 1
    }
}

# --- Ejecución ---
main "$@"