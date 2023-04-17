#!/bin/sh
#
# change_permissions.sh
# Este script cambia la propiedad y los permisos de los directorios especificados
# en un archivo de configuración JSON. El usuario y los directorios se leen desde
# el archivo de configuración y se aplican las operaciones de 'chown' y 'chmod'
# a cada directorio. El script muestra mensajes verbosos para informar sobre
# el proceso.
#
# Uso: ./change_permissions.sh
# Requiere: jq (https://stedolan.github.io/jq/)
#
# Autor: Juan José Hipólito
# Fecha: 17/04/2023
# Versión: 1.0
SCRIPT_DIR="$(dirname "$0")"
CONFIG_FILE="$SCRIPT_DIR/change_permissions_config.json"

# Leer la información del archivo JSON
usuario=$(jq -r '.usuario' $CONFIG_FILE)
directorios=$(jq -r '.directorios[]' $CONFIG_FILE)

echo "Usuario: $usuario"
echo "Directorios:"
echo "$directorios"

# Aplicar chown y chmod a cada directorio
for dir in $directorios; do
    echo "Cambiando la propiedad del directorio $dir al usuario $usuario"
    sudo chown -R $usuario "$dir"
    
    echo "Cambiando permisos del directorio $dir a 777"
    sudo chmod -R 777 "$dir"
done

echo "Permisos cambiados exitosamente."
