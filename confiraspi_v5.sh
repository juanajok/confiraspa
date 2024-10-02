#!/bin/bash
set -euo pipefail

# Script Name: confiraspi_v5.sh
# Description: Script para configurar una Raspberry Pi ejecutando varios scripts en orden de manera idempotente y desatendida.
# Author: Juan José Hipólito
# Version: 2.2.0
# Date: 2024-10-02
# License: GNU
# Usage: Ejecuta este script con sudo: sudo bash confiraspi_v5.sh [DIRECTORIO_DE_SCRIPTS]
# Dependencies: Verifica e instala automáticamente las dependencias necesarias.
# Notes: Este script configura una Raspberry Pi con varios servicios y programas de manera segura y automatizada.

# Variables
DEFAULT_SCRIPTS_DIR="/opt/confiraspa"
LOG_FILE="/var/log/confiraspi_v5.log"

# Función de registro para imprimir mensajes con marca de tiempo y nivel de log
log() {
    local level="$1"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" | tee -a "$LOG_FILE"
}

# Función para verificar que los comandos requeridos están disponibles e instalarlos si falta alguno
check_and_install_dependencies() {
    local required_commands=(
        "chmod" 
        "bash" 
        "jq"
        "apt-get"
        "sudo"
    )
    local missing_commands=()

    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_commands+=("$cmd")
        fi
    done

    if [ ${#missing_commands[@]} -ne 0 ]; then
        log "INFO" "Instalando dependencias faltantes: ${missing_commands[*]}"
        apt-get update -y

        for cmd in "${missing_commands[@]}"; do
            case "$cmd" in
                "jq")
                    apt-get install -y jq
                    ;;
                "chmod"|"bash"|"sudo"|"apt-get")
                    # Estas herramientas deberían estar presentes en casi todas las distribuciones de Linux.
                    log "ERROR" "El comando '$cmd' es esencial pero no está instalado. Por favor, instálalo manualmente."
                    exit 1
                    ;;
                *)
                    log "WARNING" "Comando desconocido '$cmd' necesita instalación."
                    ;;
            esac
        done
    else
        log "INFO" "Todas las dependencias necesarias están instaladas."
    fi
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
    if ! "$script_path" >> "$LOG_FILE" 2>&1; then
        log "ERROR" "La ejecución de '$script_path' ha fallado. Revisa el log para más detalles."
        exit 1
    fi
    log "INFO" "Script '$script_path' ejecutado correctamente."
}

# Función para mostrar el uso del script
usage() {
    echo "Uso: sudo bash $0 [DIRECTORIO_DE_SCRIPTS]"
    echo "Si no se especifica DIRECTORIO_DE_SCRIPTS, se usará '$DEFAULT_SCRIPTS_DIR'."
    exit 1
}

# Función principal que coordina la ejecución de los scripts
main() {
    # Redirigir todos los logs al archivo de log
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"

    # Verificar si se pasó un argumento para el directorio de scripts
    if [ $# -gt 1 ]; then
        usage
    fi

    # Directorio de los scripts (por defecto /opt/confiraspi)
    local SCRIPTS_DIR="$DEFAULT_SCRIPTS_DIR"
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

    # Verifica que todas las dependencias estén disponibles o las instala
    check_and_install_dependencies

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

