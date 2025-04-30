#!/bin/bash
# Script de instalación modular e idempotente de Bazarr en Docker para Raspberry Pi OS
# Utiliza la biblioteca de utilidades Confiraspa (utils.sh)
# Versión: 2.0.0
# Uso: sudo ./install_bazarr_docker.sh

# --- Configuración Global y Constantes ---
# La biblioteca utils.sh definirá INSTALL_DIR, CONFIG_DIR, LOG_DIR
UTILS_PATH="/opt/confiraspa/lib/utils.sh" # Ruta a tu biblioteca

# --- Cargar biblioteca de utilidades ---
# Verificar si el archivo de utilidades existe antes de intentar cargarlo
if [[ ! -f "$UTILS_PATH" ]]; then
    echo "[$(date --iso-8601=seconds)] [CRITICAL] [$$] Biblioteca de utilidades no encontrada en: $UTILS_PATH" >&2
    exit 1
fi
# shellcheck source=/dev/null
source "$UTILS_PATH" || {
    echo "[$(date --iso-8601=seconds)] [CRITICAL] [$$] Error al cargar la biblioteca de utilidades: $UTILS_PATH" >&2
    exit 1
}

# --- Variables Específicas del Script ---
# Asegurarse de que CONFIG_DIR esté definido (lo hace setup_paths, pero verificamos temprano)
if [[ -z "$CONFIG_DIR" ]]; then
    # Intentar obtenerlo relativo a este script si utils.sh no se cargó completamente
    CURRENT_SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
    # Asumiendo que este script está en $INSTALL_DIR/scripts o similar
    INSTALL_DIR_GUESS="$(dirname "$CURRENT_SCRIPT_DIR")"
    CONFIG_DIR="${INSTALL_DIR_GUESS}/configs"
    echo "[$(date --iso-8601=seconds)] [WARN] [$$] CONFIG_DIR no fue definido por utils.sh, intentando adivinar: $CONFIG_DIR" >&2
    # Si aún está vacío, es un error fatal. setup_paths lo detectará más tarde.
fi

CONFIG_JSON="${CONFIG_DIR}/arr_user.json"
BAZARR_BASE_DIR="/opt/bazarr"                     # Directorio base para la configuración de Bazarr
BAZARR_APP_CONFIG_DIR="${BAZARR_BASE_DIR}/config" # Directorio de configuración persistente de Bazarr
DOCKER_COMPOSE_FILE="${BAZARR_BASE_DIR}/docker-compose.yml"
# Directorios de medios - ¡Asegúrate de que estos existen y son accesibles!
# Podrían ser montajes de red (NFS, SMB) o discos locales.
MEDIA_MOVIES_DIR="/mnt/media/pelis" # Ejemplo - ¡CAMBIA ESTO A TU RUTA REAL!
MEDIA_TV_DIR="/mnt/media/series"    # Ejemplo - ¡CAMBIA ESTO A TU RUTA REAL!
# Zona horaria para el contenedor
TIMEZONE="Europe/Madrid" # Ejemplo - ¡AJUSTA A TU ZONA HORARIA! https://en.wikipedia.org/wiki/List_of_tz_database_time_zones

# Variables globales para PUID/PGID (se llenarán en parse_user_config)
declare PUID
declare PGID
declare TARGET_USER

# --- Funciones Auxiliares ---

# Verifica si un comando existe
command_exists() {
    command -v "$1" &>/dev/null
}

# Parsea el archivo JSON de configuración para obtener usuario y grupo
parse_user_config() {
    log "INFO" "Parseando archivo de configuración de usuario: $CONFIG_JSON"
    if [[ ! -f "$CONFIG_JSON" ]]; then
        log "ERROR" "Archivo de configuración no encontrado: $CONFIG_JSON"
        log "ERROR" "Crea el archivo $CONFIG_JSON con el formato: {\"user\": \"tu_usuario\", \"group\": \"tu_grupo\"}"
        return 1
    fi

    # Usar jq para parsear de forma segura
    if ! command_exists jq; then
        log "ERROR" "El comando 'jq' es necesario para parsear JSON. Por favor, instálalo (sudo apt-get install jq)."
        return 1
    fi

    TARGET_USER=$(jq -r '.user // empty' "$CONFIG_JSON")
    local target_group
    target_group=$(jq -r '.group // empty' "$CONFIG_JSON")

    if [[ -z "$TARGET_USER" || -z "$target_group" ]]; then
        log "ERROR" "Usuario ('user') o grupo ('group') no definido o vacío en $CONFIG_JSON"
        return 1
    fi

    log "INFO" "Usuario objetivo: '$TARGET_USER', Grupo objetivo: '$target_group'"

    # Validar que el usuario existe
    if ! id -u "$TARGET_USER" &>/dev/null; then
        log "ERROR" "El usuario '$TARGET_USER' especificado en $CONFIG_JSON no existe en el sistema."
        return 1
    fi
    PUID=$(id -u "$TARGET_USER")

    # Validar que el grupo existe y obtener PGID
    if ! getent group "$target_group" &>/dev/null; then
        log "ERROR" "El grupo '$target_group' especificado en $CONFIG_JSON no existe en el sistema."
        return 1
    fi
    PGID=$(getent group "$target_group" | cut -d: -f3)

    if [[ -z "$PUID" || -z "$PGID" ]]; then
        # Esta comprobación es redundante si las anteriores pasaron, pero es defensiva
        log "ERROR" "No se pudo obtener el PUID o PGID para $TARGET_USER:$target_group."
        return 1
    fi

    log "INFO" "Configurando para usuario: $TARGET_USER (PUID: $PUID), Grupo: $target_group (PGID: $PGID)"
    return 0
}

# Añade el usuario al grupo docker si es necesario
add_user_to_docker_group() {
    if [[ -z "$TARGET_USER" ]]; then
        log "WARN" "No se pudo determinar el usuario objetivo. Saltando adición al grupo 'docker'."
        return 0 # No es un error fatal para la instalación en sí, pero el usuario necesitará sudo
    fi

    if getent group docker &>/dev/null; then
        if groups "$TARGET_USER" | grep -q '\bdocker\b'; then
            log "INFO" "El usuario '$TARGET_USER' ya pertenece al grupo 'docker'."
        else
            log "INFO" "Añadiendo usuario '$TARGET_USER' al grupo 'docker'..."
            if ! usermod -aG docker "$TARGET_USER"; then
                log "ERROR" "Fallo al añadir '$TARGET_USER' al grupo 'docker'."
                return 1
            else
                log "WARN" "Usuario '$TARGET_USER' añadido al grupo 'docker'. Es necesario cerrar sesión y volver a iniciarla para que el cambio tenga efecto."
                log "WARN" "Alternativamente, puedes ejecutar 'newgrp docker' en una nueva terminal para usar Docker sin sudo en esa sesión."
            fi
        fi
    else
        log "WARN" "El grupo 'docker' no existe. La instalación de Docker debería crearlo."
        # Se podría intentar crearlo aquí, pero es mejor dejar que el instalador de Docker lo haga.
    fi
    return 0
}


# --- Funciones de Instalación y Configuración ---

# Instala Docker Engine usando el script oficial get.docker.com
install_docker_engine() {
    log "INFO" "Verificando instalación de Docker Engine..."
    if command_exists docker; then
        local docker_version
        docker_version=$(docker --version)
        log "INFO" "Docker Engine ya está instalado ($docker_version)."
        return 0
    fi

    log "INFO" "Instalando Docker Engine..."
    check_network_connectivity || return 1 # Asegurar conexión antes de descargar

    local get_docker_script="get-docker.sh"
    if ! download_secure "https://get.docker.com" "$get_docker_script"; then
        log "ERROR" "Fallo al descargar el script de instalación de Docker."
        return 1
    fi

    log "INFO" "Ejecutando script de instalación de Docker (esto puede tardar)..."
    # Ejecutar con sh, no con sudo directamente dentro, ya que el script maneja la elevación si es necesario
    if ! sh "$get_docker_script"; then
        log "ERROR" "Fallo durante la ejecución del script de instalación de Docker."
        rm -f "$get_docker_script" # Limpiar
        return 1
    fi

    rm -f "$get_docker_script" # Limpiar script descargado
    log "SUCCESS" "Docker Engine instalado correctamente."

    # Verificar que el servicio Docker está activo (systemd)
    if command_exists systemctl; then
        if ! systemctl is-active --quiet docker; then
            log "INFO" "Intentando iniciar el servicio Docker..."
            if ! systemctl start docker; then
                log "ERROR" "No se pudo iniciar el servicio Docker después de la instalación."
                return 1
            fi
        fi
        if ! systemctl is-enabled --quiet docker; then
             log "INFO" "Habilitando el servicio Docker para que inicie en el arranque..."
             if ! systemctl enable docker; then
                 log "WARN" "No se pudo habilitar el servicio Docker en el arranque."
                 # No es un error fatal para la instalación actual
             fi
        fi
        log "INFO" "Servicio Docker activo y habilitado."
    fi
    return 0
}

# Instala Docker Compose (preferiblemente el plugin V2)
install_docker_compose() {
    log "INFO" "Verificando instalación de Docker Compose..."

    # Prioridad 1: Plugin V2 (docker compose)
    if docker compose version &>/dev/null; then
        local compose_plugin_version
        compose_plugin_version=$(docker compose version)
        log "INFO" "Docker Compose Plugin (V2) ya está instalado."
        log "DEBUG" "Versión: $compose_plugin_version"
        return 0
    fi

    # Prioridad 2: V1 (docker-compose) - como fallback o si se prefiere
    if command_exists docker-compose; then
        local compose_v1_version
        compose_v1_version=$(docker-compose --version)
        log "INFO" "Docker Compose V1 ya está instalado ($compose_v1_version)."
        log "INFO" "Se recomienda migrar al plugin V2 ('docker compose') si es posible."
        return 0
    fi

    log "INFO" "Docker Compose no encontrado. Intentando instalar el plugin V2 (recomendado)..."
    check_network_connectivity || return 1

    # Intentar instalar el plugin vía apt (método preferido en Debian/Raspberry Pi OS si está disponible)
    if install_dependencies "docker-compose-plugin"; then
        log "SUCCESS" "Docker Compose Plugin (V2) instalado correctamente vía apt."
        # Verificar que el comando funciona ahora
        if ! docker compose version &>/dev/null; then
             log "WARN" "Se instaló 'docker-compose-plugin' pero el comando 'docker compose' aún no funciona. Puede requerir re-login o ajuste de PATH."
        fi
        return 0
    else
        log "WARN" "No se pudo instalar 'docker-compose-plugin' vía apt. Intentando fallback con pip (V1)..."
        # Fallback a V1 usando pip (método original del ejemplo)
        local pip_deps=("python3-pip" "python3-venv" "libffi-dev" "python3-dev") # python3-venv es buena práctica
        log "INFO" "Instalando dependencias para Docker Compose V1 (pip)..."
        if ! install_dependencies "${pip_deps[@]}"; then
            log "ERROR" "Fallo al instalar dependencias para Docker Compose V1."
            return 1
        fi

        log "INFO" "Instalando Docker Compose V1 vía pip3..."
        # Usar --break-system-packages si es necesario en sistemas más nuevos, pero intentar sin él primero
        if ! python3 -m pip install --no-cache-dir docker-compose; then
            log "WARN" "Fallo al instalar docker-compose con pip. Intentando con --break-system-packages (Debian 12+)..."
            if ! python3 -m pip install --no-cache-dir --break-system-packages docker-compose; then
                log "ERROR" "Fallo al instalar Docker Compose V1 vía pip, incluso con --break-system-packages."
                return 1
            fi
        fi

        # Verificar que el comando V1 ahora existe
        if ! command_exists docker-compose; then
             log "ERROR" "Se instaló 'docker-compose' vía pip, pero el comando no se encuentra. Verifica tu PATH."
             return 1
        fi
        log "SUCCESS" "Docker Compose V1 instalado correctamente vía pip."
        log "WARN" "Se instaló la versión V1 de Docker Compose. Considera actualizar al plugin V2 en el futuro."
        return 0
    fi
}

# Configura los directorios necesarios para Bazarr
setup_bazarr_directories() {
    log "INFO" "Configurando directorios para Bazarr en: $BAZARR_BASE_DIR"

    # Verificar que PUID y PGID están definidos
    if [[ -z "$PUID" || -z "$PGID" ]]; then
        log "ERROR" "PUID o PGID no están definidos. ¿Se ejecutó parse_user_config correctamente?"
        return 1
    fi

    local dirs_to_create=("$BAZARR_BASE_DIR" "$BAZARR_APP_CONFIG_DIR")
    # No creamos los directorios de medios aquí, asumimos que ya existen y son gestionados externamente
    # Solo verificamos que existan para advertir al usuario si no.
    local media_dirs=("$MEDIA_MOVIES_DIR" "$MEDIA_TV_DIR")
    local dir
    local created_or_exists=true

    # Crear directorios de configuración de Bazarr
    for dir in "${dirs_to_create[@]}"; do
        if [[ ! -d "$dir" ]]; then
            log "INFO" "Creando directorio: $dir"
            if ! mkdir -p "$dir"; then
                log "ERROR" "No se pudo crear el directorio: $dir (Verifica permisos en el directorio padre)"
                created_or_exists=false
            else
                log "DEBUG" "Directorio creado: $dir"
                # Establecer propietario solo si se creó exitosamente
                if ! chown "${PUID}:${PGID}" "$dir"; then
                   log "ERROR" "Error al cambiar propietario de '$dir' a ${PUID}:${PGID}."
                   created_or_exists=false
                else
                   # Establecer permisos razonables (755 para directorios)
                   chmod 755 "$dir"
                   log "DEBUG" "Propietario y permisos establecidos para: $dir (${PUID}:${PGID}, 755)"
                fi
            fi
        else
            log "INFO" "Directorio ya existe: $dir. Verificando propietario..."
            # Si ya existe, solo ajustar propietario si es necesario/posible
            if [[ $(stat -c "%u:%g" "$dir") != "${PUID}:${PGID}" ]]; then
                 log "INFO" "Ajustando propietario de '$dir' a ${PUID}:${PGID}..."
                 if ! chown "${PUID}:${PGID}" "$dir"; then
                    log "WARN" "No se pudo cambiar el propietario del directorio existente '$dir'. Verifica permisos."
                    # No lo marcamos como error fatal si ya existía, pero advertimos.
                 else
                     log "DEBUG" "Propietario ajustado para: $dir"
                 fi
            else
                 log "DEBUG" "Propietario ya es correcto para: $dir (${PUID}:${PGID})"
            fi
        fi
    done

    # Verificar existencia de directorios de medios
    for dir in "${media_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            log "WARN" "El directorio de medios '$dir' no existe o no es accesible."
            log "WARN" "Asegúrate de que este directorio exista y que el usuario con PUID $PUID y PGID $PGID tenga permisos de lectura/escritura en él."
            # Podríamos considerarlo un error fatal dependiendo del caso de uso, pero por ahora solo advertimos.
            # created_or_exists=false
        else
            log "INFO" "Directorio de medios encontrado: $dir"
            # Opcionalmente, verificar/ajustar permisos aquí también si se desea
            # if ! chown -R "${PUID}:${PGID}" "$dir"; then ... fi
        fi
    done

    if [[ "$created_or_exists" = true ]]; then
        log "SUCCESS" "Directorios de Bazarr configurados correctamente."
        return 0
    else
        log "ERROR" "Hubo problemas al configurar uno o más directorios para Bazarr."
        return 1
    fi
}

# Genera el archivo docker-compose.yml para Bazarr
generate_bazarr_compose_file() {
    log "INFO" "Generando archivo Docker Compose en: $DOCKER_COMPOSE_FILE"

    # Verificar que PUID y PGID están definidos
    if [[ -z "$PUID" || -z "$PGID" ]]; then
        log "ERROR" "PUID o PGID no están definidos. No se puede generar el compose file."
        return 1
    fi

    # Crear backup del archivo existente si existe
    if ! create_backup "$DOCKER_COMPOSE_FILE"; then
        log "WARN" "No se pudo crear un backup del archivo docker-compose.yml existente (puede que no exista)."
        # Continuar de todas formas, ya que el archivo se sobrescribirá.
    fi

    # Usar cat con Here Document para escribir el archivo
    # Asegurarse de que las variables $PUID, $PGID, etc. se expandan correctamente
    # Usar rutas absolutas para los volúmenes
    cat <<EOF > "$DOCKER_COMPOSE_FILE"
---
# Docker Compose file for Bazarr
# Auto-generado por install_bazarr_docker.sh
version: "3.8" # Usar una versión razonablemente moderna

services:
  bazarr:
    image: lscr.io/linuxserver/bazarr:latest
    container_name: bazarr
    environment:
      - PUID=${PUID}          # User ID
      - PGID=${PGID}          # Group ID
      - TZ=${TIMEZONE}     # Zona Horaria
      # - UMASK=022 # Opcional: Descomentar si necesitas permisos específicos para archivos creados
    volumes:
      - ${BAZARR_APP_CONFIG_DIR}:/config # Ruta persistente para la configuración de Bazarr
      - ${MEDIA_MOVIES_DIR}:/movies     # Ruta a tus películas (¡DEBE EXISTIR!)
      - ${MEDIA_TV_DIR}:/tv             # Ruta a tus series (¡DEBE EXISTIR!)
      # Añade más volúmenes si es necesario (e.g., para sincronizar con Radarr/Sonarr si están fuera de Docker)
      # - /path/to/radarr/config:/radarr_config:ro # Ejemplo solo lectura
      # - /path/to/sonarr/config:/sonarr_config:ro # Ejemplo solo lectura
    ports:
      - 6767:6767 # Puerto estándar de Bazarr
    restart: unless-stopped # Reiniciar automáticamente a menos que se detenga manualmente
    # networks: # Opcional: Descomentar y configurar si usas una red Docker personalizada
    #   - mi_red_personalizada

# networks: # Opcional: Definir la red si se usa arriba
#   mi_red_personalizada:
#     external: true # O especificar driver: bridge, etc.
EOF

    # Verificar que el archivo se escribió correctamente
    if [[ $? -ne 0 ]]; then
        log "ERROR" "Fallo al escribir el archivo docker-compose.yml en: $DOCKER_COMPOSE_FILE"
        # Intentar restaurar el backup si falló la escritura
        restore_backup "$DOCKER_COMPOSE_FILE"
        return 1
    fi

    # Establecer permisos/propietario razonables para el compose file (root:root o user:group está bien)
    chown root:root "$DOCKER_COMPOSE_FILE" || log "WARN" "No se pudo cambiar propietario de $DOCKER_COMPOSE_FILE a root:root"
    chmod 644 "$DOCKER_COMPOSE_FILE" || log "WARN" "No se pudo cambiar permisos de $DOCKER_COMPOSE_FILE a 644"


    log "SUCCESS" "Archivo docker-compose.yml generado/actualizado correctamente."
    log "DEBUG" "Contenido de $DOCKER_COMPOSE_FILE:"
    log "DEBUG" "$(cat "$DOCKER_COMPOSE_FILE")" # Loguear contenido para depuración
    return 0
}

# Despliega o actualiza el contenedor Bazarr usando Docker Compose
deploy_bazarr_container() {
    log "INFO" "Desplegando/Actualizando el contenedor Bazarr..."

    if [[ ! -f "$DOCKER_COMPOSE_FILE" ]]; then
        log "ERROR" "Archivo Docker Compose no encontrado: $DOCKER_COMPOSE_FILE. No se puede desplegar."
        return 1
    fi

    local compose_cmd=""
    # Detectar qué comando de compose usar (V2 preferido)
    if docker compose version &>/dev/null; then
        compose_cmd="docker compose"
        log "INFO" "Usando Docker Compose V2 ('docker compose')."
    elif command_exists docker-compose; then
        compose_cmd="docker-compose"
        log "INFO" "Usando Docker Compose V1 ('docker-compose')."
    else
        log "ERROR" "No se encontró ningún comando de Docker Compose ('docker compose' o 'docker-compose')."
        return 1
    fi

    # Cambiar al directorio base donde está el compose file es buena práctica
    local current_dir
    current_dir=$(pwd)
    cd "$BAZARR_BASE_DIR" || {
        log "ERROR" "No se pudo cambiar al directorio base: $BAZARR_BASE_DIR"
        return 1
    }

    log "INFO" "Ejecutando: $compose_cmd -f $DOCKER_COMPOSE_FILE up -d --remove-orphans"
    # Usar --remove-orphans es útil si se renombran servicios en el compose file
    # El comando 'up -d' es idempotente: crea si no existe, o actualiza si la imagen/configuración cambió.
    if ! $compose_cmd -f "$DOCKER_COMPOSE_FILE" up -d --remove-orphans; then
        log "ERROR" "Fallo al ejecutar '$compose_cmd up -d'. Revisa los logs de Docker."
        cd "$current_dir" # Volver al directorio original
        return 1
    fi

    cd "$current_dir" # Volver al directorio original

    log "INFO" "Esperando unos segundos para que el contenedor inicie..."
    sleep 5

    # Verificar estado del contenedor
    log "INFO" "Verificando estado del contenedor 'bazarr'..."
    if ! docker ps --filter "name=^bazarr$" --format "{{.Names}} ({{.Status}})" | grep -q "bazarr"; then
         log "ERROR" "El contenedor 'bazarr' no parece estar ejecutándose después del despliegue."
         log "INFO" "Revisa los logs con: docker logs bazarr"
         return 1
    fi

    local container_status
    container_status=$(docker ps --filter "name=^bazarr$" --format "{{.Status}}")
    log "SUCCESS" "Contenedor Bazarr desplegado/actualizado. Estado actual: $container_status"
    return 0
}

# --- Función Principal de Instalación ---
main() {
    # 1. Inicialización y Verificaciones Previas
    check_root # Necesitamos ser root para instalar paquetes y gestionar Docker
    # setup_error_handling y setup_paths se llaman desde utils.sh,
    # pero los llamamos explícitamente para asegurar el orden y el log específico.
    setup_error_handling
    if ! setup_paths; then
       # Log ya habrá ocurrido en setup_paths si falló
       echo "[$(date --iso-8601=seconds)] [CRITICAL] [$$] Fallo en la configuración inicial de directorios/logs. Abortando." >&2
       exit 1
    fi
    log "INFO" "--- Iniciando Instalación/Configuración de Bazarr en Docker ---"
    check_network_connectivity || log "WARN" "Continuando sin conectividad de red, algunas operaciones pueden fallar."

    # 2. Instalar Dependencias Esenciales (jq es clave aquí)
    log "INFO" "Instalando dependencias base (curl, jq)..."
    # Añadir otras dependencias si son estrictamente necesarias para este script
    # Las dependencias de Docker/Compose se manejan en sus funciones
    if ! install_dependencies "curl" "jq"; then
        log "ERROR" "Fallo al instalar dependencias esenciales (curl, jq). Abortando."
        exit 1
    fi

    # 3. Leer y Validar Configuración de Usuario
    if ! parse_user_config; then
        log "ERROR" "Fallo al procesar la configuración de usuario ($CONFIG_JSON). Abortando."
        exit 1
    fi

    # 4. Instalar Docker y Docker Compose
    if ! install_docker_engine; then
        log "ERROR" "Fallo al instalar Docker Engine. Abortando."
        exit 1
    fi
    # Añadir usuario al grupo docker (informativo, requiere re-login para efecto)
    add_user_to_docker_group # No abortar si falla, solo advertir

    if ! install_docker_compose; then
        log "ERROR" "Fallo al instalar Docker Compose. Abortando."
        exit 1
    fi

    # 5. Preparar Directorios para Bazarr
    if ! setup_bazarr_directories; then
        log "ERROR" "Fallo al configurar los directorios para Bazarr. Abortando."
        exit 1
    fi

    # 6. Generar Archivo Docker Compose
    if ! generate_bazarr_compose_file; then
        log "ERROR" "Fallo al generar el archivo docker-compose.yml. Abortando."
        exit 1
    fi

    # 7. Desplegar Contenedor
    if ! deploy_bazarr_container; then
        log "ERROR" "Fallo al desplegar el contenedor Bazarr. Revisa los logs."
        exit 1
    fi

    # 8. Finalización Exitosa
    log "SUCCESS" "--- Instalación/Configuración de Bazarr completada exitosamente ---"
    echo ""
    log "INFO" "Bazarr debería estar accesible en tu red local."
    local ip_address
    ip_address=$(get_ip_address) # Usa la función de utils.sh
    echo -e "\n-----------------------------------------------------"
    echo -e " Accede a la interfaz web de Bazarr en:"
    echo -e "   \e[1;32mhttp://${ip_address}:6767\e[0m"
    echo -e "-----------------------------------------------------"
    echo -e "\n Comandos útiles:"
    echo -e "   - Ver logs: \e[0;33mdocker logs bazarr -f\e[0m"
    echo -e "   - Reiniciar: \e[0;33m(cd ${BAZARR_BASE_DIR} && docker compose restart)\e[0m" # Usar V2 si es posible
    echo -e "   - Parar: \e[0;33m(cd ${BAZARR_BASE_DIR} && docker compose down)\e[0m"
    echo -e "   - Actualizar Bazarr (baja nueva imagen y recrea):"
    echo -e "     \e[0;33m(cd ${BAZARR_BASE_DIR} && docker compose pull && docker compose up -d --remove-orphans)\e[0m"
    echo -e "\n ¡Recuerda configurar Bazarr conectándolo a Sonarr y Radarr!"
    echo -e "-----------------------------------------------------\n"

    return 0
}


# --- Punto de Entrada del Script ---
# Asegurarse de que el script no se ejecute si se está sourcing (importando)
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi