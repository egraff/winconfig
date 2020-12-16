#!/bin/bash
set -e

# Note: this script is based on the installer script from msysGit
# (/share/msysGit/net/release.sh)

INSTALLER_NAME="winconfig"
INSTALLER_TITLE="winconfig installation"

RUN_BAT_SCRIPT_NAME="run.bat"

TARGET="$(pwd -L)"/${INSTALLER_NAME}-install.exe
TMPDIR=/tmp/msys-rootfs-tmp
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

echo "Copying files"

CR=$'\r'
cat <<EOF > ${RUN_BAT_SCRIPT_NAME}
@echo off${CR}
cd /D "%~dp0"${CR}
${CR}
mkdir ${INSTALLER_NAME}${CR}
cd ${INSTALLER_NAME}${CR}
${CR}
..\msys64\usr\bin\sh.exe /run.sh${CR}
EOF

mkdir msys64

sed 's/\r//g' "$SHARE"/fileList.txt | while read -r filepath || [ -n "$filepath" ]
do
  # do something with $filepath here
  rsync --archive --relative -v --progress --exclude "*.pyc" --exclude "*/__pycache__" /./${filepath} msys64/
done

sed 's/\r//g' "$SHARE"/fileList-mingw.txt | while read -r filepath || [ -n "$filepath" ]
do
  # do something with $filepath here
  rsync --archive --relative -v --progress --exclude "*.pyc" --exclude "*/__pycache__" /mingw64/./${filepath} msys64/
done

pushd msys64

strip usr/bin/*.exe usr/lib/git-core/*.exe

mkdir -p usr/share
cp -R /usr/share/terminfo ./usr/share/terminfo

mkdir -p usr/ssl
cp -R /usr/ssl/certs ./usr/ssl/certs

mkdir tmp

mkdir etc
cp "$SHARE"/gitconfig etc/
cp /etc/fstab ./etc/fstab
cp /etc/msystem ./etc/msystem
cp /etc/profile ./etc/profile

mkdir -p dev/shm

if test -d /etc/profile.d
then
	cp -R /etc/profile.d ./etc/profile.d
fi

cp "$SHARE"/run.sh run.sh
rsync --archive -v "$SHARE"/ansible/ ansible/

# Pop msys64 dir, to get back to $TMPDIR
popd

echo "Creating archive"

cd ..
/usr/bin/7za a $OPTS7 "$TMPPACK" msys-rootfs-tmp
(cat "$SHARE"/7zsd_extra/7zsd_All_x64.sfx &&
 echo ';!@Install@!UTF-8!' &&
 echo 'Title="${INSTALLER_TITLE}"' &&
 echo 'GUIFlags="8+32+64+256+4096"' &&
 echo 'GUIMode="1"' &&
 echo 'OverwriteMode="2"' &&
 echo 'RunProgram="cmd /c \"%%T\msys-rootfs-tmp\${RUN_BAT_SCRIPT_NAME}\""' &&
 echo ';!@InstallEnd@!' &&
 cat "$TMPPACK") > "$TARGET"

echo "Success! You'll find the new installer at \"$TARGET\"."
rm $TMPPACK
rm -rf "$TMPDIR"
