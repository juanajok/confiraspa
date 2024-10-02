#!/bin/bash
set -euo pipefail

# Descripción: Actualiza la Raspberry Pi, instala paquetes necesarios y configura tareas en el crontab.
# Autor: Juan José Hipólito
# Fecha: 2024-10-02
# Versión: 1.4.0

# Variables
LOG_FILE="/var/log/confiraspi_update_system.log"

# Crear el archivo de log si no existe y asignar permisos
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"

# Función de registro para imprimir mensajes con marca de tiempo y nivel de log
log() {
    local level="$1"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" | tee -a "$LOG_FILE"
}

# Verificar si se ejecuta como root
if [[ $EUID -ne 0 ]]; then
    log "ERROR" "Este script debe ser ejecutado con privilegios de superusuario (sudo)."
    exit 1
fi

# Función para ejecutar comandos con reintentos y timeout sin usar 'eval'
run_with_retries() {
    local retries=3
    local wait=5
    local timeout_duration=300  # 5 minutos

    for ((i=1; i<=retries; i++)); do
        log "INFO" "Ejecutando comando: $* (Intento $i de $retries)"
        if timeout "$timeout_duration" "$@"; then
            log "INFO" "Comando '$*' ejecutado exitosamente."
            return 0
        else
            log "WARNING" "Comando '$*' falló en el intento $i/$retries. Reintentando en $wait segundos..."
            sleep "$wait"
        fi
    done
    log "ERROR" "El comando '$*' falló después de $retries intentos."
    return 1
}

# Función para verificar conectividad a Internet
check_network() {
    local host="8.8.8.8"
    local count=4

    log "INFO" "Verificando conectividad de red..."
    if ping -c "$count" "$host" &>/dev/null; then
        log "INFO" "Conectividad de red verificada."
    else
        log "ERROR" "No hay conectividad de red. Asegúrate de que la Raspberry Pi esté conectada a Internet."
        exit 1
    fi
}

# Actualizar e instalar paquetes
update_and_install() {
    log "INFO" "1) Actualizando la Raspberry Pi..."

    # Verificar conectividad de red
    check_network

    # Actualiza los paquetes y limpia el sistema, forzando IPv4
    run_with_retries apt-get update -o Acquire::ForceIPv4=true
    run_with_retries apt-get upgrade -y -o Acquire::ForceIPv4=true
    run_with_retries apt-get autoremove -y
    run_with_retries apt-get clean

    # Instalar lsb-release si no está instalado
    if ! dpkg -s lsb-release >/dev/null 2>&1; then
        log "INFO" "Instalando lsb-release..."
        run_with_retries apt-get install -y lsb-release -o Acquire::ForceIPv4=true
    else
        log "INFO" "lsb-release ya está instalado."
    fi

    # Instalar paquetes necesarios si no están instalados
    paquetes=()
    if ! dpkg -s jq >/dev/null 2>&1; then paquetes+=("jq"); fi
    if ! dpkg -s moreutils >/dev/null 2>&1; then paquetes+=("moreutils"); fi

    if [ ${#paquetes[@]} -gt 0 ]; then
        log "INFO" "Instalando paquetes: ${paquetes[*]}"
        run_with_retries apt-get install -y "${paquetes[@]}" -o Acquire::ForceIPv4=true
    else
        log "INFO" "Todos los paquetes necesarios ya están instalados."
    fi
}

# Configurar actualizaciones automáticas de seguridad
configure_unattended_upgrades() {
    log "INFO" "2) Configurando actualizaciones automáticas de seguridad..."

    # Instala unattended-upgrades si no está instalado
    if ! dpkg -s unattended-upgrades >/dev/null 2>&1; then
        log "INFO" "Instalando unattended-upgrades..."
        run_with_retries apt-get install -y unattended-upgrades -o Acquire::ForceIPv4=true
    else
        log "INFO" "unattended-upgrades ya está instalado."
    fi

    # Habilita unattended-upgrades
    log "INFO" "Reconfigurando unattended-upgrades..."
    export DEBIAN_FRONTEND=noninteractive
    if ! run_with_retries dpkg-reconfigure -f noninteractive unattended-upgrades; then
        log "ERROR" "Falló la configuración de unattended-upgrades."
        exit 1
    fi

    # Obtener la codename de la distribución
    if command -v lsb_release >/dev/null 2>&1; then
        distro_codename=$(lsb_release -cs)
    elif [ -f /etc/os-release ]; then
        distro_codename=$(grep VERSION_CODENAME /etc/os-release | cut -d'=' -f2 | tr -d '"')
    else
        log "ERROR" "No se pudo determinar el codename de la distribución."
        exit 1
    fi

    log "INFO" "Codename de la distribución: $distro_codename"

    # Hacer copias de seguridad de los archivos de configuración si no se han hecho ya
    for file in /etc/apt/apt.conf.d/50unattended-upgrades /etc/apt/apt.conf.d/20auto-upgrades; do
        if [ -f "$file" ] && [ ! -f "${file}.bak" ]; then
            cp "$file" "${file}.bak"
            log "INFO" "Copia de seguridad creada para $file."
        fi
    done

    # Configurar para que solo instale actualizaciones de seguridad
    log "INFO" "Escribiendo configuración en /etc/apt/apt.conf.d/50unattended-upgrades"
    cat > /etc/apt/apt.conf.d/50unattended-upgrades << EOF
Unattended-Upgrade::Origins-Pattern {
    "origin=Debian,codename=${distro_codename},label=Debian-Security";
    "origin=Raspbian,codename=${distro_codename},label=Raspbian-Security";
};
Unattended-Upgrade::Automatic-Reboot "false";
EOF

    # Habilitar actualizaciones automáticas diarias
    log "INFO" "Escribiendo configuración en /etc/apt/apt.conf.d/20auto-upgrades"
    cat > /etc/apt/apt.conf.d/20auto-upgrades << EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

    log "INFO" "Actualizaciones automáticas de seguridad configuradas."
}

# Configurar tareas en el crontab
configure_crontab() {
    log "INFO" "3) Configurando tareas en el crontab..."

    # Definir el comando de actualización semanal (solo actualización de paquetes)
    actualizacion_cmd="0 0 * * 1 /usr/bin/apt update && /usr/bin/apt upgrade -y && /usr/bin/apt autoremove -y && /usr/bin/apt clean >/dev/null 2>&1 # actualizacion semanal"

    # Obtener el contenido actual del crontab de root
    crontab_content=$(crontab -l -u root 2>/dev/null || true)

    # Añadir el comando al crontab si no está presente
    if echo "$crontab_content" | grep -q "# actualizacion semanal"; then
        log "INFO" "La tarea de actualización semanal ya está en el crontab de root."
    else
        log "INFO" "Agregando la tarea de actualización semanal al crontab de root..."
        (echo "$crontab_content"; echo "$actualizacion_cmd") | crontab -u root -
        if [ $? -eq 0 ]; then
            log "INFO" "Tarea de crontab agregada exitosamente."
        else
            log "ERROR" "Error al agregar la tarea al crontab."
            exit 1
        fi
    fi
}

# Ejecutar funciones
update_and_install
configure_unattended_upgrades
configure_crontab

log "INFO" "Script completado exitosamente."
