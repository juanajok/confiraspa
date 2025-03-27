#!/bin/bash
# Description: Script de instalación y configuración de Calibre en Raspberry Pi con Raspbian OS
# Version: 1.1.1
# Author: [Tu Nombre]
# Date: [Fecha Actual]

set -euo pipefail

# Variables
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
CONFIG_DIR="$SCRIPT_DIR/configs"
CONFIG_FILE="$CONFIG_DIR/calibre_config.json"
SERVICE_FILE="/etc/systemd/system/calibre-server.service"
LOG_DIR="/var/log/confiraspi_v5"
SCRIPT_LOG_FILE="$LOG_DIR/install_calibre.sh.log"
CALIBRE_USER="calibre"
CALIBRE_GROUP="calibre"
CALIBRE_PORT=8080

# Crear el directorio de logs si no existe
mkdir -p "$LOG_DIR"
chmod 755 "$LOG_DIR"

# Función de registro para imprimir mensajes con marca de tiempo y nivel de log
log() {
    local level="$1"
    local message="$2"
    printf "[%s] [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$message" | tee -a "$SCRIPT_LOG_FILE"
}

# Función para verificar si se ejecuta como root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log "ERROR" "Este script debe ejecutarse con privilegios de superusuario (sudo)."
        exit 1
    fi
}

# Función para instalar dependencias
install_dependencies() {
    log "INFO" "Instalando dependencias necesarias (jq, curl, libxcb-cursor0)..."
    apt-get update
    apt-get install -y jq curl libxcb-cursor0
}

# Función para verificar si 'jq' está instalado
check_jq_installed() {
    if ! command -v jq &> /dev/null; then
        log "ERROR" "jq no se pudo instalar correctamente."
        exit 1
    fi
}

# Función para leer la ruta de la biblioteca desde el archivo JSON
read_library_path() {
    if [ -f "$CONFIG_FILE" ]; then
        LIBRARY_PATH=$(jq -r '.library_path' "$CONFIG_FILE")
        if [ -z "$LIBRARY_PATH" ]; then
            log "ERROR" "La ruta de la biblioteca no está definida en $CONFIG_FILE."
            exit 1
        fi
    else
        log "ERROR" "No se encontró el archivo de configuración JSON en '$CONFIG_FILE'."
        exit 1
    fi
}

# Función para verificar si Calibre ya está instalado
is_calibre_installed() {
    command -v calibre &> /dev/null
}

# Función para instalar Calibre
install_calibre() {
    if is_calibre_installed; then
        log "INFO" "Calibre ya está instalado. Saltando instalación."
        return
    fi

    log "INFO" "Descargando e instalando Calibre..."
    # Descargar e instalar Calibre utilizando el instalador oficial
    wget -nv -O- https://download.calibre-ebook.com/linux-installer.sh | sh /dev/stdin

    if ! is_calibre_installed; then
        log "ERROR" "La instalación de Calibre ha fallado."
        exit 1
    fi
    log "INFO" "Calibre instalado correctamente."
}

# Función para crear usuario y grupo para Calibre
setup_user_group() {
    # Verificar y crear grupo si no existe
    if ! getent group "$CALIBRE_GROUP" > /dev/null 2>&1; then
        log "INFO" "Creando grupo '$CALIBRE_GROUP'..."
        groupadd "$CALIBRE_GROUP"
    else
        log "INFO" "El grupo '$CALIBRE_GROUP' ya existe."
    fi

    # Verificar y crear usuario si no existe
    if ! id -u "$CALIBRE_USER" > /dev/null 2>&1; then
        log "INFO" "Creando usuario '$CALIBRE_USER' y agregándolo al grupo '$CALIBRE_GROUP'..."
        useradd --system --no-create-home --gid "$CALIBRE_GROUP" "$CALIBRE_USER"
    else
        log "INFO" "El usuario '$CALIBRE_USER' ya existe."
    fi

    # Asegurar que el usuario está en el grupo
    if ! id -nG "$CALIBRE_USER" | grep -qw "$CALIBRE_GROUP"; then
        log "INFO" "Agregando usuario '$CALIBRE_USER' al grupo '$CALIBRE_GROUP'..."
        usermod -a -G "$CALIBRE_GROUP" "$CALIBRE_USER"
    else
        log "INFO" "El usuario '$CALIBRE_USER' ya está en el grupo '$CALIBRE_GROUP'."
    fi
}

# Función para crear el archivo de servicio de systemd
create_service_file() {
    log "INFO" "Creando el archivo de servicio de Calibre en '$SERVICE_FILE'..."
    
    cat << EOF > "$SERVICE_FILE"
[Unit]
Description=Calibre eBook Server
After=network.target

[Service]
Type=simple
User=$CALIBRE_USER
Group=$CALIBRE_GROUP
ExecStart=/usr/bin/calibre-server --port $CALIBRE_PORT --enable-local-write "$LIBRARY_PATH"
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    log "INFO" "Archivo de servicio creado correctamente."
}

# Función para configurar y arrancar el servicio
configure_service() {
    log "INFO" "Recargando configuraciones de systemd..."
    systemctl daemon-reload

    log "INFO" "Habilitando el servicio de Calibre para que inicie en el arranque..."
    systemctl enable calibre-server.service

    log "INFO" "Iniciando el servicio de Calibre..."
    systemctl start calibre-server.service

    log "INFO" "Verificando el estado del servicio de Calibre..."
    if systemctl is-active --quiet calibre-server.service; then
        host=$(hostname -I | awk '{print $1}')
        log "INFO" "El servicio de Calibre se está ejecutando correctamente."
        log "INFO" "Puedes acceder a la interfaz web en http://$host:$CALIBRE_PORT"
    else
        log "ERROR" "El servicio de Calibre no se está ejecutando correctamente."
        systemctl status calibre-server.service >> "$SCRIPT_LOG_FILE"
        exit 1
    fi
}

# Función principal
main() {
    log "INFO" "Iniciando instalación y configuración de Calibre..."

    check_root
    install_dependencies
    check_jq_installed
    read_library_path
    install_calibre
    setup_user_group
    create_service_file
    configure_service

    log "INFO" "Instalación y configuración de Calibre completadas exitosamente."
}

# Ejecutar la función principal
main
