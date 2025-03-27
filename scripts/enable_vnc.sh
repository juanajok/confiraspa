#!/bin/bash

# Script Name: enable_vnc.sh
# Description: Este script habilita y configura el servicio VNC en una Raspberry Pi. Verifica si el servicio está habilitado y activo, realiza los ajustes necesarios en el archivo de configuración de arranque (/boot/config.txt) para establecer la resolución de pantalla y asegura que VNC se inicie automáticamente al encender.
# Author: [Tu Nombre]
# Version: 1.0.0
# Date: [Fecha de Creación]
# License: MIT License
# Usage: Ejecutar este script con privilegios de superusuario (sudo).
# Requirements: systemctl, sed
# Notes:
#   - El script verifica si se ejecuta como root antes de proceder.
#   - Crea una copia de seguridad del archivo /boot/config.txt antes de realizar cambios.
#   - Añade configuraciones específicas para la resolución de pantalla a 1280x720.
# Dependencies:
#   - systemctl: Para gestionar el servicio VNC.
#   - sed: Para modificar líneas específicas en el archivo de configuración.
# Important: Este script debe ser ejecutado con privilegios de superusuario (sudo).

# --- Cargar Funciones Comunes ---
source /opt/confiraspa/lib/utils.sh

check_root
setup_error_handling

log "11) Habilitando VNC..."

# Verificar si se ejecuta como root
if [[ $EUID -ne 0 ]]; then
    log "ERROR: Este script debe ejecutarse con privilegios de superusuario (sudo)."
    exit 1
fi

# Verificar si el servicio VNC está habilitado
if systemctl is-enabled --quiet vncserver-x11-serviced.service; then
    log "El servicio VNC ya está habilitado."
else
    systemctl enable vncserver-x11-serviced.service
    log "El servicio VNC ha sido habilitado para ejecutarse al inicio."
fi

# Verificar si el servicio VNC está activo
if systemctl is-active --quiet vncserver-x11-serviced.service; then
    log "El servicio VNC ya está iniciado."
else
    systemctl start vncserver-x11-serviced.service
    log "El servicio VNC ha sido iniciado correctamente."
fi

# Crear una copia de seguridad del archivo config.txt si no existe
CONFIG_FILE="/boot/config.txt"
BACKUP_FILE="/boot/config.txt.backup"

if [ ! -f "$BACKUP_FILE" ]; then
    cp "$CONFIG_FILE" "$BACKUP_FILE"
    log "Se ha creado una copia de seguridad del archivo $CONFIG_FILE."
fi

# Eliminar las líneas existentes de hdmi_group y hdmi_mode si existen
sed -i '/^\s*hdmi_group=/d; /^\s*hdmi_mode=/d' "$CONFIG_FILE"
log "Las líneas existentes de 'hdmi_group' y 'hdmi_mode' han sido eliminadas de $CONFIG_FILE."

# Añadir las líneas para establecer la resolución de pantalla a 1280x720
echo -e "\nhdmi_group=2\nhdmi_mode=85" >> "$CONFIG_FILE"
log "Se han añadido las líneas para establecer la resolución de pantalla a 1280x720 en $CONFIG_FILE."
