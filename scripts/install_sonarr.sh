#!/bin/bash
### Description: Instalación automatizada de Sonarr en Debian
### Adaptado para leer usuario y grupo desde configs/arr_user.json
### Versión: 1.2.0
### Fecha: [Fecha Actual]

set -euo pipefail

# Función de registro para imprimir mensajes con marca de tiempo y nivel de log
log() {
    local level="$1"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message"
}

log "INFO" "Iniciando instalación automatizada de Sonarr"

# Verificar si se ejecuta como root
if [ "$EUID" -ne 0 ]; then
    log "ERROR" "Este script debe ejecutarse con privilegios de superusuario (sudo)."
    exit 1
fi

app="sonarr"
app_port="8989"
app_prereq="curl sqlite3 wget"
app_umask="0002"
branch="main"

# Constantes
installdir="/opt"
bindir="${installdir}/${app^}"
datadir="/var/lib/$app/"
app_bin=${app^}

# Verificar que el script no se está ejecutando desde el directorio de instalación
script_dir="$(dirname -- "$(readlink -f -- "$0")")"
if [ "$installdir" == "$script_dir" ] || [ "$bindir" == "$script_dir" ]; then
    log "ERROR" "No debes ejecutar este script desde el directorio de instalación. Por favor, ejecútalo desde otro directorio."
    exit 1
fi

# Leer usuario y grupo desde configs/arr_user.json
config_file="configs/arr_user.json"

# Verificar si el archivo JSON existe
if [ ! -f "$config_file" ]; then
    log "ERROR" "El archivo de configuración $config_file no se encuentra."
    exit 1
fi

# Verificar si 'jq' está instalado
if ! command -v jq >/dev/null 2>&1; then
    log "INFO" "Instalando 'jq' para procesar archivos JSON..."
    apt-get update
    apt-get install -y jq
fi

# Leer usuario y grupo desde el archivo JSON
app_uid=$(jq -r '.user' "$config_file")
app_guid=$(jq -r '.group' "$config_file")

# Validar que los valores no estén vacíos
if [ -z "$app_uid" ] || [ -z "$app_guid" ]; then
    log "ERROR" "El archivo $config_file no contiene el usuario o grupo."
    exit 1
fi

log "INFO" "Sonarr se instalará en [$bindir] y usará [$datadir] como directorio de datos"
log "INFO" "Sonarr se ejecutará como el usuario [$app_uid] y el grupo [$app_guid]"

# Crear usuario y grupo si es necesario
if ! getent group "$app_guid" >/dev/null; then
    log "INFO" "Creando grupo [$app_guid]"
    groupadd "$app_guid"
fi

if ! id -u "$app_uid" >/dev/null 2>&1; then
    log "INFO" "Creando usuario [$app_uid] y agregándolo al grupo [$app_guid]"
    adduser --system --no-create-home --ingroup "$app_guid" "$app_uid"
fi

if ! id -nG "$app_uid" | grep -qw "$app_guid"; then
    log "INFO" "Agregando usuario [$app_uid] al grupo [$app_guid]"
    usermod -a -G "$app_guid" "$app_uid"
fi

# Detener Sonarr si está en ejecución
if systemctl is-active --quiet "$app"; then
    log "INFO" "Deteniendo servicio existente de Sonarr"
    systemctl stop "$app"
    systemctl disable "$app"
fi

# Crear directorio de datos
log "INFO" "Creando directorio de datos en [$datadir]"
mkdir -p "$datadir"
chown -R "$app_uid":"$app_guid" "$datadir"
chmod 775 "$datadir"

# Instalar paquetes necesarios
log "INFO" "Instalando paquetes necesarios"
apt-get update
apt-get install -y $app_prereq

# Obtener la arquitectura del sistema
ARCH=$(dpkg --print-architecture)

# Construir la URL de descarga
dlbase="https://services.sonarr.tv/v1/download/$branch/latest?version=4&os=linux"
case "$ARCH" in
"amd64") DLURL="${dlbase}&arch=x64" ;;
"armhf") DLURL="${dlbase}&arch=arm" ;;
"arm64") DLURL="${dlbase}&arch=arm64" ;;
*)
    log "ERROR" "Arquitectura no soportada: $ARCH"
    exit 1
    ;;
esac

# Descarga e instalación de Sonarr
log "INFO" "Descargando Sonarr desde $DLURL"
temp_dir=$(mktemp -d)
wget --content-disposition "$DLURL" -P "$temp_dir"

log "INFO" "Extrayendo archivos"
tar -xzf "$temp_dir"/${app^}.*.tar.gz -C "$temp_dir"

# Realizar copia de seguridad si existe una instalación previa
if [ -d "$bindir" ]; then
    log "INFO" "Realizando copia de seguridad de la instalación existente"
    mv "$bindir" "${bindir}_backup_$(date +%Y%m%d%H%M%S)"
fi

# Instalar Sonarr
log "INFO" "Instalando Sonarr en [$bindir]"
mv "$temp_dir/${app^}" "$installdir"
chown -R "$app_uid":"$app_guid" "$bindir"
chmod 775 "$bindir"

# Limpiar archivos temporales
rm -rf "$temp_dir"

# Crear archivo de servicio systemd
service_file="/etc/systemd/system/$app.service"
log "INFO" "Creando archivo de servicio systemd en [$service_file]"

cat <<EOF > "$service_file"
[Unit]
Description=${app^} Daemon
After=network.target

[Service]
User=$app_uid
Group=$app_guid
UMask=$app_umask
Type=simple
ExecStart=$bindir/$app_bin -nobrowser -data=$datadir
TimeoutStopSec=20
KillMode=process
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# Recargar systemd y habilitar el servicio
log "INFO" "Habilitando e iniciando el servicio de Sonarr"
systemctl daemon-reload
systemctl enable --now "$app"

# Verificar el estado del servicio
sleep 10
if systemctl is-active --quiet "$app"; then
    host=$(hostname -I | awk '{print $1}')
    log "INFO" "Sonarr instalado y ejecutándose correctamente"
    log "INFO" "Accede a la interfaz web en http://$host:$app_port"
else
    log "ERROR" "Sonarr no se está ejecutando correctamente"
    systemctl status "$app"
    exit 1
fi

exit 0


