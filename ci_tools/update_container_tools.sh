#!/bin/bash


read -r -d '' HELP << EOM
This script is used to try fetch the binary information about a release from a github release and update the repo.
You should invoke it as:
./ci_tools/update_container_tools.sh <git tag of tools release>

If you wish to override the github organiztion and repo name you can use:
CI_UPDATE_GITHUB_ORG_AND_REPO_NAME=""

Otherwise these will be determined from the origin url. So if it needs to come from something other than the origin you probably should override these.
EOM

set -efo pipefail


TOOLS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
export REPO_ROOT="$(cd $TOOLS_DIR && cd ..&& pwd)"
cd $REPO_ROOT

RELEASE_TAG="${1:-}"

if [ -z "$RELEASE_TAG" ]; then
    echo -e "\nRelease tag not specified\n\n" 1>&2
    echo $HELP 1>&2
    exit 1
fi


if [ -z "$CI_UPDATE_GITHUB_ORG_AND_REPO_NAME" ]; then
    ORIGIN_URL="$(git config --get remote.origin.url)"
    CI_UPDATE_GITHUB_ORG_AND_REPO_NAME="$(echo $ORIGIN_URL | sed -e 's/.*github\.com:\([A-Za-z0-9_/-]*\)\.git/\1/')"
    if [[ "$CI_UPDATE_GITHUB_ORG_AND_REPO_NAME" =~ ":" ]]; then
        echo "Failed to parse out CI_UPDATE_GITHUB_ORG_AND_REPO_NAME from origin, origin was: $ORIGIN_URL"
        exit 1
    fi
fi


TEMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/tmpupdate.XXXXXXXX")"
trap 'rm -rf "$TEMPDIR"' EXIT

URL_BASE="https://github.com/${CI_UPDATE_GITHUB_ORG_AND_REPO_NAME}/releases/download/${RELEASE_TAG}"
cat repositories/repositories.bzl | sed '/GO_BINARIES_AUTO_GEN_REPLACE_SECTION_START/,$d' > $TEMPDIR/prelude.txt
cat repositories/repositories.bzl | sed '1,/GO_BINARIES_AUTO_GEN_REPLACE_SECTION_END/ d' > $TEMPDIR/suffix.txt

PULLERS="go_puller_linux_amd64:linux-amd64_puller go_puller_linux_arm64:linux-arm64_puller go_puller_linux_s390x:linux-s390x_puller go_puller_darwin:darwin-amd64_puller"
LOADERS="loader_linux_amd64:linux-amd64_loader loader_linux_arm64:linux-arm64_loader loader_linux_s390x:linux-s390x_loader loader_darwin:darwin-amd64_loader"

TMP_OUTPUT=$TEMPDIR/result.bzl

function load_entry() {
    ARG=$1
    repo_name=$(echo $ARG | cut -f1 -d:)
    binary_name=$(echo $ARG | cut -f2 -d:)
    set -x
    SHA256_VALUE="$(curl --fail -L "${URL_BASE}/${binary_name}.sha256")"
cat << EOM >>$TMP_OUTPUT

    if "$repo_name" not in excludes:
        http_file(
            name = "${repo_name}",
            executable = True,
            sha256 = "$SHA256_VALUE",
            urls = ["${URL_BASE}/${binary_name}],
        )
EOM
}

for p in $PULLERS; do
    load_entry $p
done

for p in $LOADERS; do
    load_entry $p
done


cat $TEMPDIR/prelude.txt > repositories/repositories.bzl
echo "    # GO_BINARIES_AUTO_GEN_REPLACE_SECTION_START" >> repositories/repositories.bzl
cat $TEMPDIR/result.bzl >> repositories/repositories.bzl
echo "    # GO_BINARIES_AUTO_GEN_REPLACE_SECTION_END" >> repositories/repositories.bzl
cat $TEMPDIR/suffix.txt >> repositories/repositories.bzl

