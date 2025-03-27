#!/usr/bin/env python3
import os
import shutil
import re
from pathlib import Path

# Configuración principal
BASE_DIR = Path("/opt/confiraspa")
SCRIPTS_DIR = BASE_DIR / "scripts"
NEW_STRUCTURE = {
    "system": [
        "update_system.sh",
        "configure_crontab.sh",
        "generate_fstab.sh",
        "setup_logrotate_from_json.sh"
    ],
    "services": [
        "install_plex.sh",
        "install_samba.sh",
        "install_xrdp.sh",
        "install_transmission.sh",
        "install_amule.sh",
        "install_bazarr.sh",
        "install_calibre.sh",
        "install_mono.sh",
        "install_rclone.sh",
        "install_webmin.sh",
        "install_sonarr.sh",
        "install_arr.sh"
    ],
    "security": [
        "setup_credentials.sh",
        "change_permissions.sh",
        "enable_vnc.sh"
    ],
    "utils": [  # Scripts de Python
        "downloadclean.py",
        "rotabackup.py",
        "restaurarr.py"
    ],
    "main": [  # Script principal
        "confiraspi_v5.sh"
    ]
}

def create_directory_structure():
    """Crea la estructura de directorios requerida"""
    print("🛠 Creando estructura de directorios...")
    for category in NEW_STRUCTURE:
        (SCRIPTS_DIR / category).mkdir(parents=True, exist_ok=True)

def move_scripts():
    """Mueve los scripts a sus nuevas ubicaciones"""
    print("\n🚚 Moviendo scripts...")
    for category, scripts in NEW_STRUCTURE.items():
        for script in scripts:
            src = BASE_DIR / script
            dest = SCRIPTS_DIR / category / script
            
            if src.exists():
                shutil.move(str(src), str(dest))
                print(f"  ✓ {script} → {dest}")
            else:
                print(f"  ✗ {script} no encontrado. Saltando...")

def update_references():
    """Actualiza las referencias en los scripts y configuraciones"""
    print("\n🔄 Actualizando referencias...")
    
    # 1. Actualizar imports en scripts bash y Python
    for root, _, files in os.walk(SCRIPTS_DIR):
        for file in files:
            file_path = Path(root) / file
            if file.endswith((".sh", ".py")):
                update_file_references(file_path)
    
    # 2. Actualizar configuraciones JSON
    config_dir = BASE_DIR / "configs"
    for config_file in config_dir.glob("*.json"):
        update_json_paths(config_file)

def update_file_references(file_path):
    """Actualiza rutas en archivos individuales"""
    replacements = {
        r'source /opt/confiraspa/lib/utils.sh': 
            'source "$(dirname "$0")/../lib/utils.sh"',
        r'/opt/confiraspa/scripts/': 
            str(SCRIPTS_DIR) + '/',
        r'from lib\.utils':  # Para scripts Python
            'from ..lib.utils'
    }
    
    with open(file_path, 'r+') as f:
        content = f.read()
        for pattern, replacement in replacements.items():
            content = re.sub(pattern, replacement, content)
        
        f.seek(0)
        f.write(content)
        f.truncate()
    
    print(f"  ✓ Actualizado {file_path.name}")

def update_json_paths(json_file):
    """Actualiza rutas en archivos JSON"""
    with open(json_file, 'r+') as f:
        data = f.read()
        updated_data = data.replace(
            '/opt/confiraspa/scripts/', 
            str(SCRIPTS_DIR) + '/'
        )
        
        if data != updated_data:
            f.seek(0)
            f.write(updated_data)
            f.truncate()
            print(f"  ✓ Actualizado {json_file.name}")

def fix_permissions():
    """Ajusta los permisos de los archivos"""
    print("\n🔒 Ajustando permisos...")
    os.chmod(SCRIPTS_DIR, 0o755)
    for root, _, files in os.walk(SCRIPTS_DIR):
        os.chmod(root, 0o755)
        for file in files:
            file_path = Path(root) / file
            # Permisos específicos para scripts
            if file.endswith(".sh"):
                os.chmod(file_path, 0o750)
            elif file.endswith(".py"):
                os.chmod(file_path, 0o755)
    print("  ✓ Permisos configurados (750 para bash, 755 para Python)")

def main():
    print("🔧 Iniciando reorganización de scripts...")
    
    try:
        create_directory_structure()
        move_scripts()
        update_references()
        fix_permissions()
        
        print("\n✅ Reorganización completada con éxito!")
        print(f"Nueva estructura disponible en: {SCRIPTS_DIR}")
    except Exception as e:
        print(f"\n❌ Error: {str(e)}")
        exit(1)

if __name__ == "__main__":
    main()