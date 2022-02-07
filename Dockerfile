ARG BASE_IMAGE_NAME
ARG BASE_IMAGE_TAG
FROM ${BASE_IMAGE_NAME}:${BASE_IMAGE_TAG}

SHELL ["/bin/bash", "-c"]

ARG USER_NAME
ARG GROUP_NAME
ARG USER_ID
ARG GROUP_ID
ARG NGINX_GPG_KEY
ARG NGINX_SRC_REPO
ARG NGINX_PACKAGES

RUN \
    set -e -o pipefail \
    # Create the user and the group. \
    && homelab add-user \
        ${USER_NAME:?} \
        ${USER_ID:?} \
        ${GROUP_NAME:?} \
        ${GROUP_ID:?} \
        --no-create-home-dir \
    && homelab install-pkg-gpg-key ${NGINX_GPG_KEY:?} \
    && homelab install-pkg-from-deb-src "${NGINX_SRC_REPO:?}" "${NGINX_PACKAGES:?}" \
    && sed -i 's,listen       80;,listen       8080;,' /etc/nginx/conf.d/default.conf \
    && sed -i '/user  nginx;/d' /etc/nginx/nginx.conf \
    && sed -i 's,/var/run/nginx.pid,/tmp/nginx.pid,' /etc/nginx/nginx.conf \
    && sed -i "/^http {/a \    proxy_temp_path /tmp/proxy_temp;\n    client_body_temp_path /tmp/client_temp;\n    fastcgi_temp_path /tmp/fastcgi_temp;\n    uwsgi_temp_path /tmp/uwsgi_temp;\n    scgi_temp_path /tmp/scgi_temp;\n" /etc/nginx/nginx.conf \
    # nginx user must own the cache and etc directory to write cache and tweak the nginx config \
    && chown -R nginx:nginx /var/cache/nginx \
    # && chmod -R g+w /var/cache/nginx \
    && chown -R nginx:nginx /etc/nginx \
    # && chmod -R g+w /etc/nginx \
    && chown nginx:nginx /var/log/nginx/access.log /var/log/nginx/error.log \
    # Clean up. \
    && homelab cleanup

EXPOSE 8080

STOPSIGNAL SIGQUIT

USER ${USER_NAME}:${GROUP_NAME}
WORKDIR /
CMD ["nginx", "-g", "daemon off;"]
