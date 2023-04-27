#!/usr/bin/env python3

import json
import os
import shutil
import tarfile
import zipfile

# Definir la ruta de los backups y la extensión
BACKUP_DIR = "/media/Backup/"
BACKUP_EXT = {
    "zip": zipfile.ZipFile,
    "tar": tarfile.open,
    "": None  # No hay extensión para archivos sin comprimir
}

# Cargar la configuración desde el archivo JSON
with open("restore_apps.json") as f:
    config = json.load(f)

# Iterar sobre las aplicaciones y sus configuraciones
for app, app_config in config.items():
    backup_dir = os.path.join(BACKUP_DIR, app_config["backup_dir"])
    restore_dir = app_config["restore_dir"]
    backup_ext = app_config["backup_ext"]
    files = app_config.get("files", None)  # Lista opcional de ficheros a restaurar

    # Encontrar el último backup disponible en el directorio
    backup_files = os.listdir(backup_dir)
    backup_files = [f for f in backup_files if f.endswith(backup_ext)]
    backup_files = sorted(backup_files, reverse=True)
    if len(backup_files) == 0:
        print(f"No se encontraron backups para la aplicación {app}.")
        continue

    # Descomprimir o copiar el backup en la carpeta de restauración
    backup_file = os.path.join(backup_dir, backup_files[0])
    backup_ext = os.path.splitext(backup_file)[-1]
    if backup_ext in BACKUP_EXT:
        with BACKUP_EXT[backup_ext](backup_file, "r") as f:
            if files is None:
                f.extractall(restore_dir)
            else:
                for file in files:
                    f.extract(file, restore_dir)
    else:
        if files is None:
            shutil.copy(backup_file, restore_dir)
        else:
            for file in files:
                shutil.copy(os.path.join(backup_dir, file), restore_dir)

    print(f"Aplicación {app} restaurada desde {backup_file}.")

# Ejecuta el script
if __name__ == '__main__':
    main()
