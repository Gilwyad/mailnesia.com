#!/bin/bash

set -eo pipefail

function show_help() {
  cat <<EOF
Function to increment the semantic version number based on the provided arguments:
  – -a app name: see README.md - example: common
Optional flags:
  – -i autotag : increment version based on autotag, which can be major|minor|patch.
  – -b         : build docker image of the app. If -i is used, build the incremented version,
                 otherwise the latest one.
  – -p         : push docker image to registry. If -i is used, push the incremented version,
                 otherwise the latest one.

Example ./increment-version.sh -a mail-server -bpi minor
EOF
}

semver_regex='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)-.+$'
dockerhub_username=denokera

function verify_version() {
  local VERSION="${1}"
  [[ $VERSION =~ $semver_regex ]]
}

# return the highest version git tag that matches app_name,
# example: 1.0.0-website.mailnesia.com
function get_latest_tag() {
  git tag -l \*-${APP_NAME}.mailnesia.com --sort=-version:refname | head -1
}

# return the highest version from the git tag that matches app_name,
# example: 1.0.0
function get_latest_version() {
  local LATEST_TAG=$(get_latest_tag)
  [[ $LATEST_TAG =~ $semver_regex || true ]]
  echo ${BASH_REMATCH[1]:-0}.${BASH_REMATCH[2]:-0}.${BASH_REMATCH[3]:-0}
}

# return the incremented version, example: 1.2.3
function increment() {
  local LATEST_TAG=$(get_latest_tag)
  [[ $LATEST_TAG =~ $semver_regex || true ]]
  local MAJOR=${BASH_REMATCH[1]:-0}
  local MINOR=${BASH_REMATCH[2]:-0}
  local PATCH=${BASH_REMATCH[3]:-0}
  local IMAGE_VERSION=""

  shopt -s nocasematch
  if [[ $AUTOTAG == "major" ]]
  then
    IMAGE_VERSION="$((MAJOR+1)).0.0"
  elif [[ $AUTOTAG == "minor" ]]; then
    IMAGE_VERSION="${MAJOR}.$((MINOR+1)).0"
  elif [[ $AUTOTAG == "patch" ]]; then
    IMAGE_VERSION="${MAJOR}.${MINOR}.$((PATCH+1))"
  else
    >&2 echo "ERROR: can only use major or minor or patch as autotag!"
    exit 1
  fi


  echo ${IMAGE_VERSION}
}

# set & return the git tag as: image_version-app_name.mailnesia.com,
# example: 1.2.3-common.mailnesia.com
function tag_new_version() {
  local VERSION="${1}"
  local IMAGE_VERSION="${IMAGE_VERSION}-${APP_NAME}.mailnesia.com"
  if ! verify_version $IMAGE_VERSION
  then
    >&2 echo "ERROR: image version $IMAGE_VERSION is not a valid app version!"
    exit 1
  fi
  git tag --annotate --message="Version ${VERSION} for Mailnesia app ${APP_NAME}" $IMAGE_VERSION

  echo $IMAGE_VERSION
}


function main() {
  if [ -z "$APP_NAME" ]
  then
    >&2 echo ERROR: app name was not provided to incrementer script!
    show_help
    exit 1
  fi
  if [[ $AUTOTAG ]]
  then
    local IMAGE_VERSION=$(increment)
    RELEASE_TAG=$(tag_new_version $IMAGE_VERSION)
    echo "Release tag ${RELEASE_TAG} added to HEAD."
  else
    local IMAGE_VERSION=$(get_latest_version)
    echo "Latest version of $APP_NAME: $IMAGE_VERSION"
  fi

  if [[ $BUILD ]]
  then
    build_image $IMAGE_VERSION
  fi

  if [[ $PUSH ]]
  then
    push_image $IMAGE_VERSION
  fi
}


function build_image() {
  IMAGE_VERSION="${1}"
  docker build --file ${APP_NAME}.Dockerfile --tag ${APP_NAME}.mailnesia.com:${IMAGE_VERSION} --tag ${dockerhub_username}/${APP_NAME}.mailnesia.com:${IMAGE_VERSION} .
}

function push_image() {
  IMAGE_VERSION="${1}"
  docker push ${dockerhub_username}/${APP_NAME}.mailnesia.com:${IMAGE_VERSION}
}

# process command line arguments
while getopts a:i:bp flag
do
    case "${flag}" in
        a) APP_NAME=${OPTARG};;
        i) AUTOTAG=${OPTARG};;
        b) BUILD=1;;
        p) PUSH=1;;
    esac
done

main
