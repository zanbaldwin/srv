#!/bin/sh

SRVDIR=$(dirname "$(dirname "$(readlink -f "$0")")")
if [ ! -d "${SRVDIR}/apps/${1}" ]; then
    echo "There is no app available under \"${1}\"."
    exit 1
fi

DOMAIN="${1}"
shift 1

(cd "${SRVDIR}/services"; docker-compose exec mysql mysql -u root -e "CREATE DATABASE IF NOT EXISTS \`${DOMAIN}\`;")
echo "Created database \"${DOMAIN}\"..."

for SERVICE in "${@}"; do

    (cd "${SRVDIR}/apps/${DOMAIN}"; docker-compose ps "${SERVICE}" 1>/dev/null 2>&1)
    if [ $? -ne 0 ]; then
        echo "Service \"${SERVICE}\" does not exist for app \"${DOMAIN}\", skipping..."
        continue 1
    fi

    CONTAINER="$(cd "${SRVDIR}/apps/${DOMAIN}"; docker-compose ps | grep "${SERVICE}" | cut -d' ' -f1)"
    (cd "${SRVDIR}/services"; docker-compose exec mysql mysql -u root -e "CREATE USER IF NOT EXISTS '${DOMAIN}'@'${CONTAINER}.services' IDENTIFIED BY '${DOMAIN}';")
    (cd "${SRVDIR}/services"; docker-compose exec mysql mysql -u root -e "GRANT ALL PRIVILEGES ON \`${DOMAIN}\`.* TO '${DOMAIN}'@'${CONTAINER}.services';")
    echo "Granted \"${DOMAIN}\" database access to \"${DOMAIN}\" for \"${SERVICE}\" service..."
done

(cd "${SRVDIR}/services"; docker-compose exec mysql mysql -u root -e "FLUSH PRIVILEGES;")
echo 'Flushed changes...'
