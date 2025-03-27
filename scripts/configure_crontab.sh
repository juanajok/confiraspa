#!/bin/bash
# Configura tareas programadas basadas en archivo JSON
# Formato JSON: [{"script": "script.sh", "schedule": "0 * * * *"}]

source /opt/confiraspa/lib/utils.sh

check_root
setup_error_handling
install_dependencies "jq"  # Requerido para parsear JSON
setup_paths

# --- Procesar Configuración ---
log "INFO" "Cargando configuración de crontab..."
CONFIG_FILE="${CONFIG_DIR}/crontab_jobs.json" 

# Validar existencia de archivo
[ -f "$CONFIG_FILE" ] || {
  log "ERROR" "Archivo de configuración no encontrado: $CONFIG_FILE"
  exit 1
}

# --- Aplicar Configuración ---
log "INFO" "Agregando trabajos al crontab..."
while read -r job; do
  script_name=$(jq -r '.script' <<< "$job")
  schedule=$(jq -r '.schedule' <<< "$job")
  
  # Validar script existente
  if [ ! -x "/opt/confiraspa/$script_name" ]; then
    log "WARN" "Script no encontrado o no ejecutable: $script_name"
    continue
  fi

  # Agregar al crontab
  log "DEBUG" "Programando: $script_name con horario '$schedule'"
  (crontab -l 2>/dev/null; echo "$schedule /opt/confiraspa/$script_name") | crontab -
done < <(jq -c '.[]' "$CONFIG_FILE")

log "SUCCESS" "Configuración de crontab completada. Verifique con: crontab -l"