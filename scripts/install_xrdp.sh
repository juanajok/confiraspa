#!/bin/bash
set -euo pipefail

# --- Cargar Funciones Comunes ---
source /opt/confiraspa/lib/utils.sh

check_root
setup_error_handling
setup_paths

log "INFO" "Instalando XRDP..."
if ! apt-get install -y xrdp; then
    log "ERROR" "Falló la instalación de XRDP."
    exit 1
fi

systemctl enable xrdp --now
log "SUCCESS" "XRDP instalado y habilitado."
