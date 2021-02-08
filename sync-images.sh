#!/bin/bash
set -eo pipefail

REGISTRY_DOMAIN=$1
: ${REGISTRY_DOMAIN:="registry.local"}
REGISTRY_LIBRARY="${REGISTRY_DOMAIN}/library"

NEW_TAG=$(date +"%Y%m%d%H")
TMP_DIR="/tmp/docker-library"
ORIGIN_REPO="https://github.com/muzi502/official-images"
UPSTREAM="https://github.com/docker-library/official-images"
SCRIPTS_PATH=$(cd $(dirname "${BASH_SOURCE}") && pwd -P)
SKIPE_IMAGES="windowsservercore"

cd ${SCRIPTS_PATH}
mkdir -p ${TMP_DIR}

diff_images() {
    git remote remove upstream || true
    git remote add upstream ${UPSTREAM}
    git fetch upstream
    git rebase upstream/master
    PRE_TAG=$(git tag -l | egrep --only-matching -E '^([[:digit:]]{12})' | sort -nr | head -n1) || true
    PRE_TAG=${PRE_TAG:="3724fb6ed"}
    IMAGES=$(git diff --name-only --ignore-space-at-eol --ignore-space-change \
    --diff-filter=AM ${PRE_TAG} library | xargs -L1 -I {} sed "s|^|{}:|g" {} \
    | sed -n "s| ||g;s|library/||g;s|:Tags:|:|p;s|:SharedTags:|:|p" | sort -n | grep -Ev "${SKIPE_IMAGES}")
}

skopeo_copy() {
    if skopeo copy --insecure-policy --src-tls-verify=false --dest-tls-verify=false -q docker://$1 docker://$2; then
        echo "Sync $1 to $2 successfully" 
        echo ${name}:${tags} >> ${TMP_DIR}/${NEW_TAG}-successful.list
        return 0
    else
        echo "Sync $1 to $2 failed" 
        echo ${name}:${tags} >> ${TMP_DIR}/${NEW_TAG}-failed.list
        return 1
    fi
}

sync_images() {
    IFS=$'\n'
    TOTAL_NUMS=$(echo ${IMAGES} | cut -d ':' -f2 | tr ',' '\n' | wc -l)
    for image in ${IMAGES}; do
        name="$(echo ${image} | cut -d ':' -f1)"
        tags="$(echo ${image} | cut -d ':' -f2 | cut -d ',' -f1)"

        if skopeo_copy docker.io/${name}:${tags} ${REGISTRY_LIBRARY}/${name}:${tags}; then
            for tag in $(echo ${image} | cut -d ':' -f2 | tr ',' '\n'); do
                skopeo_copy ${REGISTRY_LIBRARY}/${name}:${tags} ${REGISTRY_LIBRARY}${name}:${tag}
            done
        fi
    done
    unset IFS
}

diff_images
sync_images
git tag ${NEW_TAG} --force
git push origin --tag --force || true
