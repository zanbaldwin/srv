#!/bin/sh

# Usage:
#     bin/database.sh DOMAIN ...SERVICES
#
# Where DOMAIN is the site in /apps/ and SERVICES is the list of containers/services
# listed in the sites docker-compose configuration file that should have access to
# the MySQL database.

SRVDIR=$(dirname "$(dirname "$(readlink -f "$0")")")
if [ ! -d "${SRVDIR}/apps/${1}" ]; then
    echo "There is no app available under \"${1}\"."
    exit 1
fi

DOMAIN="${1}"
shift 1

(cd "${SRVDIR}/services"; docker-compose exec mysql mysql -u root -e "CREATE DATABASE IF NOT EXISTS \`${DOMAIN}\`;")
if [ $? -ne 0 ]; then
    echo "Could not connect to MySQL..."
    exit 1
fi
echo "Created database \"${DOMAIN}\"..."

for SERVICE in "${@}"; do

    (cd "${SRVDIR}/apps/${DOMAIN}"; docker-compose ps "${SERVICE}" 1>/dev/null 2>&1)
    if [ $? -ne 0 ]; then
        echo "Service \"${SERVICE}\" does not exist for app \"${DOMAIN}\", skipping..."
        continue 1
    fi

    CONTAINER="$(cd "${SRVDIR}/apps/${DOMAIN}"; docker-compose ps | grep "${SERVICE}" | cut -d' ' -f1)"
    # Use the domain as the username. The reverse DNS resolves the IP address as "CONTAINER.NETWORK".
    (cd "${SRVDIR}/services"; docker-compose exec mysql mysql -u root -e "CREATE USER IF NOT EXISTS '${DOMAIN}'@'${CONTAINER}.services' IDENTIFIED BY '${DOMAIN}';")
    (cd "${SRVDIR}/services"; docker-compose exec mysql mysql -u root -e "GRANT ALL PRIVILEGES ON \`${DOMAIN}\`.* TO '${DOMAIN}'@'${CONTAINER}.services';")
    echo "Granted \"${DOMAIN}\" database access to \"${DOMAIN}\" for \"${SERVICE}\" service..."
done

(cd "${SRVDIR}/services"; docker-compose exec mysql mysql -u root -e "FLUSH PRIVILEGES;")
echo 'Flushed changes...'
