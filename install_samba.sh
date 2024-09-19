#!/bin/bash
set -euo pipefail

# Script Name: install_samba.sh
# Description: Instala y configura Samba en Raspberry OS utilizando un archivo smb.conf personalizado ubicado en /configs.
# Author: [Tu Nombre]
# Version: 2.1.0
# Date: [Fecha Actual]
# License: GNU

# Función de registro para imprimir mensajes con marca de tiempo y nivel de log
log() {
    local level="$1"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message"
}

log "INFO" "6) Instalando Samba..."

# Verifica si Samba ya está instalado
if dpkg -s samba &> /dev/null; then
    log "INFO" "Samba ya está instalado en el sistema."
else
    # Actualiza los repositorios
    apt-get update

    # Instala Samba y sus componentes
    apt-get install -y samba samba-common-bin

    log "INFO" "Samba ha sido instalado."
fi

# Crea una copia de seguridad del archivo de configuración si no existe
if [ ! -f /etc/samba/smb.conf.old ]; then
    cp /etc/samba/smb.conf /etc/samba/smb.conf.old
    log "INFO" "Copia de seguridad del fichero de configuración /etc/samba/smb.conf creada."
fi

# Verifica si el archivo de configuración personalizado existe en /configs
CONFIG_DIR="/configs"
CUSTOM_SMB_CONF="$CONFIG_DIR/smb.conf"

if [ -f "$CUSTOM_SMB_CONF" ]; then
    # Copia el archivo de configuración personalizado
    cp "$CUSTOM_SMB_CONF" /etc/samba/smb.conf
    log "INFO" "Archivo de configuración personalizado copiado desde '$CUSTOM_SMB_CONF' a '/etc/samba/smb.conf'."
else
    log "ERROR" "El archivo smb.conf personalizado no se encontró en '$CONFIG_DIR'."
    exit 1
fi

# Reinicia el servicio Samba
systemctl restart smbd
systemctl restart nmbd
log "INFO" "Samba se ha instalado y configurado correctamente."

