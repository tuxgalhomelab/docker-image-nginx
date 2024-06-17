#!/usr/bin/env bash
set -E -e -o pipefail

set_umask() {
    # Configure umask to allow write permissions for the group by default
    # in addition to the owner.
    umask 0002
}

start_nginx() {
    echo "Starting Nginx ..."
    echo

    exec nginx -g 'daemon off;'
}

set_umask
start_nginx
