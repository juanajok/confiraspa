import os
import json
import hashlib
import logging

# Configurar el logger con niveles adicionales
logging.basicConfig(
    format='%(asctime)s %(levelname)s [%(filename)s:%(funcName)s]: %(message)s', 
    level=logging.INFO,
    handlers=[
        logging.StreamHandler(),  # Para que los mensajes del logger se muestren en la consola
        logging.FileHandler('log.txt')  # Para que los mensajes se guarden en un archivo de registro
    ]
)

logger = logging.getLogger()

def get_hash(file_path):
    """Calcula y devuelve el hash MD5 de un archivo en bytes."""
    hasher = hashlib.md5()
    try:
        with open(file_path, 'rb') as f:
            for chunk in iter(lambda: f.read(4096), b""):
                hasher.update(chunk)
        return hasher.hexdigest()
    except Exception as e:
        logger.error(f"Error while reading file {file_path}: {e}")
        return None

def check_file_in_library(file_path, library_dir):
    """Comprueba si un archivo existe en una biblioteca de medios mediante su hash MD5."""
    file_size = os.path.getsize(file_path)
    logger.debug(f"Checking if file {file_path} with size {file_size} is in {library_dir}")
    
    for entry in os.scandir(library_dir):
        if entry.is_file() and entry.stat().st_size == file_size:
            file_hash = get_hash(file_path)
            if file_hash and get_hash(entry.path) == file_hash:
                logger.info(f"File {file_path} matches with {entry.path} in {library_dir}")
                return True
            elif not file_hash:
                logger.debug(f"Could not calculate hash for file {file_path}")
        elif entry.is_dir():
            logger.debug(f"Checking directory {entry.path}")
            if check_file_in_library(file_path, entry.path):
                return True
    
    logger.debug(f"File {file_path} not found in {library_dir}")
    return False

def delete_file(file_path):
    """Borra un archivo."""
    try:
        os.unlink(file_path)
        logger.info(f"Deleted file {file_path}")
        return True
    except FileNotFoundError:
        logger.warning(f"File {file_path} not found")
        return False
    except Exception as e:
        logger.error(f"Error deleting {file_path}: {e}")
        return False

def get_file_extension(file_path):
    """Obtiene la extensión de un archivo."""
    return os.path.splitext(file_path)[1].lower()

def find_files_recursively(directory, extensions):
    """Encuentra recursivamente todos los archivos con las extensiones dadas en un directorio y sus subdirectorios."""
    matching_files = []
    
    try:
        for entry in os.scandir(directory):
            if entry.is_file() and get_file_extension(entry.path) in extensions:
                logger.info(f"Found file {entry.path} with extension {get_file_extension(entry.path)}")
                matching_files.append(entry.path)
            elif entry.is_dir():
                logger.debug(f"Recursing into directory {entry.path}")
                matching_files += find_files_recursively(entry.path, extensions)
    except (FileNotFoundError, PermissionError) as e:
        logger.warning(f"Error accessing directory {directory}: {e}")
    
    return matching_files

def remove_empty_directories_recursively(top_directory):
    """Elimina recursivamente todos los directorios vacíos bajo el directorio superior dado."""
    for root, dirs, _ in os.walk(top_directory, topdown=False):
        for directory in dirs:
            directory_path = os.path.join(root, directory)
            if not os.listdir(directory_path):  # Verifica si el directorio está vacío
                os.rmdir(directory_path)
                logger.info(f"Deleted empty directory {directory_path}")

def main():
    # Cargar directorios desde JSON
    config_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "directories.json")
    try:
        with open(config_path, "r") as f:
            directories = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError) as e:
        logger.error(f"Error loading configuration file: {e}")
        return

    download_dir = directories.get("download_dir")
    series_dir = directories.get("series_dir")
    movies_dir = directories.get("movies_dir")
    music_dir = directories.get("music_dir")

    # Verifica si todos los directorios necesarios están presentes en el archivo JSON
    if None in [download_dir, series_dir, movies_dir, music_dir]:
        logger.error("One or more directories are missing from directories.json. Please check the file and try again.")
        return

    # Define la lista de tipos de archivo y su información asociada
    file_types = [
        ((".mp4", ".mkv", ".avi"), series_dir, "Series", "series"),
        ((".mp4", ".mkv", ".avi"), movies_dir, "Movies", "movies"),
        ((".mp3", ".flac", ".ogg"), music_dir, "Music", "music")
    ]

    # Itera sobre los tipos de archivo y procesa los archivos
    for extensions, destination_dir, log_name, print_name in file_types:
        matching_files = find_files_recursively(download_dir, extensions)
        if matching_files:
            logger.info(f"Processing {len(matching_files)} {print_name} files")
            for file_path in matching_files:
                logger.info(f"Processing file {file_path}")
                if check_file_in_library(file_path, destination_dir):
                    if delete_file(file_path):
                        logger.info(f"Deleted {file_path} from {print_name} library")
                    else:
                        logger.warning(f"Failed to delete {file_path} from {print_name} library")
                else:
                    logger.info(f"File {file_path} not found in {print_name} library, skipping deletion.")
        else:
            logger.info(f"No {print_name} files found to process")

    # Elimina carpetas vacías
    remove_empty_directories_recursively(download_dir)

if __name__ == '__main__':
    main()
