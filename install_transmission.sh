#!/bin/bash

# Función de registro para imprimir mensajes con marca de tiempo
log() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message"
}

# Archivo de configuración de JSON
JSON_FILE="transmission.json"

# Verificar si el archivo JSON existe
if [ ! -f "$JSON_FILE" ]; then
    log "Error: El archivo $JSON_FILE no existe."
    exit 1
fi

# Leer configuración desde el archivo JSON
log "Leyendo configuración desde $JSON_FILE..."
download_dir=$(jq -r '.["download-dir"]' "$JSON_FILE")
incomplete_dir=$(jq -r '.["incomplete-dir"]' "$JSON_FILE")

# Verificar que las rutas de los directorios no sean nulas
if [ -z "$download_dir" ] || [ -z "$incomplete_dir" ]; then
    log "Error: Las rutas de los directorios de descarga no están definidas correctamente en $JSON_FILE."
    exit 1
fi

# Actualizar la lista de paquetes solo si no se ha actualizado en las últimas 24 horas
log "Actualizando la lista de paquetes..."
if [ ! -f /var/lib/apt/periodic/update-success-stamp ] || [ $(( $(date +%s) - $(stat -c %Y /var/lib/apt/periodic/update-success-stamp) )) -gt 86400 ]; then
    sudo apt-get update
    log "Lista de paquetes actualizada."
else
    log "La lista de paquetes ya está actualizada."
fi

# Verificar si Transmission ya está instalado
log "Verificando si Transmission está instalado..."
if dpkg -s transmission-daemon &> /dev/null; then
    log "Transmission ya está instalado."
else
    log "Instalando Transmission..."
    sudo apt-get install -y transmission-daemon
    log "Transmission instalado correctamente."
fi

# Detener el servicio de Transmission antes de hacer cambios en la configuración
log "Deteniendo el servicio de Transmission..."
if sudo systemctl is-active --quiet transmission-daemon; then
    sudo systemctl stop transmission-daemon
    log "Servicio de Transmission detenido."
else
    log "El servicio de Transmission ya estaba detenido."
fi

# Configurar Transmission
log "Configurando Transmission..."

CONFIG_FILE="/etc/transmission-daemon/settings.json"
BACKUP_FILE="/etc/transmission-daemon/settings.json.backup"

# Crear una copia de seguridad del archivo de configuración si no existe
if [ ! -f "$BACKUP_FILE" ]; then
    sudo cp "$CONFIG_FILE" "$BACKUP_FILE"
    log "Copia de seguridad del archivo de configuración creada en $BACKUP_FILE."
else
    log "La copia de seguridad del archivo de configuración ya existe."
fi

# Asegurarse de que el archivo de configuración contiene un objeto JSON válido
if [ ! -s "$CONFIG_FILE" ] || ! jq -e . "$CONFIG_FILE" > /dev/null 2>&1; then
    echo "{}" | sudo tee "$CONFIG_FILE" > /dev/null
fi

# Modificar el archivo de configuración de Transmission basado en el archivo JSON
log "Modificando el archivo de configuración de Transmission basado en $JSON_FILE..."
jq -s '.[0] * .[1]' "$CONFIG_FILE" "$JSON_FILE" | sudo tee "$CONFIG_FILE.tmp" > /dev/null

# Validar el archivo JSON modificado
if jq empty "$CONFIG_FILE.tmp" > /dev/null 2>&1; then
    sudo mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    log "Archivo de configuración modificado correctamente."
else
    log "Error: El archivo de configuración resultante no es un JSON válido."
    cat "$CONFIG_FILE.tmp"
    exit 1
fi

# Establecer permisos y propietario adecuados para los directorios de descarga
log "Estableciendo permisos para los directorios de Transmission..."
if [ ! -d "$download_dir" ]; then
    sudo mkdir -p "$download_dir"
    log "Directorio $download_dir creado."
else
    log "El directorio $download_dir ya existe."
fi

if [ ! -d "$incomplete_dir" ]; then
    sudo mkdir -p "$incomplete_dir"
    log "Directorio $incomplete_dir creado."
else
    log "El directorio $incomplete_dir ya existe."
fi

sudo chown -R debian-transmission:debian-transmission "$download_dir" "$incomplete_dir"
sudo chmod -R 770 "$download_dir" "$incomplete_dir"
log "Permisos y propietario establecidos correctamente."

# Habilitar y arrancar el servicio de Transmission solo si no está habilitado
log "Habilitando y arrancando el servicio de Transmission..."
if ! sudo systemctl is-enabled --quiet transmission-daemon; then
    sudo systemctl enable transmission-daemon
    log "Servicio de Transmission habilitado."
else
    log "El servicio de Transmission ya estaba habilitado."
fi

if ! sudo systemctl start transmission-daemon; then
    log "Error: No se pudo arrancar el servicio de Transmission."
    sudo journalctl -xeu transmission-daemon.service
    exit 1
fi

log "Servicio de Transmission arrancado."

# Verificar el estado del servicio
log "Verificando el estado del servicio de Transmission..."
sudo systemctl status transmission-daemon

log "Instalación y configuración de Transmission completada."
