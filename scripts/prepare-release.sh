#!/usr/bin/env bash
# Usage:
#   prepare-release.sh
#   prepare-release.sh v0.1.1

set -e -o pipefail

script_parent_dir="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
git_repo_dir="$(realpath "${script_parent_dir:?}/..")"

ARGS_FILE="${git_repo_dir:?}/config/ARGS"

docker_hub_tags() {
    docker_hub_repo="${1:?}"
    case "${docker_hub_repo:?}" in
        */*) :;; # namespace/repository syntax, leave as is
        *) docker_hub_repo="library/${docker_hub_repo:?}";; # bare repository name (docker official image); must convert to namespace/repository syntax
    esac
    auth_url="https://auth.docker.io/token?service=registry.docker.io&scope=repository:${docker_hub_repo:?}:pull"
    token="$(curl -fsSL "${auth_url:?}" | jq --raw-output '.token')"
    tags_url="https://registry-1.docker.io/v2/${docker_hub_repo:?}/tags/list"
    curl -fsSL -H "Accept: application/json" -H "Authorization: Bearer ${token:?}" "${tags_url:?}" | jq --raw-output '.tags[]'
}

docker_hub_latest_tag() {
    docker_hub_tags "$@" | grep -v '^master$' | sort --version-sort --reverse | head -1
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

get_latest_version() {
    arg_prefix="${1:?}"
    repo=$(get_config_arg "${arg_prefix:?}_NAME")
    docker_hub_latest_tag "${repo:?}"
}

update_latest_version() {
    image_arg_prefix="${1:?}"
    ver=$(get_latest_version ${image_arg_prefix:?})
    echo "Updating ${image_arg_prefix:?} -> ${ver:?}"
    set_config_arg "${image_arg_prefix:?}_TAG" "${ver:?}"
}

get_latest_tag() {
    git tag --list | sort --version-sort --reverse | head -1
}

get_next_semantic_ver() {
    echo "${1:?}" | sed -E 's#^v([0-9]+)\.([0-9]+)\.([0-9]+)-.+$#v\1.\2.\3#g' | awk -F. -v OFS=. '{$NF += 1 ; print}'
}

get_package_version() {
    get_config_arg "${1:?}"
}

pkg="Nginx"
tag_pkg="nginx"

if [ -z "$1" ]; then
    # Generate the next semantic version number if version number is not supplied.
    rel_ver="$(get_next_semantic_ver $(get_latest_tag))"
else
    # Use the supplied version number from the command line arg.
    rel_ver="${1:?}"
fi
pkg_ver="$(get_package_version NGINX_VERSION)"

git branch temp-release
git checkout temp-release
update_latest_version BASE_IMAGE
git add ${ARGS_FILE:?}
git commit -m "feat: Prepare for ${rel_ver:?} release based off ${pkg:?} ${pkg_ver:?}."
echo "Creating tag ${rel_ver:?}-${tag_pkg}-${pkg_ver:?}"
git githubtag -m "${rel_ver:?} release based off ${pkg:?} ${pkg_ver:?}." ${rel_ver:?}-${tag_pkg:?}-${pkg_ver:?}
git checkout master
git branch -D temp-release
