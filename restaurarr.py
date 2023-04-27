#!/usr/bin/env python3

import json
import os
import shutil
import tarfile
import zipfile
import stat

#carga el contenido de un archivo de configuración en formato JSON y lo devuelve como un diccionario de Python.
def load_config(config_file):
    with open(config_file) as f:
        config = json.load(f)
    return config

#devuelve la ruta completa del archivo de backup más reciente de la aplicación
def get_latest_backup(backup_dir, backup_ext):
    backup_files = os.listdir(backup_dir)
    backup_files = [f for f in backup_files if f.endswith(backup_ext)]
    backup_files = sorted(backup_files, key=lambda f: os.path.getmtime(os.path.join(backup_dir, f)), reverse=True)
    if len(backup_files) == 0:
        return None
    else:
        return os.path.join(backup_dir, backup_files[0])


def restore_app(app, app_config):
    backup_dir = os.path.join(BACKUP_DIR, app_config["backup_dir"])
    restore_dir = app_config["restore_dir"]
    backup_ext = app_config["backup_ext"]
    files = app_config.get("files_to_restore", None)  # Lista opcional de ficheros a restaurar
    permissions = app_config.get("permissions", {})

    backup_file = get_latest_backup(backup_dir, backup_ext)
    if backup_file is None:
        print(f"No se encontraron backups para la aplicación {app}.")
        return

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

    # Cambiar los permisos de los archivos restaurados
    for file, perm in permissions.items():
        file_path = os.path.join(restore_dir, file)
        os.chmod(file_path, int(perm, 8))

    print(f"Aplicación {app} restaurada desde {backup_file}.")


def main():
    config_file = "restore_apps.json"
    config = load_config(config_file)

    for app, app_config in config.items():
        restore_app(app, app_config)


if __name__ == '__main__':
    main()
