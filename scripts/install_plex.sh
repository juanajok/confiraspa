#!/bin/bash
################################################################################
# Script Name: install_plex.sh
# Description: Instala/actualiza Plex Media Server en Raspberry Pi OS (64-bit)
# Usage: sudo ./install_plex.sh
# Dependencies: wget, jq, curl, dpkg
# Options: None
# Exit Codes:
#   0 - Success
#   1 - Installation/configuration error
#   2 - Network error
#   3 - Architecture not supported
################################################################################
set -euo pipefail
# --- Constantes de configuración ---
source /opt/confiraspa/lib/utils.sh
  check_root
  setup_error_handling
  setup_paths
  install_dependencies "curl" "jq"

# =============================================
# CONFIGURACIÓN
# =============================================
readonly API_URL="https://plex.tv/api/downloads/5.json"
readonly TMP_DIR=$(mktemp -d)
readonly OS_TYPE=$(uname -s | tr '[:upper:]' '[:lower:]')
readonly ARCH=$(uname -m)

# =============================================
# MÓDULO: DETECCIÓN DEL SISTEMA
# =============================================
detect_system() {
  local normalized_arch=$(normalize_arch "$ARCH")
  local distro=$(detect_linux_distro)
  
  echo "$distro:$normalized_arch"
}

normalize_arch() {
  case "$1" in
    "x86_64") echo "x86_64" ;;
    "aarch64") echo "aarch64" ;;
    "armv7l") echo "armv7hf" ;;
    *) echo "unknown" ;;
  esac
}

detect_linux_distro() {
  if grep -qi "debian\|ubuntu" /etc/os-release; then
    echo "debian"
  elif grep -qi "centos\|rhel\|fedora" /etc/os-release; then
    echo "redhat"
  else
    echo "unknown"
  fi
}

# =============================================
# MÓDULO: INTERACCIÓN CON LA API
# =============================================
fetch_plex_data() {
  curl -sSL "$API_URL" || {
    log "ERROR" "Fallo al acceder a la API de Plex"
    exit 1
  }
}

get_download_url() {
  local plex_data="$1"
  local distro="$2"
  local arch="$3"
  
  echo "$plex_data" | jq -r --arg arch "$arch" --arg distro "$distro" \
    '.computer.Linux.releases[] | select(.build == "linux-\($arch)" and .distro == $distro).url'
}

get_latest_version() {
  local plex_data="$1"
  
  echo "$plex_data" | jq -r '.computer.Linux.version'
}

get_checksum() {
  local plex_data="$1"
  local download_url="$2"
  
  echo "$plex_data" | jq -r --arg url "$download_url" \
    '.computer.Linux.releases[] | select(.url == $url).checksum'
}

# =============================================
# MÓDULO: MANEJO DE PAQUETES
# =============================================
download_package() {
  local url="$1"
  local output_file="$2"
  
  log "INFO" "Descargando desde $url..."
  if ! wget -q --show-progress "$url" -O "$output_file"; then
    log "ERROR" "Fallo en la descarga"
    return 1
  fi
}

verify_checksum() {
  local file="$1"
  local expected_checksum="$2"
  
  local actual_checksum=$(sha1sum "$file" | awk '{print $1}')
  if [[ "$expected_checksum" != "$actual_checksum" ]]; then
    log "ERROR" "Checksum inválido: Esperado=$expected_checksum | Obtenido=$actual_checksum"
    return 1
  fi
}

install_package() {
  local package_file="$1"
  local distro="$2"
  
  case "$distro" in
    "debian") sudo dpkg -i "$package_file" ;;
    "redhat") sudo rpm -Uvh "$package_file" ;;
    *) log "ERROR" "Distribución no soportada: $distro"; return 1 ;;
  esac || {
    log "ERROR" "Error durante la instalación"
    return 1
  }
}

# =============================================
# FUNCIÓN PRINCIPAL
# =============================================
main() {
  # Obtener datos del sistema
  IFS=':' read -r distro arch <<< "$(detect_system)"
  [[ "$arch" == "unknown" || "$distro" == "unknown" ]] && {
    log "ERROR" "Arquitectura o distribución no soportada"
    exit 1
  }

  # Obtener información de Plex
  local plex_data=$(fetch_plex_data)
  local latest_version=$(get_latest_version "$plex_data")
  local download_url=$(get_download_url "$plex_data" "$distro" "$arch")
  
  [ -z "$download_url" ] && {
    log "ERROR" "No se encontró paquete para: Distro=$distro, Arch=$arch"
    exit 1
  }

  # Descargar y verificar
  local package_path="$TMP_DIR/plex.pkg"
  download_package "$download_url" "$package_path" || exit 1
  
  local expected_checksum=$(get_checksum "$plex_data" "$download_url")
  verify_checksum "$package_path" "$expected_checksum" || exit 1

  # Instalar
  install_package "$package_path" "$distro" || exit 1

  # Limpieza
  rm -rf "$TMP_DIR"
  log "SUCCESS" "Plex $latest_version instalado exitosamente"
}

# =============================================
# EJECUCIÓN
# =============================================
main