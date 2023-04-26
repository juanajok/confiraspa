#!/bin/bash

# Función para imprimir mensajes con información de la función que los llama y la fecha y hora
function log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') ${FUNCNAME[1]}: $1"
}

# Función para restaurar una aplicación
function restore_app() {
    local app_name=$1
    local backup_dir=$2
    local backup_ext=$3
    local restore_dir=$4

    # Verificar si la ruta de backup existe y contiene archivos
    if [ ! -d "$backup_dir" ] || [ ! "$(ls -A $backup_dir)" ]; then
        log "La ruta de backup para $app_name no existe o no contiene archivos."
        return 1
    fi

    # Obtener el archivo más reciente en la ruta de backup
    local backup_file=$(ls -t "$backup_dir"/*"$backup_ext" | head -1)

    # Verificar si el archivo de backup existe
    if [ ! -f "$backup_file" ]; then
        log "El archivo de backup para $app_name no existe."
        return 1
    fi

    log "Restaurando $app_name desde $backup_file"

    # Detener el servicio
    systemctl stop "$app_name".service

    # Hacer una copia de seguridad de los archivos originales
    local app_dir=$(jq -r --arg app_name "$app_name" '.[$app_name].app_dir' restore_apps.json)
    cp "$app_dir"/"$app_name".db "$app_dir"/"$app_name".db.bak
    cp "$app_dir"/config.xml "$app_dir"/config.xml.bak


    # Descomprimir el backup en el directorio temporal
    local tmp_dir="$restore_dir/$app_name"
    mkdir -p "$tmp_dir"
    unzip "$backup_file" -d "$tmp_dir"

    # Copiar los archivos del backup a la ubicación original
    cp "$tmp_dir"/"$app_name".db "$app_dir"/"$app_name".db
    cp "$tmp_dir"/config.xml "$app_dir"/config.xml

    # Asignar los permisos adecuados a los archivos
    local sudo_user=$(whoami)
    local sudo_user_group=$(id -gn $sudo_user)
    chown -R "$sudo_user":"$sudo_user_group" "$app_dir"/"$app_name"
    chmod 755 "$app_dir"/"$app_name".db
    chmod 644 "$app_dir"/config.xml

    # Iniciar el servicio
    systemctl start "$app_name".service

    log "$app_name restaurado exitosamente"
}

# Función principal
function main() {
    # Verificar si el archivo restore_apps.json existe
    if [ ! -f "restore_apps.json" ]; then
        log "El archivo restore_apps.json no existe."
        return 1
    fi

    # Configuración de las aplicaciones a restaurar
    apps=($(jq -r 'keys[]' restore_apps.json))

    for app_name in "${apps[@]}"
    do
        backup_dir=$(jq -r --arg app_name "$app_name" '.[$app_name].backup_dir' restore_apps.json)
        backup_ext=$(jq -r --arg app_name "$app_name" '.[$app_name].backup_ext' restore_apps.json)
        restore_dir=$(jq -r --arg app_name "$app_name" '.[$app_name].restore_dir' restore_apps.json)

        restore_app "$app_name" "$backup_dir" "$backup_ext" "$restore_dir"
    done
}


