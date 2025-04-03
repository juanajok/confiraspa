#!/bin/bash
# Script para instalar/configurar servidor Samba
# Configuración: configs/smb.conf
# Dependencias: samba, samba-common-bin
set -euo pipefail
# --- Cargar Funciones Comunes ---
source /opt/confiraspa/lib/utils.sh

# --- Validaciones Iniciales ---
check_root
setup_error_handling
setup_paths
install_dependencies "samba" "samba-common-bin"

# Verificar instalación de Samba de manera precisa
if ! dpkg-query -W -f='${Status}' samba 2>/dev/null | grep -q "install ok installed"; then
    log "ERROR" "Falló la instalación de Samba"
    exit 1
fi

# --- Variables ---
SAMBA_CONFIG="/etc/samba/smb.conf"
BACKUP_CONFIG="/etc/samba/smb.conf.orig"
CONFIG_SOURCE="${CONFIG_DIR}/smb.conf"

# --- Configuración Principal ---
log "INFO" "Aplicando configuración personalizada de Samba..."

# Crear backup timestamped
if [ ! -f "$BACKUP_CONFIG" ]; then
    cp "$SAMBA_CONFIG" "$BACKUP_CONFIG-$(date +%Y%m%d%H%M%S)"
    log "DEBUG" "Backup creado: $BACKUP_CONFIG"
fi

# Copiar nueva configuración
log "DEBUG" "Copiando $CONFIG_SOURCE a $SAMBA_CONFIG..."
cp "$CONFIG_SOURCE" "$SAMBA_CONFIG" || {
    log "ERROR" "Falló la copia de $CONFIG_SOURCE. Verifique permisos."
    exit 1
}

# Validar sintaxis
testparm -s "$SAMBA_CONFIG" >/dev/null || {
    log "ERROR" "Configuración inválida. Revise $CONFIG_SOURCE"
    exit 1
}

# Ajustar permisos
chmod 644 "$SAMBA_CONFIG"
chown root:root "$SAMBA_CONFIG"

# --- Reinicio de Servicios ---
log "INFO" "Reiniciando servicios..."

# Siempre usar smbd y nmbd (nombres estándar en sistemas modernos)
SERVICES=("smbd" "nmbd")

# Restart services with error handling
if ! systemctl restart "${SERVICES[@]}"; then
    log "ERROR" "Fallo al reiniciar servicios Samba"
    log "DEBUG" "Estado de ${SERVICES[0]}: $(systemctl status ${SERVICES[0]})"
    log "DEBUG" "Estado de ${SERVICES[1]}: $(systemctl status ${SERVICES[1]})"
    exit 1
fi

# Verificar estado
if systemctl is-active "${SERVICES[0]}" && systemctl is-active "${SERVICES[1]}"; then
    log "INFO" "Samba configurado correctamente."
else
    log "ERROR" "Fallo en el inicio de servicios. Ejecute: journalctl -u ${SERVICES[0]}"
    exit 1
fi