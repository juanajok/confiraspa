#!/bin/bash

# Función de registro para imprimir mensajes con marca de tiempo
log() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${FUNCNAME[1]}] $message"
}

# Imprime un mensaje indicando que se está instalando Samba
log "6) Instalando Samba..."

# Verifica si Samba ya está instalado
if dpkg -s samba &> /dev/null; then
    log "Samba ya está instalado en el sistema."
    exit 0
fi

# Instala Samba y sus componentes
apt install -y samba samba-common-bin

# Crea una copia de seguridad del archivo de configuración si no existe
if [ ! -f /etc/samba/smb.conf.old ]; then
    cp /etc/samba/smb.conf /etc/samba/smb.conf.old
    log "Copia de seguridad del fichero de configuración /etc/samba/smb.conf creada."
fi

# Copia el archivo de configuración personalizado
cp smb.conf /etc/samba/smb.conf
# Reinicia el servicio Samba
systemctl restart smbd
log "Samba se ha instalado y configurado correctamente."
