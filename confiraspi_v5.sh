#!/bin/bash
set -euo pipefail

# Script Name: confiraspi.sh
# Description: Script para configurar una Raspberry Pi ejecutando varios scripts en orden.
# Author: Juan José Hipólito
# Version: 2.1.0
# Date: 2023-03-30
# License: GNU
# Usage: Ejecuta este script desde cualquier ruta; se encargará de encontrar los scripts necesarios.
# Dependencies: Verifica que todos los comandos necesarios están instalados.
# Notes: Este script configura una Raspberry Pi con varios servicios y programas.

# Función de registro para imprimir mensajes con marca de tiempo y nivel de log
log() {
    local level="$1"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message"
}

# Función para verificar que los comandos requeridos están disponibles
check_dependencies() {
    local required_commands=(
        "chmod" "bash" "jq"
    )
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log "ERROR" "El comando '$cmd' no está instalado. Instálalo antes de continuar."
            exit 1
        fi
    done
    log "INFO" "Todas las dependencias necesarias están disponibles."
}

# Función para verificar la existencia y permisos de un script antes de ejecutarlo
check_script() {
    local script_path="$1"
    if [ ! -f "$script_path" ]; then
        log "ERROR" "El script '$script_path' no existe."
        exit 1
    fi
    if [ ! -x "$script_path" ]; then
        log "INFO" "Asignando permisos de ejecución a '$script_path'..."
        chmod +x "$script_path"
    fi
}

# Función para ejecutar un script y manejar errores
run_script() {
    local script_path="$1"
    check_script "$script_path"
    log "INFO" "Ejecutando '$script_path'..."
    if ! "$script_path"; then
        log "ERROR" "La ejecución de '$script_path' ha fallado."
        exit 1
    fi
}

# Función principal que coordina la ejecución de los scripts
main() {
    # Verificar si se pasó un argumento para el directorio de scripts
    if [ $# -gt 1 ]; then
        log "ERROR" "Uso: $0 [DIRECTORIO_DE_SCRIPTS]"
        exit 1
    fi

    # Directorio de los scripts (por defecto /opt/confiraspa)
    local SCRIPTS_DIR="/opt/confiraspa"
    if [ $# -eq 1 ]; then
        SCRIPTS_DIR="$1"
    fi

    # Verificar si se ejecuta como root
    if [[ $EUID -ne 0 ]]; then
        log "ERROR" "Este script debe ejecutarse con privilegios de superusuario (sudo)."
        exit 1
    fi

    # Verificar que el directorio de scripts existe
    if [ ! -d "$SCRIPTS_DIR" ]; then
        log "ERROR" "El directorio de scripts '$SCRIPTS_DIR' no existe."
        exit 1
    fi

    # Verifica que todas las dependencias estén disponibles
    check_dependencies

    # Lista de scripts a ejecutar en orden
    scripts=(
        "update_system.sh"
        "setup_credentials.sh"
        "create_mount_points.sh"
        "generate_fstab.sh"
        "install_samba.sh"
        "install_xrdp.sh"
        "install_transmission.sh"
        "install_mono.sh"
        "install_sonarr.sh"
        "install_webmin.sh"
        "enable_vnc.sh"
        "install_plex.sh"
        "install_bazarr.sh"
        "install_amule.sh"
        "configure_crontab.sh"
        "install_rclone.sh"
        "setup_logrotate_from_json.sh"
    )

    log "INFO" "Iniciando configuración de la Raspberry Pi..."

    # Iterar sobre la lista de scripts y ejecutarlos
    for script_name in "${scripts[@]}"; do
        script_path="$SCRIPTS_DIR/$script_name"
        run_script "$script_path"
    done

    log "INFO" "Configuración completa. Reinicia el sistema para aplicar todos los cambios: sudo reboot."
}

# Llama a la función principal con todos los argumentos pasados
main "$@"
