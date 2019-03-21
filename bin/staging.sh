#!/bin/bash

# Usage:
#     bin/staging.sh DOMAIN
#
# Where DOMAIN is an already created app.

SRVDIR="$(dirname "$(dirname "$(readlink -f "${0}")")")"
DOMAIN="${1}"
shift 1

ORIGINALDIR="${SRVDIR}/apps/${DOMAIN}"
STAGINGDIR="${SRVDIR}/apps/staging.${DOMAIN}"

if [ ! -d "${ORIGINALDIR}" ]; then
    echo "App for ${DOMAIN} does not exist."
    exit 1
fi

if [ $(id -u) -ne 0 ]; then
    echo "Please run as root."
    exit 1
fi

DATABASE="$(cd "${SRVDIR}/services"; docker-compose exec mysql mysql -u root -B --disable-column-names -e "SHOW DATABASES LIKE '${DOMAIN}'")"
if [ "${DATABASE}" -eq "" ]; then
    echo "Database \"${DOMAIN}\" does not exist."
    exit 1
fi

rm -rf "${STAGINGDIR}"
mkdir -p "${STAGINGDIR}"
sed -i -e "s@HOSTNAME=(.*)\$@HOSTNAME=staging.\1@g" "${STAGINGDIR}/.env"

# Create copy of code.
cp -r "${ORIGINALDIR}" "${STAGINGDIR}"

# Create copy of database.
(cd "${SRVDIR}/services"; docker-compose exec mysql mysql -u root -e "DROP DATABASE IF EXISTS \`staging.${DOMAIN}\`;")
echo "Dropped previous staging database..."
(cd "${SRVDIR}/services"; docker-compose exec mysql mysql -u root -e "CREATE DATABASE IF NOT EXISTS \`staging.${DOMAIN}\`;")
echo "Created database \"staging.${DOMAIN}\"..."

for SERVICE in "${@}"; do

    (cd "${STAGINGDIR}"; docker-compose ps "${SERVICE}" 1>/dev/null 2>&1)
    if [ $? -ne 0 ]; then
        echo "Service \"${SERVICE}\" does not exist for app \"staging.${DOMAIN}\", skipping..."
        continue 1
    fi

    CONTAINER="$(cd "${STAGINGDIR}"; docker-compose ps | grep "${SERVICE}" | cut -d' ' -f1)"
    # Use the domain as the username. The revise DNS resolves the IP address as "CONTAINER.NETWORK".
    (cd "${SRVDIR}/services"; docker-compose exec mysql mysql -u root -e "CREATE USER IF NOT EXISTS 'staging.${DOMAIN}'@'${CONTAINER}.services' IDENTIFIED BY 'staging.${DOMAIN}';")
    (cd "${SRVDIR}/services"; docker-compose exec mysql mysql -u root -e "GRANT ALL PRIVILEGES ON \`staging.${DOMAIN}\`.* TO 'staging.${DOMAIN}'@'${CONTAINER}.services';")
    echo "Granted \"staging.${DOMAIN}\" database access to \"staging.${DOMAIN}\" database for \"${SERVICE}\" service..."

done

(cd "${SRVDIR}/services"; docker-compose exec mysql mysql -u root -e "FLUSH PRIVILEGES;")
echo "Flushed changes..."

SQLFILE="$(tempfile)"
(cd "${SRVDIR/services"; docker-compose exec mysql mysqldump -u root --hex-blob "${DOMAIN}" > "${SQLFILE}")
echo "Database \"${DOMAIN}\" exported..."
(cd "${SRVDIR}/services"; docker-compose exec -T mysql mysql -u root "staging.${DOMAIN}" < "${SQLFILE}")
rm "${SQLFILE}"
echo "Database \"staging.${DOMAIN}\" imported..."
