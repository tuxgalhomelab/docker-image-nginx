#!/usr/bin/env bash

set -e -o pipefail

script_parent_dir="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
git_repo_dir="$(realpath "${script_parent_dir:?}/..")"

ARGS_FILE="${git_repo_dir:?}/config/ARGS"

nginx_deb_repo_latest_ver() {
    gpg_key_server=$(get_config_arg "NGINX_GPG_KEY_SERVER")
    gpg_key=$(get_config_arg "NGINX_GPG_KEY")
    gpg_key_path="$(get_config_arg "NGINX_GPG_KEY_PATH")"
    nginx_repo=$(get_config_arg "NGINX_REPO")
    nginx_release_distro=$(get_config_arg "NGINX_RELEASE_DISTRO")
    base_image=$(get_config_arg "BASE_IMAGE_NAME"):$(get_config_arg "BASE_IMAGE_TAG")
    docker run --rm ${base_image:?} sh -c "homelab export-gpg-key ${gpg_key_server:?} ${gpg_key:?} ${gpg_key_path:?} >/dev/null 2>&1 && echo 'deb-src [signed-by=${gpg_key_path:?}] ${nginx_repo:?} ${nginx_release_distro:?} nginx' > /etc/apt/sources.list.d/src_nginx.list && rm /etc/apt/sources.list.d/debian.sources && apt-get -qq update >/dev/null 2>&1 && (apt-cache madison nginx | cut -d '|' -f 2 | cut -d ' ' -f 2 | sort --version-sort --reverse | head -1 | sed -E 's/^(.+)~${nginx_release_distro:?}$/\1/g')"
}

get_config_arg() {
    arg="${1:?}"
    sed -n -E "s/^${arg:?}=(.*)\$/\\1/p" ${ARGS_FILE:?}
}

set_config_arg() {
    arg="${1:?}"
    val="${2:?}"
    sed -i -E "s/^${arg:?}=(.*)\$/${arg:?}=${val:?}/" ${ARGS_FILE:?}
}

pkg="Nginx"
config_ver_key_main="NGINX_VERSION"
config_ver_key_suffix="NGINX_RELEASE_SUFFIX"

existing_upstream_ver_main=$(get_config_arg ${config_ver_key_main:?})
existing_upstream_ver_suffix=$(get_config_arg ${config_ver_key_suffix:?})
existing_upstream_ver="${existing_upstream_ver_main:?}-${existing_upstream_ver_suffix:?}"
latest_upstream_ver=$(nginx_deb_repo_latest_ver)

if [[ "${existing_upstream_ver:?}" == "${latest_upstream_ver:?}" ]]; then
    echo "Existing config is already up to date and pointing to the latest upstream ${pkg:?} version '${latest_upstream_ver:?}'"
else
    latest_upstream_ver_main=$(echo ${latest_upstream_ver:?} | cut --delimiter='-' --fields=1)
    latest_upstream_ver_suffix=$(echo ${latest_upstream_ver:?} | cut --delimiter='-' --fields=2)
    echo "Updating ${pkg:?} '${existing_upstream_ver:?}' -> '${latest_upstream_ver:?}'"
    echo "Updating ${config_ver_key_main:?} '${existing_upstream_ver_main:?}' -> '${latest_upstream_ver_main:?}'"
    echo "Updating ${config_ver_key_suffix:?} '${existing_upstream_ver_suffix:?}' -> '${latest_upstream_ver_suffix:?}'"
    set_config_arg "${config_ver_key_main:?}" "${latest_upstream_ver_main:?}"
    set_config_arg "${config_ver_key_suffix:?}" "${latest_upstream_ver_suffix:?}"
    git add ${ARGS_FILE:?}
    git commit -m "feat: Bump upstream ${pkg:?} version to ${latest_upstream_ver:?}."
fi
