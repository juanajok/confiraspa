# confiraspa
Este repositorio contiene el script confiraspi, que automatiza la reinstalación y configuración de una Raspberry Pi con diversas aplicaciones y servicios.

Descripción
El script confiraspi es un script de shell que realiza varias tareas, incluyendo la actualización de la Raspberry Pi, configuración de IP estática, instalación y configuración de Samba, XRDP, Transmission, Mono, Sonarr y Webmin, y habilitar VNC. El objetivo del proyecto es facilitar la configuración de una Raspberry Pi para su uso en distintos escenarios.

Requisitos previos
Asegúrese de tener una Raspberry Pi con una distribución basada en Debian (por ejemplo, Raspberry Pi OS) y acceso a una terminal o línea de comandos en la Raspberry Pi.

Uso
Clone este repositorio en su Raspberry Pi:
 
git clone https://github.com/your-username/your-repository.git

Navegue hasta el directorio del repositorio clonado:
 
cd your-repository
Asegúrese de que el script confiraspi sea ejecutable:

chmod +x confiraspi

edite el archivo ip_config.json en el directorio del repositorio clonado, con la siguiente estructura:

{
  "interface": "eth0",
  "ip_address": "192.168.1.100/24",
  "routers": "192.168.1.1",
  "domain_name_servers": "8.8.8.8 8.8.4.4"
}

Ajuste los valores de interface, ip_address, routers y domain_name_servers según su configuración de red.

Edita también el fichero credenciales.json:
{
    "user": "pi",
    "password": "raspberry"
}

con el usuario y contraseña de tu raspberry pi. La aplicación aMule heredará las mismas credenciales
Ejecute el script:

./confiraspi
Siga las instrucciones en pantalla y espere a que se complete la ejecución del script.

Dependencias
El script confiraspi no tiene dependencias adicionales, pero instalará y configurará varios paquetes y servicios en su Raspberry Pi, como se mencionó anteriormente en la descripción.

Contribuciones
Las contribuciones son bienvenidas. Siéntase libre de abrir issues o enviar pull requests para mejorar el script o agregar nuevas funciones.

Licencia
Este proyecto está licenciado bajo la Licencia GNU General Public License v3.0. Para más información, consulte el archivo LICENSE en el repositorio.