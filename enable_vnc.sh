#!/bin/bash

# Función de registro para imprimir mensajes con marca de tiempo
log() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${FUNCNAME[1]}] $message"
}

# Imprime un mensaje indicando que se está habilitando VNC
log "11) Habilitando VNC..."

# Verifica si el servicio VNC está habilitado
if systemctl is-enabled vncserver-x11-serviced.service &> /dev/null; then
    log "El servicio VNC ya está habilitado."
else
    systemctl enable vncserver-x11-serviced.service
    log "El servicio VNC ha sido habilitado para ejecutarse al inicio."
fi

# Verifica si el servicio VNC está activo
if systemctl is-active --quiet vncserver-x11-serviced.service; then
    log "El servicio VNC ya está iniciado."
else
    systemctl start vncserver-x11-serviced.service
    log "El servicio VNC ha sido iniciado correctamente."
fi

# Crea una copia de seguridad del archivo config.txt si no existe
if [ ! -f /boot/config.txt.backup ]; then
    cp /boot/config.txt /boot/config.txt.backup
    log "Se ha creado una copia de seguridad del archivo /boot/config.txt."
fi

# Elimina las líneas existentes de hdmi_group y hdmi_mode si existen
if grep -qP '^(?!#)\s*hdmi_group=' /boot/config.txt && grep -qP '^(?!#)\s*hdmi_mode=' /boot/config.txt; then
    sed -i '/^\s*hdmi_group=/d' /boot/config.txt
    sed -i '/^\s*hdmi_mode=/d' /boot/config.txt
    log "Las líneas que contenían hdmi_group y hdmi_mode han sido eliminadas del archivo /boot/config.txt."
fi

# Añade las líneas para establecer la resolución de pantalla a 1280x720
echo -e "\nhdmi_group=2\nhdmi_mode=85" | tee -a /boot/config.txt > /dev/null
log "Se han añadido las líneas para establecer la resolución de pantalla a 1280x720 al final del archivo /boot/config.txt."
