#!/bin/bash
set -e

# Descripción: Actualiza la Raspberry Pi, instala paquetes necesarios y configura tareas en el crontab.
# Autor: [Tu Nombre]
# Fecha: [Fecha]
# Versión: 1.1.0

# Función de registro para imprimir mensajes con marca de tiempo y nivel de log
log() {
    local level="$1"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message"
}

# Verificar si se ejecuta como root
if [[ $EUID -ne 0 ]]; then
    log "ERROR" "Este script debe ser ejecutado con privilegios de superusuario (sudo)."
    exit 1
fi

# Actualizar e instalar paquetes
update_and_install() {
    log "INFO" "1) Actualizando la Raspberry Pi..."

    # Actualiza los paquetes y limpia el sistema
    apt update
    apt upgrade -y
    apt autoremove -y
    apt clean

    # Instala jq si no está instalado
    if ! dpkg -s jq >/dev/null 2>&1; then
        log "INFO" "Instalando jq..."
        apt install -y jq
    else
        log "INFO" "jq ya está instalado."
    fi

    # Instala moreutils si no está instalado
    if ! dpkg -s moreutils >/dev/null 2>&1; then
        log "INFO" "Instalando moreutils..."
        apt install -y moreutils
    else
        log "INFO" "moreutils ya está instalado."
    fi
}

# Configurar actualizaciones automáticas de seguridad
configure_unattended_upgrades() {
    log "INFO" "2) Configurando actualizaciones automáticas de seguridad..."

    # Instala unattended-upgrades si no está instalado
    if ! dpkg -s unattended-upgrades >/dev/null 2>&1; then
        log "INFO" "Instalando unattended-upgrades..."
        apt install -y unattended-upgrades
    else
        log "INFO" "unattended-upgrades ya está instalado."
    fi

    # Habilita unattended-upgrades
    dpkg-reconfigure -plow unattended-upgrades

    # Configurar para que solo instale actualizaciones de seguridad
    cat > /etc/apt/apt.conf.d/50unattended-upgrades << EOF
Unattended-Upgrade::Origins-Pattern {
    "origin=Debian,codename=${distro_codename},label=Debian-Security";
    "origin=Raspbian,codename=${distro_codename},label=Raspbian";
};
Unattended-Upgrade::Automatic-Reboot "false";
EOF

    # Habilitar actualizaciones automáticas diarias
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
    actualizacion_cmd="0 0 * * 1 /usr/bin/apt update && /usr/bin/apt upgrade -y && /usr/bin/apt autoremove -y && /usr/bin/apt clean # actualizacion semanal"

    # Obtener el contenido actual del crontab de root
    crontab_content=$(crontab -l -u root 2>/dev/null || true)

    # Añadir el comando al crontab si no está presente
    if echo "$crontab_content" | grep -q "# actualizacion semanal"; then
        log "INFO" "La tarea de actualización semanal ya está en el crontab de root."
    else
        log "INFO" "Agregando la tarea de actualización semanal al crontab de root..."
        (echo "$crontab_content"; echo "$actualizacion_cmd") | crontab -u root -
    fi
}

# Ejecutar funciones
update_and_install
configure_unattended_upgrades
configure_crontab

log "INFO" "Script completado exitosamente."
