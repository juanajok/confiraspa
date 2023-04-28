import json
import os
import shutil
import tarfile
import zipfile
import subprocess



# Carga el contenido de un archivo de configuración en formato JSON y lo devuelve como un diccionario de Python.
def load_config(config_file):
    try:
        with open(config_file) as f:
            config = json.load(f)
            return config
    except FileNotFoundError:
        print(f"No se pudo abrir el archivo de configuración {config_file}.")
        return None


# Devuelve la ruta completa del archivo de backup más reciente de la aplicación.
def get_latest_backup(backup_dir, backup_ext):
    if not os.path.exists(backup_dir):
        print(f"El directorio de backup {backup_dir} no existe.")
        return None

    backup_files = os.listdir(backup_dir)
    backup_files = [f for f in backup_files if f.endswith(backup_ext)]
    backup_files = sorted(backup_files, key=lambda f: os.path.getmtime(os.path.join(backup_dir, f)), reverse=True)
    if len(backup_files) == 0:
        return None
    else:
        return os.path.join(backup_dir, backup_files[0])

def stop_app(app):
    print(f"Deshabilitando la aplicación {app}...")
    try:
        subprocess.run(["sudo", "systemctl", "stop", app], check=True)
        print(f"La aplicación {app} ha sido detenida exitosamente.")
    except subprocess.CalledProcessError:
        print(f"Error al detener la aplicación {app}.")


def start_app(app):
    print(f"Habilitando la aplicación {app}...")
    try:
        subprocess.run(["sudo", "systemctl", "start", app], check=True)
        print(f"La aplicación {app} ha sido arrancada exitosamente.")
    except subprocess.CalledProcessError:
        print(f"Error al arrancar la aplicación {app}.")


def restore_app(app, app_config):
    # Obtener la información de la configuración de la aplicación
    backup_dir = app_config["backup_dir"]
    backup_ext = app_config["backup_ext"]
    restore_dir = app_config["restore_dir"]
    files = app_config.get("files_to_restore", [])
    permissions = app_config.get("permissions", {})

    # Detener la aplicación antes de la restauración
    stop_app(app)

    # Verificar si la carpeta de restauración existe antes de continuar
    if not os.path.exists(restore_dir):
        print(f"No existe la carpeta de restauración '{restore_dir}', creando...")
        os.makedirs(restore_dir)
        print(f"Carpeta de restauración '{restore_dir}' creada exitosamente.")

    # Crear la carpeta backup_orig y hacer una copia de los archivos originales
    backup_orig_dir = os.path.join(restore_dir, "backup_orig")
    if not os.path.exists(backup_orig_dir):
        print(f"No existe la carpeta '{backup_orig_dir}', creando...")
        os.makedirs(backup_orig_dir)
        print(f"Carpeta '{backup_orig_dir}' creada exitosamente.")
    print("Haciendo una copia de los archivos originales en la carpeta 'backup_orig'...")
    for file in files:
        src_path = os.path.join(restore_dir, file)
        dst_path = os.path.join(backup_orig_dir, file)
        if os.path.exists(src_path):
            shutil.copy(src_path, dst_path)
            print(f"Archivo '{file}' copiado exitosamente a la carpeta 'backup_orig'.")
        else:
            print(f"No se encontró el archivo '{file}' en la carpeta de restauración.")

    # Encontrar el último backup disponible en el directorio de backup
    backup_file = get_latest_backup(backup_dir, backup_ext)
    if backup_file is None:
        print(f"No se encontraron backups para la aplicación '{app}'.")
        return
    print(f"Último backup encontrado para la aplicación '{app}': '{backup_file}'.")
    print(f"La extensión del archivo de backup es '{backup_ext}'.")


    # Restaurar los archivos desde el backup en la carpeta de restauración
    print(f"Restaurando los archivos de la aplicación '{app}'...")
    if backup_ext.endswith("zip"):
        with zipfile.ZipFile(backup_file, "r") as f:
            print(f"La extensión del archivo de backup es '{backup_ext}'.")
            print(f"Archivos en el archivo zip: {f.namelist()}")
            for file in files:
                try:
                    f.extract(file, restore_dir)
                    print(f"Archivo '{file}' restaurado exitosamente.")
                except KeyError:
                    print(f"No se encontró el archivo '{file}' en el backup '{backup_file}'.")

    elif backup_ext.endswith(("tar", "tar.gz", "tgz")):
        with tarfile.open(backup_file, "r") as f:
            for file in files:
                try:
                    f.extract(file, restore_dir)
                    print(f"Archivo '{file}' restaurado exitosamente.")
                except KeyError:
                    print(f"No se encontró el archivo '{file}' en el backup '{backup_file}'.")
    else:
        for file in files:
            src_path = os.path.join(backup_dir, file)
            dst_path = os.path.join(restore_dir, file)
            if os.path.exists(src_path):
                shutil.copy(src_path, dst_path)
                print(f"Archivo '{file}' restaurado exitosamente.")
            else:
                print(f"No se encontró el archivo '{file}' en el directorio de backup.")

    # Cambiar los permisos de los archivos restaurados
    for file, perm in permissions.items():
        file_path = os.path.join(restore_dir, file)
        if os.path.isfile(file_path):
            os.chmod(file_path, int(perm, 8))
        else:
            print(f"No se pudo cambiar los permisos para el archivo {file_path}.")


    print(f"Aplicación {app} restaurada desde {backup_file}.")



def main():
    # Cargar la configuración desde el archivo JSON
    config = load_config("restore_apps.json")

    # Iterar sobre las aplicaciones y restaurar cada una
    for app, app_config in config.items():
        restore_app(app, app_config)

    # iniciar la aplicación después de la restauración
    start_app(app)

    print("Proceso de restauración finalizado con éxito.")


if __name__ == '__main__':
    main()