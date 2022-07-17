#!/bin/bash

set -eo pipefail

function show_help() {
  cat <<EOF
Function to build, push, and increment the semantic version number based on the provided arguments.
The version is used to tag the Docker image and the git commit.
  – -a app name:

    – common: the base image all apps depend on
    – mail-server
    – website (contains all website pages where database access is required, like /mailbox/, /settings/)
    – website-pages (contains all website pages where database access is not required)
    – rss
    – clicker (script to "click" links in emails)
    – api (HTTP API used by the Angular website)
    – angular-website (modern mobile friendly alternative website)
    – all: all of the above apps, without common, one by one (common needs to be built first, then all
    apps updated to the new common version)

Optional flags:
  – -i RELEASE_TYPE : increment version based on RELEASE_TYPE, which can be major|minor|patch.
  – -b         : build docker image of the app.
  – -p         : push docker image to registry.
  The version to be used is:
   - if -i is used, the incremented version
   - otherwise if the working directory is clean (no modified files):
     the latest version
   - otherwise: 'devel'

Example ./$0 -a mail-server -bpi minor
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
    >&2 echo "ERROR: can only use major or minor or patch as release type!"
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
  APP_NAME="${1}"
  if [[ $AUTOTAG ]]
  then
    local IMAGE_VERSION=$(increment)
    RELEASE_TAG=$(tag_new_version $IMAGE_VERSION)
    echo "Release tag ${RELEASE_TAG} added to HEAD."
  else
    if git diff --quiet
      then
      local IMAGE_VERSION=$(get_latest_version)
      echo "Latest version of $APP_NAME: $IMAGE_VERSION"
    else
      local IMAGE_VERSION=devel
    fi
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
  DOCKER_TAG="${dockerhub_username}/${APP_NAME}.mailnesia.com:${IMAGE_VERSION}"
  echo "Building image: $DOCKER_TAG"
  docker build --file ${APP_NAME}.Dockerfile --tag ${DOCKER_TAG} .
}

function push_image() {
  IMAGE_VERSION="${1}"
  DOCKER_TAG="${dockerhub_username}/${APP_NAME}.mailnesia.com:${IMAGE_VERSION}"
  echo "Pushing image: $DOCKER_TAG"
  docker push ${DOCKER_TAG}
}

# process command line arguments
while getopts a:i:bp flag
do
  case "${flag}" in
    a) APPS=${OPTARG};;
    i) AUTOTAG=${OPTARG};;
    b) BUILD=1;;
    p) PUSH=1;;
  esac
done

if [ -z "$APPS" ]
then
  >&2 echo ERROR: app name was not provided to incrementer script!
  show_help
  exit 1
fi

if [[ $APPS == "all" ]]
then
  main mail-server
  main website
  main website-pages
  main rss
  main clicker
  main api
else
  main $APPS
fi
