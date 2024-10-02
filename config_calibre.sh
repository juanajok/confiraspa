#!/bin/bash

# Script Name: config_calibre.sh
# Description: Configura que calibre arranque como servcio y que ejecute el servidor de correos
# Author: Juan José Hipólito
# Version: 1.1.0
# Date: 17/04/2023
# License: GNU
# Usage: Ejecuta el script manualmente
# Dependencies: jq

# Función de registro para imprimir mensajes con marca de tiempo
log() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1"
}


# Ruta al archivo de servicio
SERVICE_FILE="/etc/systemd/system/calibre-server.service"

# Directorio de configuración y archivo JSON
CONFIG_DIR="/configs"
CONFIG_FILE="${CONFIG_DIR}/calibre_config.json"
log "la ruta de la librería es $CONFIG_FILE" 

# Verifica si el script se ejecuta como superusuario
if [ "$(id -u)" -ne 0 ]; then
    log "Este script debe ejecutarse con privilegios de superusuario."
    exit 1
fi

# Instalar jq si no está instalado
if ! command -v jq &> /dev/null; then
    log "Instalando jq para procesamiento de JSON..."
    apt-get install -y jq
fi

# Leer la ruta de la biblioteca del archivo JSON
if [ -f "$CONFIG_FILE" ]; then
    LIBRARY_PATH=$(jq -r '.library_path' "$CONFIG_FILE")
else
    log "Error: No se encontró el archivo de configuración JSON en '$CONFIG_FILE'."
    exit 1
fi

# Creación del archivo de servicio utilizando las variables de entorno del usuario sudo
log "Creando el archivo de servicio de Calibre..."
cat << EOF > "$SERVICE_FILE"
[Unit]
Description=Calibre eBook Server
After=network.target

[Service]
Type=simple
User=$SUDO_USER
Group=$(getent group $SUDO_GID | cut -d: -f1)
ExecStart=/usr/bin/calibre-server --port 8080 --enable-local-write "$LIBRARY_PATH"
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Recargar los servicios de systemd para reconocer el nuevo servicio
log "Recargando configuraciones de systemd..."
systemctl daemon-reload

# Habilitar el servicio para que se inicie en el arranque
log "Habilitando el servicio de Calibre..."
systemctl enable calibre-server.service

# Iniciar el servicio de Calibre
log "Iniciando el servicio de Calibre..."
systemctl start calibre-server.service

# Mostrar el estado del servicio
log "Estado del servicio de Calibre:"
systemctl status calibre-server.service
