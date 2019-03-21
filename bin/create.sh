#!/bin/sh

# Usage:
#     bin/create.sh DOMAIN
#
# Where domain should be the main domain used to access the site.

SRVDIR=$(dirname "$(dirname "$(readlink -f "$0")")")

DOMAIN="${1}"

mkdir -p "${SRVDIR}/apps/${DOMAIN}"

cp "${SRVDIR}/skeleton/docker-compose.yaml" "${SRVDIR}/apps/${DOMAIN}/docker-compose.yaml"
cp "${SRVDIR}/skeleton/docker-compose.override.yaml" "${SRVDIR}/apps/${DOMAIN}/docker-compose.override.yaml"
touch "${SRVDIR}/apps/${DOMAIN}/.env"
echo "HOSTNAME=${DOMAIN}" >> "${SRVDIR}/apps/${DOMAIN}/.env"

mkdir -p "${SRVDIR}/apps/${DOMAIN}/srv/public"
mkdir -p "${SRVDIR}/apps/${DOMAIN}/images"

ROOT=1

mkdir -p "${SRVDIR}/apps/${DOMAIN}/ssh"
touch "${SRVDIR}/apps/${DOMAIN}/ssh/authorized_keys"
cat "${HOME}/.ssh/authorized_keys" 2>/dev/null > "${SRVDIR}/apps/${DOMAIN}/ssh/authorized_keys"
chmod 0600 "${SRVDIR}/apps/${DOMAIN}/ssh/authorized_keys"
chown root:root "${SRVDIR}/apps/${DOMAIN}/ssh/authorized_keys" 2>/dev/null || ROOT=0
chmod 0755 "${SRVDIR}/apps/${DOMAIN}/ssh"
chown root:root "${SRVDIR}/apps/${DOMAIN}/ssh" 2>/dev/null || ROOT=0

if [ $ROOT -ne 1 ]; then
    echo "Please run as root:"
    echo "    chown -R root:root \"${SRVDIR}/apps/${DOMAIN}/ssh\""
fi
