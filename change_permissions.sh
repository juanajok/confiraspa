#!/bin/sh

#chmod +x /home/pi/confiraspa/change_permissions.sh


sudo chown -R pi /media/discoduro/torrents /media/WDElements/Peliculas "/media/WDElements/Series TV" "/media/WDElements/Libros/Biblioteca de Calibre"
for dir in /media/discoduro/torrents /media/WDElements/Peliculas "/media/WDElements/Series TV" "/media/WDElements/Libros/Biblioteca de Calibre"; do
    sudo chmod -R 777 "$dir"
done    