#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Script Name: install_bazarr.sh
# Description: Instalación robusta y automatizada de Bazarr en Raspberry Pi OS
# Author: Tu Nombre
# Version: 3.0.2
# License: MIT
# Usage: sudo ./install_bazarr.sh

# --- Cargar Funciones Comunes ---
if [[ ! -f "/opt/confiraspa/lib/utils.sh" ]]; then
    echo "ERROR: Script de utilidades '/opt/confiraspa/lib/utils.sh' no encontrado." >&2
    exit 1
fi
source /opt/confiraspa/lib/utils.sh

# --- Configuración Principal ---
readonly APP_NAME="bazarr"
readonly INSTALL_DIR="/opt/${APP_NAME}"
readonly SERVICE_NAME="${APP_NAME}.service"
readonly SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}"
readonly PYTHON_VENV="${INSTALL_DIR}/venv"
readonly MIN_PYTHON_VERSION="3.8"
readonly GITHUB_API_URL="https://api.github.com/repos/morpheus65535/bazarr/releases/latest"
readonly USER_CONFIG_FILE="${CONFIG_DIR}/arr_user.json"
readonly REQUIRED_PACKAGES=(
    libxml2-dev libxslt1-dev python3-dev python3-libxml2
    python3-lxml unrar-free ffmpeg libatlas-base-dev
    python3-venv unzip ca-certificates jq git
)

# Variables dinámicas cargadas desde JSON
BAZARR_USER=""
BAZARR_GROUP=""

# --- Funciones de Validación ---
validate_environment() {
    check_root
    setup_error_handling
    setup_paths
    check_network_connectivity

    log "INFO" "Validando arquitectura..."
    local arch
    arch=$(uname -m)
    [[ "$arch" =~ ^(armv[67]l|aarch64)$ ]] || {
        log "ERROR" "Arquitectura no soportada: $arch"
        exit 1
    }

    log "INFO" "Validando versión de Python..."
    # Obtener componentes numéricos de la versión
    local python_major python_minor
    python_major=$(python3 -c 'import sys; print(sys.version_info.major)')
    python_minor=$(python3 -c 'import sys; print(sys.version_info.minor)')

    # Comparación numérica correcta
    if (( python_major < 3 )) || (( python_major == 3 && python_minor < 8 )); then
        log "ERROR" "Se requiere Python >= 3.8 (Detectado: ${python_major}.${python_minor})"
        exit 1
    fi
    log "INFO" "Versión de Python validada: ${python_major}.${python_minor}"
}

load_user_config() {
    log "INFO" "Cargando configuración de usuario desde ${USER_CONFIG_FILE}..."
    
    [[ -f "$USER_CONFIG_FILE" ]] || {
        log "ERROR" "Archivo de configuración no encontrado: $USER_CONFIG_FILE"
        exit 1
    }

    BAZARR_USER=$(jq -r '.user' "$USER_CONFIG_FILE" || {
        log "ERROR" "Error al extraer usuario del JSON"
        exit 1
    })
    
    BAZARR_GROUP=$(jq -r '.group' "$USER_CONFIG_FILE" || {
        log "ERROR" "Error al extraer grupo del JSON"
        exit 1
    })

    [[ -n "$BAZARR_USER" && -n "$BAZARR_GROUP" ]] || {
        log "ERROR" "Configuración incompleta en el JSON"
        exit 1
    }

    log "INFO" "Configuración cargada - Usuario: $BAZARR_USER, Grupo: $BAZARR_GROUP"
}

validate_system_user() {
    log "INFO" "Validando usuario y grupo del sistema..."
    
    if ! getent group "$BAZARR_GROUP" >/dev/null; then
        log "ERROR" "El grupo '$BAZARR_GROUP' no existe"
        exit 1
    fi

    if ! id -u "$BAZARR_USER" >/dev/null 2>&1; then
        log "ERROR" "El usuario '$BAZARR_USER' no existe"
        exit 1
    fi

    if ! id -nG "$BAZARR_USER" | grep -qw "$BAZARR_GROUP"; then
        log "ERROR" "El usuario '$BAZARR_USER' no pertenece al grupo '$BAZARR_GROUP'"
        exit 1
    fi
}

check_existing_installation() {
    # Detener servicio si está activo (sin preguntar)
    if systemctl is-active --quiet "${SERVICE_NAME}"; then
        log "WARN" "Deteniendo servicio ${SERVICE_NAME}..."
        systemctl stop "${SERVICE_NAME}" || true
    fi

    # Eliminar instalación previa automáticamente
    if [[ -d "${INSTALL_DIR}" ]]; then
        log "WARN" "Eliminando instalación previa en ${INSTALL_DIR}..."
        systemctl disable "${SERVICE_NAME}" >/dev/null 2>&1 || true
        rm -rf "${INSTALL_DIR}" || {
            log "ERROR" "Error al eliminar instalación previa"
            exit 1
        }
        # Limpiar archivos residuales del servicio
        rm -f "${SERVICE_PATH}" || true
        systemctl daemon-reload >/dev/null 2>&1 || true
    fi
}

# --- Funciones de Instalación ---
download_bazarr() {
    local download_url release_tag
    log "INFO" "Obteniendo última versión de Bazarr..."
    
    local response
    response=$(curl -fsSL "$GITHUB_API_URL") || {
        log "ERROR" "Error al contactar GitHub API"
        exit 1
    }

    download_url=$(jq -r '.assets[] | select(.name | endswith(".zip")) | .browser_download_url' <<< "$response")
    release_tag=$(jq -r '.tag_name' <<< "$response")

    [[ -n "$download_url" ]] || {
        log "ERROR" "No se pudo obtener URL de descarga"
        exit 1
    }

    log "INFO" "Descargando versión $release_tag..."
    curl -fsSL --retry 3 -o "${INSTALL_DIR}/bazarr.zip" "$download_url" || {
        log "ERROR" "Error en la descarga"
        exit 1
    }

    log "INFO" "Descomprimiendo archivos..."
    unzip -qo "${INSTALL_DIR}/bazarr.zip" -d "$INSTALL_DIR"
    rm -f "${INSTALL_DIR}/bazarr.zip"
}

setup_python_environment() {
    log "INFO" "Configurando entorno virtual Python..."
    
    python3 -m venv --clear "$PYTHON_VENV" || {
        log "ERROR" "Error al crear entorno virtual"
        exit 1
    }

    "${PYTHON_VENV}/bin/python" -m pip install -Uq pip setuptools wheel || {
        log "ERROR" "Error al actualizar pip"
        exit 1
    }

    local req_file="${INSTALL_DIR}/requirements.txt"
    [[ -f "$req_file" ]] || {
        log "ERROR" "Archivo de requisitos no encontrado"
        exit 1
    }

    "${PYTHON_VENV}/bin/pip" install -Uqr "$req_file" || {
        log "ERROR" "Error al instalar dependencias"
        exit 1
    }

    # Manejo especial para ARMv6
    if grep -qi 'armv6' /proc/cpuinfo; then
        log "INFO" "Optimizando numpy para ARMv6..."
        "${PYTHON_VENV}/bin/pip" uninstall -yq numpy || true
        install_dependencies python3-numpy || {
            log "ERROR" "Error al instalar numpy del sistema"
            exit 1
        }
    fi
}

configure_systemd_service() {
    log "INFO" "Creando servicio systemd..."
    
    cat > "$SERVICE_PATH" << EOF
[Unit]
Description=Bazarr Subtitle Service
After=network.target

[Service]
User=$BAZARR_USER
Group=$BAZARR_GROUP
WorkingDirectory=$INSTALL_DIR
ExecStart=$PYTHON_VENV/bin/python -m bazarr
Restart=on-failure
RestartSec=5
UMask=0027

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload || {
        log "ERROR" "Error al recargar systemd"
        exit 1
    }
}

set_permissions() {
    log "INFO" "Aplicando permisos..."
    
    chown -R "$BAZARR_USER:$BAZARR_GROUP" "$INSTALL_DIR"
    find "$INSTALL_DIR" -type d -exec chmod 750 {} \;
    find "$INSTALL_DIR" -type f -exec chmod 640 {} \;
}

# --- Función Principal ---
main() {
    validate_environment
    check_existing_installation
    install_dependencies "${REQUIRED_PACKAGES[@]}"
    load_user_config
    validate_system_user

    mkdir -p "$INSTALL_DIR" || {
        log "ERROR" "Error al crear directorio de instalación"
        exit 1
    }

    download_bazarr
    setup_python_environment
    configure_systemd_service
    set_permissions

    log "INFO" "Iniciando servicio..."
    systemctl enable --now "$SERVICE_NAME" || {
        log "ERROR" "Error al iniciar el servicio"
        exit 1
    }

    log "SUCCESS" "Instalación completada"
    log "INFO" "Accede en: http://$(get_ip_address):6767"
}

main "$@"