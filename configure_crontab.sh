#!/bin/bash
set -e

# Verificar si se ejecuta como root
if [[ $EUID -ne 0 ]]; then
    echo "Este script debe ser ejecutado con privilegios de superusuario (sudo)."
    exit 1
fi

# Función de registro para imprimir mensajes con marca de tiempo
log() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1"
}

log "Configurando comandos de crontab..."

# Directorio del script
script_path=$(dirname "$(realpath "$0")")
config_path="$script_path/configs/scripts_and_crontab.json"

# Leer y procesar el JSON
json_data=$(cat "$config_path")

# Iterar sobre cada entrada en el JSON
echo "$json_data" | jq -c '.[]' | while read -r entry; do
    script=$(echo "$entry" | jq -r '.script')
    schedule=$(echo "$entry" | jq -r '.schedule')
    interpreter=$(echo "$entry" | jq -r '.interpreter')

    # Agregar la barra inclinada inicial a la ruta
    script_full_path="/opt/confiraspa/$script"

    # Aplicar permisos ejecutables
    log "Aplicando permisos ejecutables a $script_full_path..."
    chmod +x "$script_full_path"

    # Construir el comando completo
    if [ "$interpreter" != "null" ]; then
        command="$interpreter $script_full_path"
    else
        command="$script_full_path"
    fi

    # Crear un identificador único para evitar duplicados
    unique_id="# CRON_ID:$(echo "$script_full_path" | md5sum | cut -d ' ' -f1)"
    crontab_line="$schedule $command $unique_id"

    # Comprobar si el script ya está en el crontab de root
    if crontab -l | grep -q "$unique_id"; then
        log "El script $script ya está en el crontab de root."
    else
        # Agregar el script al crontab de root
        log "Agregando el script $script al crontab de root..."
        (crontab -l 2>/dev/null; echo "$crontab_line") | crontab -
    fi
done

log "Configuración de comandos de crontab completada."
