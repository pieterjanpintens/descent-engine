"""Builds the standalone importer the app downloads for its "Import game assets" button: asset_importer.py and the
other import tools packaged with PyInstaller (Python and UnityPy inside), archived as

    Descent-Engine-importer-<windows|linux|macos>-<x86_64|arm64>.<zip|tar.gz>      (zip on Windows)

PyInstaller cannot cross-compile, so this runs once per platform (the release workflow does). Needs:
    pip install UnityPy pyinstaller
Usage: python build_importer.py [output folder]        (default: the current folder)
"""

import os
import platform
import shutil
import subprocess
import sys
import tarfile
import tempfile
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
NAME = "asset_importer"
# Imported by name at run time (asset_importer.STEPS), so PyInstaller cannot see them by itself.
MODULES = ["import_official_assets", "import_monster_meshes", "import_hero_meshes", "import_weapon_data",
           "import_item_data", "import_monster_data", "user_data"]
# Packages whose data files / native libraries PyInstaller misses. fmod_toolkit: UnityPy loads its audio library
# even when only decoding images - without it every image export fails.
COLLECT = ["UnityPy", "archspec", "fmod_toolkit", "pyfmodex"]


def archive_name() -> str:
    system = {"Windows": "windows", "Darwin": "macos", "Linux": "linux"}[platform.system()]
    machine = platform.machine().lower()
    arch = "arm64" if machine in ("arm64", "aarch64") else "x86_64"
    return "Descent-Engine-importer-%s-%s.%s" % (system, arch, "zip" if system == "windows" else "tar.gz")


def main() -> int:
    out_dir = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.getcwd()
    work = tempfile.mkdtemp(prefix="importer_build_")
    command = [sys.executable, "-m", "PyInstaller", "--noconfirm", "--onedir", "--console", "--name", NAME,
               "--paths", HERE, "--distpath", os.path.join(work, "dist"), "--workpath", os.path.join(work, "build"),
               "--specpath", work]
    for module in MODULES:
        command += ["--hidden-import", module]
    for package in COLLECT:
        command += ["--collect-all", package]
    command.append(os.path.join(HERE, "asset_importer.py"))
    if subprocess.call(command) != 0:
        return 1

    built = os.path.join(work, "dist", NAME)
    os.makedirs(out_dir, exist_ok=True)
    target = os.path.join(out_dir, archive_name())
    if os.path.exists(target):
        os.remove(target)
    if target.endswith(".zip"):
        with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as archive:
            for folder, _dirs, files in os.walk(built):
                for file_name in files:
                    path = os.path.join(folder, file_name)
                    archive.write(path, os.path.join(NAME, os.path.relpath(path, built)))
    else:
        with tarfile.open(target, "w:gz") as archive:  # keeps the executable bits and the links between libraries
            archive.add(built, arcname=NAME)
    shutil.rmtree(work, ignore_errors=True)
    print("Wrote %s (%.1f MB)" % (target, os.path.getsize(target) / 1048576.0))
    return 0


if __name__ == "__main__":
    sys.exit(main())
