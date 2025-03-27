#!/bin/bash
# Biblioteca de utilidades comunes para scripts de Confiraspa
# Proporciona funciones estándar para logging, manejo de errores y dependencias

# --- Configuración Global ---
# --- Variables Configurables ---
export INSTALL_DIR="${INSTALL_DIR:-$(dirname "$(realpath "$0")")/..}"  # Ruta relativa al script
export CONFIG_DIR="${INSTALL_DIR}/configs" #directorio con las configuraciones
export LOG_DIR="${INSTALL_DIR}/logs" #directorio de logs

# Función para setear rutas portables
setup_paths() {
    [ ! -d "$LOG_DIR" ] && mkdir -p "$LOG_DIR" && chmod 755 "$LOG_DIR"
}                  # Asegurar que existe el directorio de logs

# --- Función: Logging Estandarizado ---
# Registra mensajes con formato [TIMESTAMP] [NIVEL] Mensaje
# Uso: log <nivel> "<mensaje>"
log() {
  local level="${1:-INFO}"                 # Nivel de log (INFO por defecto)
  local message="$2"                       # Mensaje a registrar
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${level^^}] $message" | tee -a "$LOG_DIR/confiraspa.log"
}

# --- Función: Verificación de Root ---
# Termina el script si no se ejecuta como root
# Uso: check_root
check_root() {
  [[ $EUID -eq 0 ]] || { 
    log "ERROR" "Este script requiere privilegios de superusuario. Ejecute con: sudo $0"
    exit 1 
  }
}

# --- Función: Configurar Manejo de Errores ---
# Habilita modo estricto y captura errores no controlados
# Uso: setup_error_handling
setup_error_handling() {
  set -eo pipefail                          # Detener en errores y pipes fallidos
  trap 'log "ERROR" "Error crítico en línea $LINENO. Último comando: $BASH_COMMAND"' ERR
}

# --- Función: Instalar Dependencias ---
# Instala paquetes del sistema si no están presentes
# Uso: install_dependencies "paquete1" "paquete2"
install_dependencies() {
  local deps=("$@")                        # Lista de paquetes a instalar
  log "DEBUG" "Actualizando lista de paquetes..."
  apt-get update -qq                       # Actualizar repositorios silenciosamente
  
  for dep in "${deps[@]}"; do
    if ! dpkg -l "$dep" &>/dev/null; then   # Verificar si el paquete está instalado
      log "INFO" "Instalando dependencia requerida: $dep"
      apt-get install -y "$dep"            # Instalar de forma no interactiva
    fi
  done
}