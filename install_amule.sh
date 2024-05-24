#!/bin/bash

# Función de registro para imprimir mensajes con marca de tiempo
log() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${FUNCNAME[1]}] $message"
}

# Imprime un mensaje indicando que se están instalando aMule y sus dependencias
log "Instalando aMule y sus dependencias..."

# Actualiza la lista de paquetes e instala aMule y sus utilidades
apt-get update
apt-get install -y amule amule-utils amule-daemon amule-utils-gui

log "aMule y sus dependencias instaladas correctamente."

# Ejecuta aMule por primera vez para generar archivos de configuración
sudo -u $usuario amuled --ec-config <<< "$contrasena" &

# Espera 20 segundos y luego detiene el servicio de aMule
sleep 20
pkill -f amuled
log "El demonio de aMule ha sido detenido."

cd "$script_path"

# Crea una copia de seguridad del archivo de configuración de aMule
cp /home/$usuario/.aMule/amule.conf /home/$usuario/.aMule/amule.conf.backup
log "Copia de seguridad de amule.conf creada."

# Lee las rutas de directorios del archivo JSON
directories_json="amule_directories.json"
incoming_directory=$(jq -r '.incoming_directory' "$directories_json")
temp_directory=$(jq -r '.temp_directory' "$directories_json")

# Actualiza el archivo de configuración de aMule con las nuevas rutas
amule_conf_path="/home/$usuario/.aMule/amule.conf"
sed -i "s|^IncomingDir=.*$|IncomingDir=$incoming_directory|" "$amule_conf_path"
sed -i "s|^TempDir=.*$|TempDir=$temp_directory|" "$amule_conf_path"
sed -i "s|^Template=.*$|Template=webserver|" "$amule_conf_path"
sed -i "s|^Password=.*$|Password=$(echo -n $contrasena | md5sum | awk '{ print $1 }')|" "$amule_conf_path"
sed -i "s|^User=.*$|User=$usuario|" "$amule_conf_path"
sed -i "s|^AcceptExternalConnections=.*$|AcceptExternalConnections=1|" "$amule_conf_path"
sed -i "/^\[WebServer\]/,/^\[/ s|^Enabled=.*$|Enabled=1|" "$amule_conf_path"
sed -i "/^\[WebServer\]/,/^\[/ s|^Port=.*$|Port=4711|" "$amule_conf_path"
sed -i "s|^ECPassword=.*$|ECPassword=$(echo -n $contrasena | md5sum | awk '{ print $1 }')|" "$amule_conf_path"

log "Se han actualizado las rutas de directorios y la configuración en amule.conf."

# Crea el archivo de servicio para aMule
cat << EOF | tee /etc/systemd/system/amule.service
[Unit]
Description=aMule Daemon
After=network.target

[Service]
User=$usuario
Type=forking
ExecStart=/usr/bin/amuled -f
ExecStop=/usr/bin/pkill -f amuled
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# Crea el archivo de servicio para la interfaz gráfica de aMule
cat << EOF | tee /etc/systemd/system/amule-gui.service
[Unit]
Description=aMule GUI
After=amule.service

[Service]
User=$usuario
Type=simple
ExecStart=/usr/bin/amule

[Install]
WantedBy=graphical.target
EOF

# Recarga los servicios de systemd y habilita los nuevos servicios
systemctl daemon-reload
systemctl enable amule.service
systemctl enable amule-gui.service
systemctl restart amule.service
systemctl restart amule-gui.service

log "Servicios de aMule y aMule GUI configurados y reiniciados correctamente."
