#!/bin/bash

# Usage:
#     bin/staging.sh DOMAIN
#
# Where DOMAIN is an already created app.

MYSQL_NETWORK="services"
SRVDIR="$(dirname "$(dirname "$(readlink -f "${0}")")")"
DOMAIN="${1}"
shift 1

ORIGINALDIR="${SRVDIR}/apps/${DOMAIN}"
STAGINGDIR="${SRVDIR}/apps/staging.${DOMAIN}"

if [ ! -d "${ORIGINALDIR}" ]; then
    echo "App for ${DOMAIN} does not exist."
    exit 1
fi


if [ "$(id -u)" != "0" ]; then
    echo "Please run as root."
    exit 1
fi

DATABASE="$(cd "${SRVDIR}/${MYSQL_NETWORK}" || { echo "Services directory missing"; exit 1; }; docker-compose exec mysql mysql -u root -B --disable-column-names -e "SHOW DATABASES LIKE '${DOMAIN}'")"
if [ "${DATABASE}" != "" ]; then
    echo "Database \"${DOMAIN}\" does not exist."
    exit 1
fi

rm -rf "${STAGINGDIR}"
mkdir -p "${STAGINGDIR}"

# Create copy of code.
rm -rf "${STAGINGDIR}" 2>/dev/null
cp -pra "${ORIGINALDIR}/." "${STAGINGDIR}/" || { echo "Could not copy \"${ORIGINALDIR}\" to \"${STAGINGDIR}\"."; exit 1; }
sed -i -r -e "s@HOSTNAME=(.*)\$@HOSTNAME=staging.\1@g" "${STAGINGDIR}/.env"

# Create copy of database.
(cd "${SRVDIR}/${MYSQL_NETWORK}"; docker-compose exec mysql mysql -u root -e "DROP DATABASE IF EXISTS \`staging.${DOMAIN}\`;")
echo "Dropped previous staging database..."
(cd "${SRVDIR}/${MYSQL_NETWORK}"; docker-compose exec mysql mysql -u root -e "CREATE DATABASE IF NOT EXISTS \`staging.${DOMAIN}\`;")
echo "Created database \"staging.${DOMAIN}\"..."

for SERVICE in "${@}"; do

    (cd "${STAGINGDIR}"; docker-compose ps "${SERVICE}" 1>/dev/null 2>&1)
    if [ $? -ne 0 ]; then
        echo "Service \"${SERVICE}\" does not exist for app \"staging.${DOMAIN}\", skipping..."
        continue 1
    fi

    CONTAINER="$(cd "${STAGINGDIR}"; docker-compose ps | grep "${SERVICE}" | cut -d' ' -f1)"
    # Use the domain as the username. The revise DNS resolves the IP address as "CONTAINER.NETWORK".
    (cd "${SRVDIR}/${MYSQL_NETWORK}"; docker-compose exec mysql mysql -u root -e "CREATE USER IF NOT EXISTS 'staging.${DOMAIN}'@'${CONTAINER}.${MYSQL_NETWORK}' IDENTIFIED BY 'staging.${DOMAIN}';")
    (cd "${SRVDIR}/${MYSQL_NETWORK}"; docker-compose exec mysql mysql -u root -e "GRANT ALL PRIVILEGES ON \`staging.${DOMAIN}\`.* TO 'staging.${DOMAIN}'@'${CONTAINER}.${MYSQL_NETWORK}';")
    echo "Granted \"staging.${DOMAIN}\" database access to \"staging.${DOMAIN}\" database for \"${SERVICE}\" service..."

done

(cd "${SRVDIR}/{$MYSQL_NETWORK}"; docker-compose exec mysql mysql -u root -e "FLUSH PRIVILEGES;")
echo "Flushed changes..."

SQLFILE="$(mktemp || { echo "Could not create temporary database export."; exit 1; })"
(cd "${SRVDIR}/${MYSQL_NETWORK}"; docker-compose exec mysql mysqldump -u root --hex-blob "${DOMAIN}" > "${SQLFILE}")
echo "Database \"${DOMAIN}\" exported..."
(cd "${SRVDIR}/${MYSQL_NETWORK}"; docker-compose exec -T mysql mysql -u root "staging.${DOMAIN}" < "${SQLFILE}")
rm "${SQLFILE}"
echo "Database \"staging.${DOMAIN}\" imported..."
