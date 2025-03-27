#!/usr/bin/env bash

# Script Name: install_transmission.sh
# Description: Este script instala y configura Transmission en un sistema Linux. Verifica y gestiona las dependencias, ajusta la configuración según un archivo JSON y asegura que el servicio se ejecute correctamente.
# Author: [Tu Nombre]
# Version: 1.2.1
# Date: [Fecha de Modificación]
# License: MIT License
# Usage: Ejecutar este script con privilegios de superusuario (sudo). Asegúrate de tener un archivo transmission.json con la configuración deseada.
# Requirements: jq, systemctl, dpkg
# Notes:
# - Verifica si el script se ejecuta como root antes de proceder.
# - Crea una copia de seguridad del archivo de configuración de Transmission antes de aplicar cambios.
# - El script detendrá el servicio de Transmission, aplicará la configuración, ajustará permisos y reiniciará el servicio.
# Dependencies:
# - jq: Para manipulación de archivos JSON.
# - systemctl: Para gestionar el servicio de Transmission.
# - dpkg: Para verificar si los paquetes están instalados.
# - transmission-daemon: Instalado y gestionado por el script si no está presente.
# Important: Este script debe ser ejecutado con privilegios de superusuario (sudo).

set -euo pipefail
# set -x  # Activa el modo de depuración (descomentar para depurar)

# Archivo de log (usamos el mismo que los otros scripts)
LOG_FILE="/var/log/confiraspi_v5.log"

# Función de registro para imprimir mensajes con marca de tiempo y nivel de log
log() {
    local level="$1"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" | tee -a "$LOG_FILE"
}

# Verificar si se ejecuta como root
if [[ $EUID -ne 0 ]]; then
    log "ERROR" "Este script debe ser ejecutado con privilegios de superusuario (sudo)."
    exit 1
fi

# Función para verificar que los comandos requeridos están disponibles
check_dependencies() {
    required_commands=("jq" "systemctl" "dpkg")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log "WARNING" "El comando $cmd no está instalado."
            log "INFO" "Instalando $cmd..."
            if ! apt-get -o Acquire::ForceIPv4=true install -y "$cmd"; then
                log "ERROR" "No se pudo instalar $cmd. Por favor, instálalo manualmente e intenta de nuevo."
                exit 1
            fi
        fi
    done
    log "INFO" "Todas las dependencias necesarias están disponibles."
}

# Función para verificar si Transmission está instalado
check_transmission_installed() {
    if dpkg -l | grep -qw transmission-daemon; then
        log "INFO" "Transmission ya está instalado."
    else
        log "INFO" "Instalando Transmission..."
        apt-get -o Acquire::ForceIPv4=true update
        if ! apt-get -o Acquire::ForceIPv4=true install -y transmission-daemon; then
            log "ERROR" "No se pudo instalar Transmission. Por favor, verifica tu conexión a Internet o los repositorios e intenta de nuevo."
            exit 1
        fi
        log "INFO" "Transmission instalado correctamente."
    fi
}

# Obtener el usuario que ejecuta Transmission
get_transmission_user() {
    if id -u "debian-transmission" &>/dev/null; then
        TRANSMISSION_USER="debian-transmission"
        log "INFO" "Usuario de Transmission identificado: debian-transmission"
    elif id -u "transmission" &>/dev/null; then
        TRANSMISSION_USER="transmission"
        log "INFO" "Usuario de Transmission identificado: transmission"
    else
        log "ERROR" "No se pudo encontrar el usuario de Transmission."
        exit 1
    fi
}

# Verificar conectividad a Internet
check_internet_connection() {
    log "INFO" "Verificando la conectividad a Internet..."
    if ping -c 2 8.8.8.8 &>/dev/null && ping -c 2 google.com &>/dev/null; then
        log "INFO" "Conectividad a Internet verificada."
    else
        log "ERROR" "No se pudo verificar la conectividad a Internet. Por favor, revisa tu conexión."
        exit 1
    fi
}

# Función principal
main() {
    # Verificar conectividad a Internet
    check_internet_connection

    # Verificar dependencias
    check_dependencies

    # Verificar e instalar Transmission si es necesario
    check_transmission_installed

    # Obtener el usuario de Transmission después de la instalación
    get_transmission_user

    # Archivo de configuración de JSON
    script_path="$(dirname "$(realpath "$0")")"
    JSON_FILE="$script_path/configs/transmission.json"

    # Verificar si el archivo JSON existe
    if [ ! -f "$JSON_FILE" ]; then
        log "ERROR" "El archivo $JSON_FILE no existe. Por favor, crea este archivo o verifica la ruta."
        exit 1
    fi

    # Leer configuración desde el archivo JSON
    log "INFO" "Leyendo configuración desde $JSON_FILE..."
    download_dir=$(jq -r '.["download-dir"]' "$JSON_FILE")
    incomplete_dir=$(jq -r '.["incomplete-dir"]' "$JSON_FILE")

    # Verificar que las rutas de los directorios no sean nulas
    if [ -z "$download_dir" ] || [ -z "$incomplete_dir" ]; then
        log "ERROR" "Las rutas de los directorios de descarga no están definidas correctamente en $JSON_FILE."
        exit 1
    fi

    # Verificar si el archivo de configuración de Transmission existe
    CONFIG_FILE="/etc/transmission-daemon/settings.json"
    if [ ! -f "$CONFIG_FILE" ]; then
        log "ERROR" "El archivo de configuración $CONFIG_FILE no existe."
        exit 1
    fi

    # Detener el servicio de Transmission antes de hacer cambios en la configuración
    log "INFO" "Deteniendo el servicio de Transmission..."
    if systemctl is-active --quiet transmission-daemon; then
        systemctl stop transmission-daemon
        log "INFO" "Servicio de Transmission detenido."
    else
        log "INFO" "El servicio de Transmission ya estaba detenido."
    fi

    # Configurar Transmission
    log "INFO" "Configurando Transmission..."
    BACKUP_FILE="/etc/transmission-daemon/settings.json.backup"

    # Crear una copia de seguridad del archivo de configuración si no existe
    if [ ! -f "$BACKUP_FILE" ]; then
        cp "$CONFIG_FILE" "$BACKUP_FILE"
        log "INFO" "Copia de seguridad del archivo de configuración creada en $BACKUP_FILE."
    else
        log "INFO" "La copia de seguridad del archivo de configuración ya existe."
    fi

    # Validar que el archivo de configuración original es un JSON válido
    if ! jq empty "$CONFIG_FILE" > /dev/null 2>&1; then
        log "ERROR" "El archivo de configuración original no es un JSON válido. Restaurando desde la copia de seguridad."
        cp "$BACKUP_FILE" "$CONFIG_FILE"
        exit 1
    fi

    # Modificar las configuraciones específicas en settings.json
    log "INFO" "Actualizando configuraciones específicas en settings.json..."

    # Mezclar las configuraciones existentes con las nuevas, dando prioridad al archivo JSON proporcionado
    if ! jq -s '.[0] * .[1]' "$CONFIG_FILE" "$JSON_FILE" > "${CONFIG_FILE}.tmp"; then
        log "ERROR" "Error al combinar las configuraciones con jq."
        exit 1
    fi

    # Validar el archivo JSON modificado
    if ! jq empty "${CONFIG_FILE}.tmp" > /dev/null 2>&1; then
        log "ERROR" "El archivo de configuración modificado no es un JSON válido. Restaurando desde la copia de seguridad."
        cp "$BACKUP_FILE" "$CONFIG_FILE"
        exit 1
    fi

    # Reemplazar el archivo de configuración original con el modificado
    mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    log "INFO" "Configuraciones actualizadas correctamente en $CONFIG_FILE."

    # Establecer permisos y propietario adecuados para los directorios de descarga
    log "INFO" "Estableciendo permisos para los directorios de Transmission..."
    for dir in "$download_dir" "$incomplete_dir"; do
        if [ ! -d "$dir" ]; then
            if mkdir -p "$dir"; then
                log "INFO" "Directorio $dir creado."
            else
                log "ERROR" "No se pudo crear el directorio $dir."
                exit 1
            fi
        else
            log "INFO" "El directorio $dir ya existe."
        fi
        if ! chown -R "$TRANSMISSION_USER":"$TRANSMISSION_USER" "$dir"; then
            log "ERROR" "No se pudo cambiar el propietario del directorio $dir."
            exit 1
        fi
        chmod -R 770 "$dir"
        log "INFO" "Permisos y propietario establecidos para $dir."
    done

    # Habilitar y arrancar el servicio de Transmission
    log "INFO" "Habilitando y arrancando el servicio de Transmission..."
    if ! systemctl enable transmission-daemon; then
        log "ERROR" "No se pudo habilitar el servicio de Transmission."
        exit 1
    fi
    if ! systemctl start transmission-daemon; then
        log "ERROR" "No se pudo iniciar el servicio de Transmission."
        exit 1
    fi
    log "INFO" "Servicio de Transmission iniciado correctamente."

    # Esperar unos segundos antes de verificar el estado del servicio
    sleep 3

    # Verificar el estado del servicio
    log "INFO" "Verificando el estado del servicio de Transmission..."
    if systemctl is-active --quiet transmission-daemon; then
        log "INFO" "Transmission está activo."
    else
        log "ERROR" "Transmission no está activo después del arranque. Revisa los logs del sistema."
        exit 1
    fi

    log "INFO" "Instalación y configuración de Transmission completada."
}

# Llama a la función principal
main
