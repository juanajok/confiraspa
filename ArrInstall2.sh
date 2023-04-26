
#!/bin/bash
### Description: \*Arr .NET Debian install
### Originally written for Radarr by: DoctorArr - doctorarr@the-rowlands.co.uk on 2021-10-01 v1.0
### Version v1.1 2021-10-02 - Bakerboy448 (Made more generic and conformant)
### Version v1.1.1 2021-10-02 - DoctorArr (Spellcheck and boilerplate update)
### Version v2.0.0 2021-10-09 - Bakerboy448 (Refactored and ensured script is generic. Added more variables.)
### Version v2.0.1 2021-11-23 - brightghost (Fixed datadir step to use correct variables.)
### Version v3.0.0 2022-02-03 - Bakerboy448 (Rewrote script to prompt for user/group and made generic for all \*Arrs)
### Version v3.0.1 2022-02-05 - aeramor (typo fix line 179: 'chown "$app_uid":"$app_uid" -R "$bindir"' -> 'chown "$app_uid":"$app_guid" -R "$bindir"')
### Version v3.0.3 2022-02-06 - Bakerboy448 fixup ownership
### Version v3.0.3a Readarr to develop
### Version v3.0.4 2022-03-01 - Add sleep before checking service status
### Version v3.0.5 2022-04-03 - VP-EN (Added Whisparr)
### Version v3.0.6 2022-04-26 - Bakerboy448 - binaries to group
### Additional Updates by: The \*Arr Community

### Boilerplate Warning
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
#EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
#MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
#NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
#LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
#OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
#WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

#constantes
scriptversion="3.0.6"
scriptdate="2022-04-26"
INSTALL_BASE_DIR="/opt"
DATA_BASE_DIR="/var/lib"

set -euo pipefail

log() {
    local function_name message timestamp
    function_name="$1"
    message="$2"
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] [$scriptname] [$function_name] $message"
}



function mostrar_info_version() {
    log "Running *Arr Install Script - Version [$scriptversion] as of [$scriptdate]"
}

function verificar_root() {
    if [ "$EUID" -ne 0 ]; then
        log "Please run as root."
        exit
    fi
}

function obtener_usuario_grupo() {
    app_uid=$(logname)
    app_guid=$(id -gn "$app_uid")
}

function crear_usuario_grupo() {
    if [ "$app_guid" != "$app_uid" ]; then
        if ! getent group "$app_guid" >/dev/null; then
            groupadd "$app_guid"
        fi
    fi
    if ! getent passwd "$app_uid" >/dev/null; then
        adduser --system --no-create-home --ingroup "$app_guid" "$app_uid"
        log "Created and added User [$app_uid] to Group [$app_guid]"
    fi
    if ! getent group "$app_guid" | grep -qw "$app_uid"; then
        log "User [$app_uid] did not exist in Group [$app_guid]"
        usermod -a -G "$app_guid" "$app_uid"
        log "Added User [$app_uid] to Group [$app_guid]"
    fi
}

function detener_aplicacion() {
    local app=$1
    if service --status-all | grep -Fq "$app"; then
        systemctl stop $app
        systemctl disable $app.service
        log "Stopped existing $app"
    fi
}

# Función para configurar directorios
function configurar_directorios() {
    local app_name=$1
    local usuario=$2
    local grupo=$3

    local install_dir="${INSTALL_BASE_DIR}/${app_name}"
    local data_dir="${DATA_BASE_DIR}/${app_name}"

    if [ ! -d "${install_dir}" ]; then
        mkdir -p "${install_dir}"
        chown "${usuario}:${grupo}" "${install_dir}"
        chmod 775 "${install_dir}"
    fi

    if [ ! -d "${data_dir}" ]; then
        mkdir -p "${data_dir}"
        chown "${usuario}:${grupo}" "${data_dir}"
        chmod 775 "${data_dir}"
    fi
}


# Función para verificar si un paquete está instalado
function paquete_instalado() {
    dpkg -s "$1" >/dev/null 2>&1
}

# Función para instalar paquetes requeridos
function instalar_paquetes_requeridos() {
    local paquetes=$1
    for paquete in ${paquetes}; do
        if ! paquete_instalado "${paquete}"; then
            log "Instalando paquete: ${paquete}"
            apt-get install -y "${paquete}"
        else
            log "Paquete ya instalado: ${paquete}"
        fi
    done
}

function descargar_instalar_aplicacion() {
    local app=$1
    local branch=$2
    local bindir=$3
    local datadir=$4
    local app_uid=$5
    local app_guid=$6

    ARCH=$(dpkg --print-architecture)
    dlbase="https://${app}.servarr.com/v1/update/${branch}/updatefile?os=linux&runtime=netcore"

    case "$ARCH" in
    "amd64") DLURL="${dlbase}&arch=x64" ;;
    "armhf") DLURL="${dlbase}&arch=arm" ;;
    "arm64") DLURL="${dlbase}&arch=arm64" ;;
    *)
        log "Arch not supported"
        exit 1
        ;;
    esac

    log ""
    log "Downloading..."
    wget --content-disposition "$DLURL"
    tar -xvzf ${app^}.*.tar.gz
    log ""
    log "Installation files downloaded and extracted"

    log "Removing existing installation"
    rm -rf $bindir
    log "Installing..."
    mv "${app^}" $installdir
    chown "$app_uid":"$app_guid" "$bindir"
    chown -R "$app_uid":"$app_guid" "$bindir"
    log "Application installed"
    rm ${app^}.*.tar.gz
}


function configurar_servicio_systemd() {
    local app=$1
    local bindir=$2
    local datadir=$3

    log ""
    log "Creating systemd service"
    cat >/etc/systemd/system/${app}.service <<EOL
[Unit]
Description=${app^} Daemon
After=syslog.target network.target

[Service]
User=${app_uid}
Group=${app_guid}
Type=simple
ExecStart=${INSTALL_BASE_DIR}/${app}/${app} -nobrowser -data=${datadir}
TimeoutStopSec=20
KillMode=process
Restart=on-failure
Restart-sec=2

[Install]
WantedBy=multi-user.target
EOL

    log ""
    log "Enabling and starting ${app^} service"
    systemctl enable ${app}.service
    systemctl start ${app}
}


function iniciar_aplicacion() {
    local app=$1
    log "Starting ${app^} ..."
    systemctl status $app
}

# Función para instalar una aplicación específica
function instalar_aplicacion() {
    local app_name=$1
    local app_port=$2
    local app_prerequisites=$3
    local app_umask=$4
    local app_branch=$5
    local usuario=$6
    local grupo=$7

    log "Instalando ${app_name}"
    detener_aplicacion "${app_name}"
    configurar_directorios "${app_name}" "${usuario}" "${grupo}"
    instalar_paquetes_requeridos "${app_prerequisites}"
    descargar_instalar_aplicacion "${app_name}" "${app_branch}" "${INSTALL_BASE_DIR}/${app_name}" "${DATA_BASE_DIR}/${app_name}" "${usuario}" "${grupo}"
    configurar_servicio_systemd "${app_name}" "${INSTALL_BASE_DIR}/${app_name}" "${DATA_BASE_DIR}/${app_name}"
    iniciar_aplicacion "${app_name}"
}

function principal() {
    mostrar_info_version
    verificar_root
    obtener_usuario_grupo
    crear_usuario_grupo

    # Leer el archivo JSON y procesar cada aplicación
    app_list=$(jq -c '.[]' apps.json)
    for app_data in ${app_list}; do
        app_name=$(echo "${app_data}" | jq -r '.name')
        app_port=$(echo "${app_data}" | jq -r '.port')
        app_prerequisites=$(echo "${app_data}" | jq -r '.prerequisites')
        app_umask=$(echo "${app_data}" | jq -r '.umask')
        app_branch=$(echo "${app_data}" | jq -r '.branch')
        
        instalar_aplicacion "${app_name}" "${app_port}" "${app_prerequisites}" "${app_umask}" "${app_branch}" "${app_uid}" "${app_guid}"

    done

    log ""
    log ""
    log "script finalizado"
}

principal

