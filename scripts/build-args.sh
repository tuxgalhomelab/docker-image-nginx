#!/usr/bin/env bash
set -e -o pipefail

script_parent_dir="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
repo_dir="$(realpath "${script_parent_dir:?}/..")"

ARGS_FILE="${repo_dir:?}/config/ARGS"

NGINX_REPO="https://nginx.org/packages/debian/"
NGINX_VERSION="1.20.2"
NGINX_DEBIAN_RELEASE="bullseye"
NGINX_MODULES=""
# Candidate modules are listed below:
# NGINX_MODULES="xslt geoip image-filter perl"
# There is also njs which uses a slightly different version format than the rest.
# The list can be seen here: https://nginx.org/packages/mainline/debian/pool/nginx/n/

nginx_src_repo() {
    echo -n "deb-src ${NGINX_REPO:?} ${NGINX_DEBIAN_RELEASE:?} nginx"
}

nginx_packages() {
    echo -n "nginx=${NGINX_VERSION:?}-1~${NGINX_DEBIAN_RELEASE:?} "
    for module in ${NGINX_MODULES:?}; do
        echo -n "nginx-module-${module}=${NGINX_VERSION:?}-1~${NGINX_DEBIAN_RELEASE:?} "
    done
}

nginx_build_args() {
    if [[ "$1" == "docker-flags" ]]; then
        local prefix="--build-arg "
        echo -n "${prefix:?}NGINX_SRC_REPO=\"$(nginx_src_repo)\" "
        echo -n "${prefix:?}NGINX_PACKAGES=\"$(nginx_packages)\" "
    else
        echo "NGINX_SRC_REPO=$(nginx_src_repo)"
        echo "NGINX_PACKAGES=$(nginx_packages)"
    fi
}

args_file_as_build_args() {
    local prefix=""
    if [[ "$1" == "docker-flags" ]]; then
        prefix="--build-arg "
        while IFS="=" read -r key value; do
            echo -n "${prefix}$key=\"$value\" "
        done < ${ARGS_FILE:?}
    else
        while IFS="=" read -r key value; do
            echo "$key=$value"
        done < ${ARGS_FILE:?}
    fi
}

github_env_dump() {
    args_file_as_build_args
    nginx_build_args
}

if [[ "$1" == "docker-flags" ]]; then
    # --build-arg format used with the docker build command.
    args_file_as_build_args $1
    nginx_build_args $1
else
    # Convert the build args into a multi-line format
    # that will be accepted by Github workflows.
    output=$(github_env_dump)
    output="${output//'%'/'%25'}"
    output="${output//$'\n'/'%0A'}"
    output="${output//$'\r'/'%0D'}"
    echo -e "::set-output name=build_args::$output"
fi
