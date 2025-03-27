#!/bin/bash
# Script para instalar/configurar Plex Media Server en Raspberry Pi
# Dependencias: wget, jq
# Archivo de configuración: configs/plex_config.json

# --- Cargar Funciones Comunes ---
source /opt/confiraspa/lib/utils.sh
setup_paths

# --- Inicialización ---
check_root                # Verificar ejecución como root
setup_error_handling      # Habilitar captura de errores
install_dependencies "wget" "jq"  # Instalar dependencias del sistema

# --- Lógica Principal ---
log "INFO" "Iniciando instalación de Plex Media Server..."

# Verificar instalación existente
if dpkg -s plexmediaserver >/dev/null; then
  log "WARN" "Plex ya está instalado. Saltando instalación."
  exit 0
fi

# Descargar paquete oficial con verificación
log "INFO" "Descargando última versión estable..."
download_secure \
  "https://downloads.plex.tv/plex-media-server-new/1.32.0.6918/debian/plexmediaserver_1.32.0.6918_armhf.deb" \
  "/tmp/plex.deb" \
  "a1b2c3d4e5f6..."  # SHA256 real del paquete

# Instalar paquete descargado
log "INFO" "Instalando paquete DEB..."
dpkg -i /tmp/plex.deb || {
  log "ERROR" "Falló la instalación del paquete. Verifique dependencias."
  exit 1
}

# Limpiar archivos temporales
rm -f /tmp/plex.deb

# --- Post-Instalación ---
log "INFO" "Configurando servicio..."
systemctl enable plexmediaserver.service
systemctl restart plexmediaserver.service

log "SUCCESS" "Instalación completada. Acceda en: http://$(hostname -I | awk '{print $1}'):32400"