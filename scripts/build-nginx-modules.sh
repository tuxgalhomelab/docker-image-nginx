#!/usr/bin/env bash
set -E -e -o pipefail

build_module() {
    local nginx_module="${1:?}"

    echo "Building ${nginx_module:?} for nginx ${NGINX_VERSION:?}-${NGINX_RELEASE_SUFFIX:?}"
    BASE_VERSION=${NGINX_VERSION:?} make rules-module-${nginx_module:?}
    mk-build-deps \
        --install '--tool=apt-get -o Debug::pkgProblemResolver=yes --no-install-recommends --yes' \
        debuild-module-${nginx_module:?}/nginx-${NGINX_VERSION:?}/debian/control
    BASE_VERSION=${NGINX_VERSION:?} make module-${nginx_module:?}
}

build_modules() {
    local nginx_modules="${1:?}"

    pushd /tmp/modules-build/pkg-oss/debian
    for nginx_module in ${nginx_modules:?}; do
        build_module "${nginx_module:?}"
    done
    popd
}

publish_artifacts() {
    rm -rf /modules-build
    mkdir -p /modules-build
    mv /tmp/modules-build/*.deb /modules-build
    rm /modules-build/*dbg_*.deb
}

build_modules "$@"
publish_artifacts
