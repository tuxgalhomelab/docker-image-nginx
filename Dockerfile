# syntax=docker/dockerfile:1

ARG BASE_IMAGE_NAME
ARG BASE_IMAGE_TAG
FROM ${BASE_IMAGE_NAME}:${BASE_IMAGE_TAG} AS modules-builder-base

ARG XSLSCRIPT_PL_SHA256_CHECKSUM
ARG NGINX_VERSION
ARG NGINX_RELEASE_SUFFIX

ENV NGINX_VERSION="${NGINX_VERSION}"
ENV NGINX_RELEASE_SUFFIX="${NGINX_RELEASE_SUFFIX}"

COPY scripts/build-nginx-modules.sh /scripts/

# hadolint ignore=SC2086,SC3044
RUN \
    set -E -e -o pipefail \
    && export HOMELAB_VERBOSE=y \
    && homelab install util-linux patch quilt build-essential make cmake g++ \
        git mercurial \
        lsb-release devscripts equivs debhelper \
        libkrb5-dev \
        libbrotli-dev \
        libssl-dev libpcre2-dev zlib1g-dev \
        libgeoip-dev libmaxminddb-dev \
        libgd-dev \
        libedit-dev libxml2-dev libxslt-dev libyaml-cpp-dev libboost-dev \
        libc-ares-dev \
        libperl-dev \
        libre2-dev \
        libxml2-utils xsltproc libparse-recdescent-perl \
        rake \
    && homelab install-bin \
        https://hg.nginx.org/xslscript/raw-file/01dc9ba12e1b/xslscript.pl \
        ${XSLSCRIPT_PL_SHA256_CHECKSUM:?} \
        xslscript.pl \
        xslscript \
        /opt/bin/xslscript.pl \
        root \
        root \
    # Clone the nginx modules source. \
    && mkdir -p /tmp/modules-build \
    && pushd /tmp/modules-build \
    && hg clone -r ${NGINX_VERSION:?}-${NGINX_RELEASE_SUFFIX:?} https://hg.nginx.org/pkg-oss/ \
    && popd

FROM modules-builder-base AS modules-builder-1
ARG NGINX_MODULES_SHARD_1
RUN /scripts/build-nginx-modules.sh "${NGINX_MODULES_SHARD_1:?}"

FROM modules-builder-base AS modules-builder-2
ARG NGINX_MODULES_SHARD_2
RUN /scripts/build-nginx-modules.sh "${NGINX_MODULES_SHARD_2:?}"

FROM modules-builder-base AS modules-builder-3
ARG NGINX_MODULES_SHARD_3
RUN /scripts/build-nginx-modules.sh "${NGINX_MODULES_SHARD_3:?}"

FROM modules-builder-base AS modules-builder-4
ARG NGINX_MODULES_SHARD_4
RUN /scripts/build-nginx-modules.sh "${NGINX_MODULES_SHARD_4:?}"

FROM modules-builder-base AS modules-builder-5
ARG NGINX_MODULES_SHARD_5
RUN /scripts/build-nginx-modules.sh "${NGINX_MODULES_SHARD_5:?}"

FROM modules-builder-base AS modules-builder-6
ARG NGINX_MODULES_SHARD_6
RUN /scripts/build-nginx-modules.sh "${NGINX_MODULES_SHARD_6:?}"

FROM modules-builder-base AS lua-modules-builder
ARG NGINX_LUA_PROMETHEUS_VERSION
ARG LUA_RESTY_CORE_VERSION

# hadolint ignore=SC3009
RUN \
    mkdir -p /lua-modules{,/prometheus,/resty-core} \
    && homelab download-git-repo \
        https://github.com/knyar/nginx-lua-prometheus \
        ${NGINX_LUA_PROMETHEUS_VERSION:?} \
        /tmp/lua-prometheus \
    && cp \
        /tmp/lua-prometheus/prometheus{,_keys,_resty_counter}.lua \
        /lua-modules/prometheus/ \
    # Download the necessary openresty lua resty core lua files (a dependency \
    # for the lua prometheus metrics exporter). \
    && homelab download-git-repo \
        https://github.com/openresty/lua-resty-core \
        ${LUA_RESTY_CORE_VERSION:?} \
        /tmp/lua-resty-core \
    && cp \
        /tmp/lua-resty-core/lib/resty/core/*.lua \
        /lua-modules/resty-core/

ARG BASE_IMAGE_NAME
ARG BASE_IMAGE_TAG
FROM ${BASE_IMAGE_NAME}:${BASE_IMAGE_TAG} AS configs-and-scripts

COPY scripts/start-nginx.sh /scripts/
COPY config/nginx.conf /configs/
COPY config/homelab_enabled_modules.conf /configs/

ARG BASE_IMAGE_NAME
ARG BASE_IMAGE_TAG
FROM ${BASE_IMAGE_NAME}:${BASE_IMAGE_TAG}

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

# hadolint ignore=DL4006,SC3040
RUN \
    --mount=type=bind,target=/modules/shard1,from=modules-builder-1,source=/modules-build \
    --mount=type=bind,target=/modules/shard2,from=modules-builder-2,source=/modules-build \
    --mount=type=bind,target=/modules/shard3,from=modules-builder-3,source=/modules-build \
    --mount=type=bind,target=/modules/shard4,from=modules-builder-4,source=/modules-build \
    --mount=type=bind,target=/modules/shard5,from=modules-builder-5,source=/modules-build \
    --mount=type=bind,target=/modules/shard6,from=modules-builder-6,source=/modules-build \
    --mount=type=bind,target=/lua-modules,from=lua-modules-builder,source=/lua-modules \
    --mount=type=bind,target=/configs,from=configs-and-scripts,source=/configs \
    --mount=type=bind,target=/scripts,from=configs-and-scripts,source=/scripts \
    set -E -e -o pipefail \
    && export HOMELAB_VERBOSE=y \
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
    # Build and install the nginx package using the nginx sources repo. \
    && homelab install-pkg-from-deb-src \
        "deb-src [signed-by=${NGINX_GPG_KEY_PATH:?}] ${NGINX_REPO:?} ${NGINX_RELEASE_DISTRO:?} nginx" \
        "nginx=${NGINX_VERSION:?}-${NGINX_RELEASE_SUFFIX:?}~${NGINX_RELEASE_DISTRO:?}" \
    # Install the nginx module packages using the deb files we built earlier. \
    && (find /modules -type f -iname '*.deb' -print0 | xargs -0 -r homelab install) \
    # Delete the debug versions of the modules.\
    && rm -f /etc/nginx/modules/*-debug.so \
    # Copy the lua modules needed by the nginx lua prometheus metrics exporter. \
    && mkdir -p /opt/lib/nginx-lua \
    && cp -rf /lua-modules/* /opt/lib/nginx-lua \
    && cp /configs/nginx.conf /etc/nginx/nginx.conf \
    # Enable relevant nginx modules by default. \
    && mkdir -p /etc/nginx/modules-enabled \
    && cp /configs/homelab_enabled_modules.conf /etc/nginx/modules-enabled/ \
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

EXPOSE 443

ENV LUA_PATH="/opt/lib/nginx-lua/prometheus/?.lua;/opt/lib/nginx-lua/resty-core/?.lua;;"
USER ${USER_NAME}:${GROUP_NAME}
WORKDIR /

CMD ["start-nginx"]
STOPSIGNAL SIGQUIT
