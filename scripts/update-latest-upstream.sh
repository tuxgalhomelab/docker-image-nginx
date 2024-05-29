#!/usr/bin/env bash

set -e -o pipefail

script_parent_dir="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
git_repo_dir="$(realpath "${script_parent_dir:?}/..")"

ARGS_FILE="${git_repo_dir:?}/config/ARGS"

grep_cookie() {
    output="${1:?}"
    cookie="${2:?}"
    echo -e "${output:?}" | grep "document.cookie=\"${cookie:?}="  | sed -E 's#^.*"'"${cookie:?}"'=([^;]+);.*$#\1#g'
}

nginx_hg_repo_get_all_tags() {
    hg_repo="${1:?}"

    cookie_output=$(curl --silent --location ${hg_repo:?}/raw-tags)
    tc_cookie=$(grep_cookie "${cookie_output:?}" "tc")
    tce_cookie=$(grep_cookie "${cookie_output:?}" "tce")

    # Only return tags that start with a number.
    curl --silent --location -H "Cookie: tc=${tc_cookie:?}; tce=${tce_cookie:?}" ${hg_repo:?}/raw-tags | cut --delimiter=$'\t' --fields=1 | grep -P '^\d+.*$'
}

nginx_hg_repo_latest_tag() {
    hg_repo="${1:?}"
    tags="$(nginx_hg_repo_get_all_tags ${hg_repo:?})"

    # Strip out any strings that begin with 'v' before identifying the highest semantic version.
    highest_sem_ver_tag=$(echo -e "${tags:?}" | sed -E s'#^v(.*)$#\1#g' | sed '/-/!{s/$/_/}' | sort --version-sort | sed 's/_$//'| tail -1)
    # Identify the correct tag for the semantic version of interest.
    echo -e "${tags:?}" | grep "${highest_sem_ver_tag:?}$" | cut --delimiter='/' --fields=3
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
repo_url="https://hg.nginx.org/pkg-oss"
config_key_main="NGINX_VERSION"
config_key_suffix="NGINX_RELEASE_SUFFIX"

existing_upstream_ver_main=$(get_config_arg ${config_key_main:?})
existing_upstream_ver_suffix=$(get_config_arg ${config_key_suffix:?})
existing_upstream_ver="${existing_upstream_ver_main:?}-${existing_upstream_ver_suffix:?}"
latest_upstream_ver=$(nginx_hg_repo_latest_tag ${repo_url:?})

if [[ "${existing_upstream_ver:?}" == "${latest_upstream_ver:?}" ]]; then
    echo "Existing config is already up to date and pointing to the latest upstream ${pkg:?} version '${latest_upstream_ver:?}'"
else
    latest_upstream_ver_main=$(echo ${latest_upstream_ver:?} | cut --delimiter='-' --fields=1)
    latest_upstream_ver_suffix=$(echo ${latest_upstream_ver:?} | cut --delimiter='-' --fields=2)
    echo "Updating ${pkg:?} '${existing_upstream_ver:?}' -> '${latest_upstream_ver:?}'"
    echo "Updating ${config_key_main:?} '${existing_upstream_ver_main:?}' -> '${latest_upstream_ver_main:?}'"
    echo "Updating ${config_key_suffix:?} '${existing_upstream_ver_suffix:?}' -> '${latest_upstream_ver_suffix:?}'"
    set_config_arg "${config_key_main:?}" "${latest_upstream_ver_main:?}"
    set_config_arg "${config_key_suffix:?}" "${latest_upstream_ver_suffix:?}"
fi
