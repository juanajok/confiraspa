#!/bin/bash

# Función de registro para imprimir mensajes con marca de tiempo
log() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${FUNCNAME[1]}] $message"
}

# Imprime un mensaje indicando que se está instalando Rclone
log "Instalando Rclone..."

# Descarga e instala Rclone
curl https://rclone.org/install.sh | bash

# Verifica si la instalación fue exitosa
if command -v rclone > /dev/null; then
    log "Rclone instalado correctamente."
else
    log "Error: No se pudo instalar Rclone."
    exit 1
fi

# Si tienes configuraciones específicas para Rclone, puedes añadirlas aquí
log "Configuración de Rclone completada."
