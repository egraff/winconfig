#!/bin/bash
set -e

# Note: this script is based on the installer script from msysGit
# (/share/msysGit/net/release.sh)

INSTALLER_NAME="winconfig"
INSTALLER_TITLE="winconfig installation"
INSTALLER_DIRNAME="winconfig"

TARGET="$(pwd -L)"/${INSTALLER_NAME}-install.exe
TMPDIR=/tmp/${INSTALLER_DIRNAME}
OPTS7="-m0=lzma -mx=9 -md=64M"
TMPPACK=/tmp.7z

# Get script dir
cd "$(dirname "${0}")"
SHARE="$(pwd -L)"
cd - > /dev/null

test ! -d "$TMPDIR" || rm -rf "$TMPDIR" || exit
mkdir "$TMPDIR"
cd "$TMPDIR"

(cd .. && test ! -f "$TMPPACK" || rm "$TMPPACK")

echo "Extracting winsible archive"
/usr/bin/7za x "$SHARE/winsible.7z"

echo "Copying files"

mkdir -p msys64/etc
cp "$SHARE"/gitconfig msys64/etc/
cp "$SHARE"/run.sh run.sh
cp "$SHARE"/run.ps1 run.ps1
rsync --archive -v "$SHARE"/ansible/ ansible/

echo "Installing ansible collections"

# Note: I haven't figured out how to enter the other MSYS environment from the first, without "inheriting" state
# that determines where the MSYS FS is rooted, so use cmd.exe as a wrapper to avoid this problem for now...
cmd /c 'msys64\usr\bin\sh.exe -c "cd ansible && export PATH=\"/usr/local/bin:/usr/bin:/bin:/opt/bin\" && ansible-galaxy collection install -f -r roles/requirements.yml"'

echo "Creating archive"

cd ..
/usr/bin/7za a $OPTS7 "$TMPPACK" ${TMPDIR}/*
(cat "$SHARE"/7zsd_extra/7zsd_All_x64.sfx &&
 echo ';!@Install@!UTF-8!' &&
 echo "Title=\"${INSTALLER_TITLE}\"" &&
 echo 'GUIFlags="8+32+64+256+4096"' &&
 echo 'GUIMode="1"' &&
 echo 'OverwriteMode="2"' &&
 echo "RunProgram=\"powershell.exe -WindowStyle Hidden -Command Start-Process -Wait -Verb RunAs powershell.exe -ArgumentList '-ExecutionPolicy ByPass -File \\\"%%T\\run.ps1\\\"'\"" &&
 echo ';!@InstallEnd@!' &&
 cat "$TMPPACK") > "$TARGET"

echo "Success! You'll find the new installer at \"$TARGET\"."
rm $TMPPACK
rm -rf "$TMPDIR"
