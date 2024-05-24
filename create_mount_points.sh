#!/bin/bash

# Función de registro para imprimir mensajes con marca de tiempo
log() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${FUNCNAME[1]}] $message"
}

# Imprime un mensaje indicando que se está iniciando la creación de puntos de montaje
log "Iniciando la creación de puntos de montaje..."

# Verifica si el archivo puntos_de_montaje.json existe
if [ ! -f puntos_de_montaje.json ]; then
    log "Error: No se encuentra el archivo puntos_de_montaje.json."
    exit 1
fi

# Lee los puntos de montaje del archivo JSON
directorios=$(cat puntos_de_montaje.json | jq -r '.puntos_de_montaje | .[]')

# Crea cada punto de montaje y aplica permisos
for dir in ${directorios}; do
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
        chmod -R 777 "$dir"
        log "Punto de montaje creado y permisos aplicados: $dir"
    else
        log "El punto de montaje $dir ya existe."
    fi
done

log "Finalizando la creación de puntos de montaje..."
