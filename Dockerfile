ARG BASE_IMAGE_NAME
ARG BASE_IMAGE_TAG
FROM ${BASE_IMAGE_NAME}:${BASE_IMAGE_TAG} AS builder

COPY scripts/start-nginx.sh /scripts/

SHELL ["/bin/bash", "-c"]

ARG XSLSCRIPT_PL_SHA256_CHECKSUM
ARG NGINX_VERSION
ARG NGINX_RELEASE_SUFFIX
ARG NGINX_MODULES

# hadolint ignore=SC2086
RUN \
    set -E -e -o pipefail \
    && homelab install util-linux patch quilt build-essential make cmake g++ \
        git mercurial \
        lsb-release devscripts equivs debhelper \
        libkrb5-dev \
        libbrotli-dev \
        libssl-dev libpcre2-dev zlib1g-dev \
        libgeoip-dev libmaxminddb-dev \
        libgd-dev \
        libedit-dev libxml2-dev libxslt-dev libyaml-cpp-dev libboost-dev \
        libre2-dev \
        libxml2-utils xsltproc libparse-recdescent-perl \
    && homelab install-bin \
        https://hg.nginx.org/xslscript/raw-file/01dc9ba12e1b/xslscript.pl \
        ${XSLSCRIPT_PL_SHA256_CHECKSUM:?} \
        xslscript.pl \
        xslscript \
        /opt/bin/xslscript.pl \
        root \
        root \
    && mkdir -p /tmp/nginx-modules-build \
    && pushd /tmp/nginx-modules-build \
    && hg clone -r ${NGINX_VERSION:?}-${NGINX_RELEASE_SUFFIX:?} https://hg.nginx.org/pkg-oss/ \
    && popd \
    && pushd /tmp/nginx-modules-build/pkg-oss/debian \
    && for nginx_module in ${NGINX_MODULES:?}; do \
        echo "Building ${nginx_module:?} for nginx ${NGINX_VERSION:?}-${NGINX_RELEASE_SUFFIX:?}"; \
        make rules-module-${nginx_module:?} BASE_VERSION=${NGINX_VERSION:?} NGINX_VERSION=${NGINX_VERSION:?}; \
        mk-build-deps --install '--tool=apt-get -o Debug::pkgProblemResolver=yes --no-install-recommends --yes' debuild-module-${nginx_module:?}/nginx-${NGINX_VERSION:?}/debian/control; \
        make module-${nginx_module:?} BASE_VERSION=${NGINX_VERSION:?} NGINX_VERSION=${NGINX_VERSION:?}; \
        done \
    && popd \
    && mkdir -p /nginx-modules-build \
    && mv /tmp/nginx-modules-build/*.deb /nginx-modules-build \
    && rm /nginx-modules-build/*dbg_*.deb \
    && rm -rf /tmp/nginx-modules-build

ARG BASE_IMAGE_NAME
ARG BASE_IMAGE_TAG
FROM ${BASE_IMAGE_NAME}:${BASE_IMAGE_TAG}

SHELL ["/bin/bash", "-c"]

ARG USER_NAME
ARG GROUP_NAME
ARG USER_ID
ARG GROUP_ID
ARG NGINX_VERSION
ARG NGINX_RELEASE_SUFFIX
ARG NGINX_RELEASE_DISTRO
ARG NGINX_REPO
ARG NGINX_GPG_KEY
ARG NGINX_GPG_KEY_SERVER
ARG NGINX_GPG_KEY_PATH

RUN \
    --mount=type=bind,target=/nginx-modules-build,from=builder,source=/nginx-modules-build \
    --mount=type=bind,target=/scripts,from=builder,source=/scripts \
    set -E -e -o pipefail \
    # Create the user and the group. \
    && homelab add-user \
        ${USER_NAME:?} \
        ${USER_ID:?} \
        ${GROUP_NAME:?} \
        ${GROUP_ID:?} \
        --no-create-home-dir \
    && homelab export-gpg-key \
        "${NGINX_GPG_KEY_SERVER:?}" \
        "${NGINX_GPG_KEY:?}" \
        "${NGINX_GPG_KEY_PATH:?}" \
    && homelab install-pkg-from-deb-src \
        "deb-src [signed-by=${NGINX_GPG_KEY_PATH:?}] ${NGINX_REPO:?} ${NGINX_RELEASE_DISTRO:?} nginx" \
        "nginx=${NGINX_VERSION:?}-${NGINX_RELEASE_SUFFIX:?}~${NGINX_RELEASE_DISTRO:?}" \
    && homelab install /nginx-modules-build/*.deb \
    && sed -i '/user  nginx;/d' /etc/nginx/nginx.conf \
    && sed -i 's,/var/run/nginx.pid,/tmp/nginx.pid,' /etc/nginx/nginx.conf \
    && sed -i '/^pid        \/tmp\/nginx.pid;/a include    /etc/nginx/modules-enabled/*.conf;' /etc/nginx/nginx.conf \
    && sed -i "/^http {/a \    proxy_temp_path /tmp/proxy_temp;\n    client_body_temp_path /tmp/client_temp;\n    fastcgi_temp_path /tmp/fastcgi_temp;\n    uwsgi_temp_path /tmp/uwsgi_temp;\n    scgi_temp_path /tmp/scgi_temp;\n" /etc/nginx/nginx.conf \
    && sed -i 's/#tcp_nopush     on;/tcp_nopush      on;\n    tcp_nodelay     on;/' /etc/nginx/nginx.conf \
    && sed -i 's/#gzip  on;/gzip  on;/' /etc/nginx/nginx.conf \
    # Copy the start-nginx.sh script. \
    && mkdir -p /opt/nginx \
    && cp /scripts/start-nginx.sh /opt/nginx/ \
    && ln -sf /opt/nginx/start-nginx.sh /opt/bin/start-nginx \
    # nginx user must own the cache and etc directory to write cache and tweak the nginx config \
    && chown -R ${USER_NAME:?}:${GROUP_NAME:?} /var/cache/nginx /etc/nginx /opt/nginx /opt/bin/start-nginx \
    # Forward request and error logs to the docker logs collector. \
    && ln -sf /dev/stdout /var/log/nginx/access.log \
    && ln -sf /dev/stderr /var/log/nginx/error.log \
    # Clean up. \
    && homelab cleanup

EXPOSE 80

USER ${USER_NAME}:${GROUP_NAME}
WORKDIR /

CMD ["start-nginx"]
STOPSIGNAL SIGQUIT
