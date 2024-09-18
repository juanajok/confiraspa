#!/usr/bin/env bash

# Script Name: install_transmission.sh
# Description: Este script instala y configura Transmission en un sistema Linux. Verifica y gestiona las dependencias, ajusta la configuración según un archivo JSON y asegura que el servicio se ejecute correctamente.
# Author: [Tu Nombre]
# Version: 1.1.0
# Date: [Fecha de Modificación]
# License: MIT License
# Usage: Ejecutar este script con privilegios de superusuario (sudo). Asegúrate de tener un archivo `transmission.json` con la configuración deseada.
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

set -e

# Verificar si se ejecuta como root
if [[ $EUID -ne 0 ]]; then
    echo "Este script debe ser ejecutado con privilegios de superusuario (sudo)."
    exit 1
fi

# Función de registro para imprimir mensajes con marca de tiempo
log() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message"
}

# Función para verificar que los comandos requeridos están disponibles
check_dependencies() {
    required_commands=("jq" "systemctl" "dpkg")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log "El comando $cmd no está instalado. Instalándolo..."
            apt-get install -y "$cmd"
        fi
    done
    log "Todas las dependencias necesarias están disponibles."
}

# Obtener el usuario que ejecuta Transmission
get_transmission_user() {
    if id -u "debian-transmission" &>/dev/null; then
        TRANSMISSION_USER="debian-transmission"
    elif id -u "transmission" &>/dev/null; then
        TRANSMISSION_USER="transmission"
    else
        log "Error: No se pudo encontrar el usuario de Transmission."
        exit 1
    fi
}

# Función principal
main() {
    # Verificar dependencias
    check_dependencies

    # Obtener el usuario de Transmission
    get_transmission_user

    # Archivo de configuración de JSON
    script_path="$(dirname "$(realpath "$0")")"
    JSON_FILE="$script_path/configs/transmission.json"

    # Verificar si el archivo JSON existe
    if [ ! -f "$JSON_FILE" ]; then
        log "Error: El archivo $JSON_FILE no existe."
        exit 1
    fi

    # Leer configuración desde el archivo JSON
    log "Leyendo configuración desde $JSON_FILE..."
    download_dir=$(jq -r '.["download-dir"]' "$JSON_FILE")
    incomplete_dir=$(jq -r '.["incomplete-dir"]' "$JSON_FILE")

    # Verificar que las rutas de los directorios no sean nulas
    if [ -z "$download_dir" ] || [ -z "$incomplete_dir" ]; then
        log "Error: Las rutas de los directorios de descarga no están definidas correctamente en $JSON_FILE."
        exit 1
    fi

    # Actualizar la lista de paquetes
    log "Actualizando la lista de paquetes..."
    apt-get update

    # Verificar si Transmission ya está instalado
    log "Verificando si Transmission está instalado..."
    if dpkg -l | grep -qw transmission-daemon; then
        log "Transmission ya está instalado."
    else
        log "Instalando Transmission..."
        apt-get install -y transmission-daemon
        log "Transmission instalado correctamente."
    fi

    # Detener el servicio de Transmission antes de hacer cambios en la configuración
    log "Deteniendo el servicio de Transmission..."
    if systemctl is-active --quiet transmission-daemon; then
        systemctl stop transmission-daemon
        log "Servicio de Transmission detenido."
    else
        log "El servicio de Transmission ya estaba detenido."
    fi

    # Configurar Transmission
    log "Configurando Transmission..."
    CONFIG_FILE="/etc/transmission-daemon/settings.json"
    BACKUP_FILE="/etc/transmission-daemon/settings.json.backup"

    # Crear una copia de seguridad del archivo de configuración si no existe
    if [ ! -f "$BACKUP_FILE" ]; then
        cp "$CONFIG_FILE" "$BACKUP_FILE"
        log "Copia de seguridad del archivo de configuración creada en $BACKUP_FILE."
    else
        log "La copia de seguridad del archivo de configuración ya existe."
    fi

    # Validar que el archivo de configuración original es un JSON válido
    if ! jq empty "$CONFIG_FILE" > /dev/null 2>&1; then
        log "Error: El archivo de configuración original no es un JSON válido."
        exit 1
    fi

    # Modificar únicamente las configuraciones específicas
    log "Actualizando configuraciones específicas en settings.json..."

    # Leer las claves a actualizar desde el archivo JSON proporcionado
    KEYS_TO_UPDATE=$(jq -r 'keys[]' "$JSON_FILE")

    # Realizar una copia del archivo de configuración actual para trabajar
    cp "$CONFIG_FILE" "${CONFIG_FILE}.tmp"

    # Actualizar cada clave en el archivo de configuración
    for key in $KEYS_TO_UPDATE; do
        value=$(jq ".\"$key\"" "$JSON_FILE")
        # Usar jq para actualizar el valor en el archivo de configuración
        jq ".\"$key\" = $value" "${CONFIG_FILE}.tmp" > "${CONFIG_FILE}.tmp2"
        mv "${CONFIG_FILE}.tmp2" "${CONFIG_FILE}.tmp"
    done

    # Validar el archivo JSON modificado
    if ! jq empty "${CONFIG_FILE}.tmp" > /dev/null 2>&1; then
        log "Error: El archivo de configuración modificado no es un JSON válido."
        cp "$BACKUP_FILE" "$CONFIG_FILE"
        exit 1
    fi

    # Reemplazar el archivo de configuración original con el modificado
    mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    log "Configuraciones actualizadas correctamente en $CONFIG_FILE."

    # Establecer permisos y propietario adecuados para los directorios de descarga
    log "Estableciendo permisos para los directorios de Transmission..."
    for dir in "$download_dir" "$incomplete_dir"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            log "Directorio $dir creado."
        else
            log "El directorio $dir ya existe."
        fi
        chown -R "$TRANSMISSION_USER":"$TRANSMISSION_USER" "$dir"
        chmod -R 770 "$dir"
    done
    log "Permisos y propietario establecidos correctamente."

    # Habilitar y arrancar el servicio de Transmission
    log "Habilitando y arrancando el servicio de Transmission..."
    systemctl enable transmission-daemon
    systemctl restart transmission-daemon

    log "Servicio de Transmission reiniciado correctamente."

    # Verificar el estado del servicio
    log "Verificando el estado del servicio de Transmission..."
    if systemctl is-active --quiet transmission-daemon; then
        log "Transmission está activo."
    else
        log "Transmission no está activo."
        exit 1
    fi

    log "Instalación y configuración de Transmission completada."
}

# Llama a la función principal
main
