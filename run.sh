#!/bin/sh

# Note: this script is based on the setup script from msysGit
# (/share/msysGit/net/setup-msysgit.sh)

ORIG_PATH=$PATH
export PATH="/usr/local/bin:/usr/bin:/bin:/opt/bin:$PATH"

error () {
    echo "* error: $*"
    echo INSTALLATION ABORTED
    read -e IGNORED_INPUT
    trap - exit
    exit 1
}

echo
echo -------------------------------------------------------
echo Running Ansible (will prompt for username and password)
echo -------------------------------------------------------

ansible-playbook site.yml -v
