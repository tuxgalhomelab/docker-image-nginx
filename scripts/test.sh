#!/usr/bin/env bash
set -e -o pipefail

random_container_name() {
    shuf -zer -n10  {A..Z} {a..z} {0..9} | tr -d '\0'
}

cleanup_container() {
    echo "Stopping the ${container_type:?} container ${container_name:?} ..."
    docker stop ${container_name:?} --time 5 2>/dev/null 1>&2 || /bin/true
    docker kill ${container_name:?} 2>/dev/null 1>&2 || /bin/true
}

container_type="nginx"
container_name=$(random_container_name)

echo "Starting ${container_type:?} container ${container_name:?} in the background ..."
docker run \
    --name ${container_name:?} \
    --detach \
    --rm \
    --publish 127.0.0.1:8082:8080 \
    ${IMAGE:?}

echo "Waiting for the ${container_type:?} container ${container_name:?} to finish starting up ..."
sleep 10

echo "Running tests against the ${container_type:?} container ${container_name:?} ..."

set +e
http_status_code=$(\
    curl -w "%{http_code}" --silent --output /dev/null --location http://127.0.0.1:8082/)
return_code=$?
set -e

if [[ $return_code != "0" ]]; then
    echo "Test failed: Obtained non-zero return code"
    echo "Output: ${http_status_code}"
    echo "Return Code: ${return_code}"
    cleanup_container
    exit 1
fi
if [[ ${http_status_code:?} != "200" ]]; then
    echo "Test failed: Status code is not 200"
    echo "Output: ${http_status_code}"
    echo "Return Code: ${return_code}"
    cleanup_container
    exit 1
fi
echo "All tests passed against the ${container_type:?} container ${container_name:?} ..."

cleanup_container
