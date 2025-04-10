#!/bin/bash
set -euo pipefail

# Script Name: confiraspi_v5.sh
# Description: Script para configurar una Raspberry Pi ejecutando varios scripts en orden de manera idempotente y desatendida.
# Author: Juan José Hipólito
# Version: 2.3.1
# Date: 2024-10-29
# License: GNU
# Usage: Ejecuta este script con sudo: sudo bash confiraspi_v5.sh [DIRECTORIO_DE_SCRIPTS]
# Dependencies: Verifica e instala automáticamente las dependencias necesarias.
# Notes: Este script configura una Raspberry Pi con varios servicios y programas de manera segura y automatizada.

# --- Cargar Funciones Comunes ---
source /opt/confiraspa/lib/utils.sh

check_root
# --- Crear directorio de logs ANTES de setup_error_handling ---
LOG_DIR="/opt/confiraspa/logs"
MAIN_LOG_FILE="$LOG_DIR/confiraspa.log"
mkdir -p "$LOG_DIR"
chmod 755 "$LOG_DIR"
setup_error_handling
install_dependencies "jq" "bash" # depenencias

# Variables
DEFAULT_SCRIPTS_DIR="/opt/confiraspa/scripts"

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
    local script_name="$(basename "$script_path")"
    local script_log="$LOG_DIR/$script_name.log"

    check_script "$script_path"
    log "INFO" "Ejecutando '$script_name'..."

    # Ejecutar el script con variables de entorno ajustadas y redirigir entrada
    if ! env DEBIAN_FRONTEND=noninteractive TERM=dumb \
           bash "$script_path" >> "$script_log" 2>&1 </dev/null; then
        log "ERROR" "La ejecución de '$script_name' ha fallado. Revisa '$script_log' para más detalles."
        exit 1
    fi
    log "INFO" "Script '$script_name' ejecutado correctamente."
}

# Función para deshabilitar IPv6 temporalmente
disable_ipv6() {
    log "INFO" "Deshabilitando IPv6 temporalmente..."
    sysctl -w net.ipv6.conf.all.disable_ipv6=1 > /dev/null
    sysctl -w net.ipv6.conf.default.disable_ipv6=1 > /dev/null
    log "INFO" "IPv6 deshabilitado."
}

# Función para mostrar el uso del script
usage() {
    echo "Uso: sudo bash $0 [DIRECTORIO_DE_SCRIPTS]"
    echo "Si no se especifica DIRECTORIO_DE_SCRIPTS, se usará '$DEFAULT_SCRIPTS_DIR'."
    exit 1
}

# Función principal que coordina la ejecución de los scripts
main() {
    # Verificar si se pasó un argumento para el directorio de scripts
    if [ $# -gt 1 ]; then
        usage
    fi

    # Directorio de los scripts (por defecto /opt/confiraspa)
    local SCRIPTS_DIR="$DEFAULT_SCRIPTS_DIR"
    if [ $# -eq 1 ]; then
        SCRIPTS_DIR="$1"
    fi

    # Verificar si se ejecuta como root
    if [[ $EUID -ne 0 ]]; then
        log "ERROR" "Este script debe ejecutarse con privilegios de superusuario (sudo)."
        exit 1
    fi

    # Crear directorio de logs y archivo principal con permisos

    if [ ! -f "$MAIN_LOG_FILE" ]; then
        touch "$MAIN_LOG_FILE"
        chmod 644 "$MAIN_LOG_FILE"
    fi

    # Deshabilitar IPv6 antes de cualquier operación de red
    disable_ipv6

    # Verificar que el directorio de scripts existe
    if [ ! -d "$SCRIPTS_DIR" ]; then
        log "ERROR" "El directorio de scripts '$SCRIPTS_DIR' no existe."
        exit 1
    fi

    # Lista de scripts a ejecutar en orden
    scripts=(
        "update_system.sh"
        "setup_credentials.sh"
        "generate_fstab.sh"
        "install_samba.sh"
        "install_xrdp.sh"
        "install_transmission.sh"
        "install_mono.sh"
        "install_sonarr.sh"
        "install_arr.sh"
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
