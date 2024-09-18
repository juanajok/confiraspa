#!/bin/bash

# Script Name: install_amule.sh
# Description: Este script instala y configura aMule y sus servicios en un sistema Linux. Configura directorios, ajusta los archivos de configuración de aMule según los parámetros definidos en archivos JSON y configura servicios systemd para el demonio y la interfaz gráfica de aMule.
# Author: [Tu Nombre]
# Version: 1.0.0
# Date: [Fecha de Creación]
# License: MIT License
# Usage: Ejecutar este script con privilegios de superusuario (sudo). Asegúrate de tener los archivos `credenciales.json` y `amule_directories.json` en el mismo directorio que el script.
# Requirements: jq, systemctl
# Notes:
#   - El script detiene aMule, aplica configuraciones personalizadas desde archivos JSON y reinicia el servicio.
#   - Crea copias de seguridad de los archivos de configuración antes de realizar cambios.
#   - Configura y habilita servicios systemd para automatizar el inicio de aMule.
# Dependencies:
#   - jq: Utilizado para leer y procesar archivos JSON.
#   - systemctl: Utilizado para gestionar servicios systemd.
# Important: Este script debe ser ejecutado con privilegios de superusuario (sudo).

set -e

# Verificar si se ejecuta como root
if [[ $EUID -ne 0 ]]; then
    echo "Este script debe ser ejecutado con privilegios de superusuario (sudo)."
    exit 1
fi

# Variables necesarias
usuario="${SUDO_USER:-$(whoami)}"
user_home=$(getent passwd "$usuario" | cut -d: -f6)
script_path="$(dirname "$(realpath "$0")")"
credenciales_json="$script_path/configs/credenciales.json"
directories_json="$script_path/configs/amule_directories.json"

# Función de registro para imprimir mensajes con marca de tiempo
log() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message"
}

# Verifica que el archivo de credenciales existe
if [ ! -f "$credenciales_json" ]; then
    log "Error: El archivo de credenciales $credenciales_json no se encuentra."
    exit 1
fi

# Lee la contraseña desde el archivo JSON
contrasena=$(jq -r '.password' "$credenciales_json")

# Verifica que el archivo de directorios existe
if [ ! -f "$directories_json" ]; then
    log "Error: El archivo de directorios $directories_json no se encuentra."
    exit 1
fi

# Actualiza la lista de paquetes e instala aMule y sus utilidades
log "Instalando aMule y sus dependencias..."
apt-get update
apt-get install -y amule amule-utils amule-daemon amule-utils-gui
log "aMule y sus dependencias instaladas correctamente."

# Crear directorios de aMule si no existen
incoming_directory=$(jq -r '.incoming_directory' "$directories_json")
temp_directory=$(jq -r '.temp_directory' "$directories_json")

mkdir -p "$incoming_directory" "$temp_directory"
chown -R "$usuario":"$usuario" "$incoming_directory" "$temp_directory"
chmod -R 755 "$incoming_directory" "$temp_directory"
log "Directorios de aMule creados y permisos establecidos."

# Ejecuta aMule por primera vez para generar archivos de configuración
log "Ejecutando aMule por primera vez para generar archivos de configuración..."
sudo -u "$usuario" amuled &
amuled_pid=$!
sleep 20
kill "$amuled_pid"
log "El demonio de aMule ha sido detenido."

# Verifica que el archivo de configuración existe
amule_conf_path="$user_home/.aMule/amule.conf"
if [ ! -f "$amule_conf_path" ]; then
    log "Error: El archivo de configuración $amule_conf_path no se encuentra."
    exit 1
fi

# Crea una copia de seguridad del archivo de configuración de aMule
cp "$amule_conf_path" "$amule_conf_path.backup"
log "Copia de seguridad de amule.conf creada."

# Generar el hash MD5 de la contraseña
password_hash=$(echo -n "$contrasena" | md5sum | awk '{ print $1 }')

# Función para actualizar o agregar una clave en una sección INI
update_ini() {
    local file="$1"
    local section="$2"
    local key="$3"
    local value="$4"

    # Escapar caracteres especiales
    section_escaped=$(printf '%s\n' "$section" | sed 's/[][\/.^$*]/\\&/g')
    key_escaped=$(printf '%s\n' "$key" | sed 's/[][\/.^$*]/\\&/g')

    if grep -q "^\[$section_escaped\]" "$file"; then
        if grep -A1000 "^\[$section_escaped\]" "$file" | grep -m1 -q "^$key_escaped="; then
            # Actualizar clave existente
            sed -i "/^\[$section_escaped\]/,/^\[/{s|^$key_escaped=.*|$key=$value|}" "$file"
        else
            # Agregar clave al final de la sección
            sed -i "/^\[$section_escaped\]/a $key=$value" "$file"
        fi
    else
        # Agregar sección y clave al final del archivo
        echo -e "\n[$section]\n$key=$value" >> "$file"
    fi
}

# Actualiza el archivo de configuración de aMule con las nuevas rutas y configuraciones
update_ini "$amule_conf_path" "eMule" "IncomingDir" "$incoming_directory"
update_ini "$amule_conf_path" "eMule" "TempDir" "$temp_directory"
update_ini "$amule_conf_path" "eMule" "Template" "webserver"
update_ini "$amule_conf_path" "eMule" "Password" "$password_hash"
update_ini "$amule_conf_path" "eMule" "UserNick" "$usuario"
update_ini "$amule_conf_path" "eMule" "AcceptExternalConnections" "1"

# Configurar el WebServer
update_ini "$amule_conf_path" "WebServer" "Enabled" "1"
update_ini "$amule_conf_path" "WebServer" "Port" "4711"
update_ini "$amule_conf_path" "WebServer" "Password" "$password_hash"

# Configurar ExternalConnect
update_ini "$amule_conf_path" "ExternalConnect" "ECPassword" "$password_hash"

log "Se han actualizado las rutas de directorios y la configuración en amule.conf."

# Crea el archivo de servicio para aMule
log "Creando el archivo de servicio para aMule..."
cat > /etc/systemd/system/amule.service << EOF
[Unit]
Description=aMule Daemon
After=network.target

[Service]
User=$usuario
Type=forking
ExecStart=/usr/bin/amuled -f
ExecStop=/bin/kill -SIGINT \$MAINPID
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# Crea el archivo de servicio para la interfaz gráfica de aMule (opcional)
log "Creando el archivo de servicio para aMule GUI..."
cat > /etc/systemd/system/amule-gui.service << EOF
[Unit]
Description=aMule GUI
After=amule.service

[Service]
User=$usuario
Type=simple
Environment=DISPLAY=:0
ExecStart=/usr/bin/amule
Restart=on-failure

[Install]
WantedBy=graphical.target
EOF

# Recarga los servicios de systemd y habilita los nuevos servicios
log "Recargando systemd y habilitando servicios de aMule..."
systemctl daemon-reload
systemctl enable amule.service
systemctl enable amule-gui.service

# Iniciar los servicios
log "Iniciando servicios de aMule..."
systemctl restart amule.service
if ! systemctl is-active --quiet amule.service; then
    log "Error: El servicio de aMule no pudo iniciarse."
    exit 1
fi

systemctl restart amule-gui.service
if ! systemctl is-active --quiet amule-gui.service; then
    log "Error: El servicio de aMule GUI no pudo iniciarse."
    exit 1
fi

log "Servicios de aMule y aMule GUI configurados y reiniciados correctamente."
