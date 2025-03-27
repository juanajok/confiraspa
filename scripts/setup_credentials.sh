#!/bin/bash
set -euo pipefail

# Script Name: setup_credentials.sh
# Description: Configura variables de usuario y contraseña para su uso en otros scripts, leyendo desde un archivo JSON.
# Author: Juan José Hipólito
# Version: 2.3.0
# Date: 2024-10-02
# License: GNU
# Usage: Ejecutar este script como superusuario (sudo).

# --- Cargar Funciones Comunes ---
source /opt/confiraspa/lib/utils.sh

# --- Inicialización ---
check_root                # Verificar ejecución como root
setup_error_handling      # Habilitar captura de errores
install_dependencies "wget" "jq"  # Instalar dependencias del sistema


# Función de registro para imprimir mensajes con marca de tiempo y nivel de log
log() {
    local level="$1"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" | tee -a "$LOG_FILE"
}

# Verificar si se ejecuta como root
if [[ $EUID -ne 0 ]]; then
    log "ERROR" "Por favor, ejecuta el script como superusuario (sudo)."
    exit 1
fi

# Definir variables de usuario y grupo
usuario="${SUDO_USER:-$(whoami)}"
app_guid=$(id -gn "$usuario")

log "INFO" "El usuario es: $usuario"
log "INFO" "El grupo es: $app_guid"

# Determinar el directorio del script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Definir el directorio de configuración relativo al directorio del script
CONFIG_DIR="$SCRIPT_DIR/configs"
CREDENTIALS_FILE="$CONFIG_DIR/credenciales.json"

# Verificar si el archivo credenciales.json existe
if [ ! -f "$CREDENTIALS_FILE" ]; then
    log "ERROR" "El archivo 'credenciales.json' no se encuentra en '$CONFIG_DIR'."
    exit 1
fi

# Leer las credenciales del archivo credenciales.json
if ! contrasena=$(jq -r '.password' "$CREDENTIALS_FILE"); then
    log "ERROR" "No se pudo leer la contraseña del archivo 'credenciales.json'."
    exit 1
fi

# Verificar que la contraseña no esté vacía
if [ -z "$contrasena" ] || [ "$contrasena" == "null" ]; then
    log "ERROR" "La contraseña en 'credenciales.json' está vacía o es nula."
    exit 1
fi

log "INFO" "Se usará el usuario '$usuario' para el resto de instalaciones."

# Exportar variables para que estén disponibles en otros scripts
export usuario
export app_guid
export contrasena

log "INFO" "Variables de usuario y contraseña configuradas correctamente."
