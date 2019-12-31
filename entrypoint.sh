#!/bin/sh
set -e

function main() {
  echo "" # see https://github.com/actions/toolkit/issues/168

  sanitize "${INPUT_NAME}" "name"
  sanitize "${INPUT_USERNAME}" "username"
  sanitize "${INPUT_PASSWORD}" "password"

  REGISTRY_NO_PROTOCOL=$(echo "${INPUT_REGISTRY}" | sed -e 's/^https:\/\///g')
  if uses "${INPUT_REGISTRY}" && ! isPartOfTheName "${REGISTRY_NO_PROTOCOL}"; then
    INPUT_NAME="${REGISTRY_NO_PROTOCOL}/${INPUT_NAME}"
  fi

  translateDockerTag
  DOCKERNAME="${INPUT_NAME}:${TAG}"

  if uses "${INPUT_WORKDIR}"; then
    changeWorkingDirectory
  fi

  echo ${INPUT_PASSWORD} | docker login -u ${INPUT_USERNAME} --password-stdin ${INPUT_REGISTRY}

  BUILDPARAMS=""
  CONTEXT="."

  if uses "${INPUT_DOCKERFILE}"; then
    useCustomDockerfile
  fi
  if uses "${INPUT_BUILDARGS}"; then
    addBuildArgs
  fi
  if uses "${INPUT_CONTEXT}"; then
    CONTEXT="${INPUT_CONTEXT}"
  fi
  if usesBoolean "${INPUT_CACHE}"; then
    useBuildCache
  fi

  if usesBoolean "${INPUT_SNAPSHOT}"; then
    pushWithSnapshot
  else
    pushWithoutSnapshot
  fi
  echo "::set-output name=tag::${TAG}"
  DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' ${DOCKERNAME})
  echo "::set-output name=digest::${DIGEST}"

  docker logout
}

function sanitize() {
  if [ -z "${1}" ]; then
    >&2 echo "Unable to find the ${2}. Did you set with.${2}?"
    exit 1
  fi
}

function isPartOfTheName() {
  [ $(echo "${INPUT_NAME}" | sed -e "s/${1}//g") != "${INPUT_NAME}" ]
}

function translateDockerTag() {
  local BRANCH=$(echo ${GITHUB_REF} | sed -e "s/refs\/heads\///g" | sed -e "s/\//-/g")
  if hasCustomTag; then
    TAG=$(echo ${INPUT_NAME} | cut -d':' -f2)
    INPUT_NAME=$(echo ${INPUT_NAME} | cut -d':' -f1)
  elif isOnMaster; then
    TAG="latest"
  elif isGitTag && usesBoolean "${INPUT_TAG_NAMES}"; then
    TAG=$(echo ${GITHUB_REF} | sed -e "s/refs\/tags\///g")
  elif isGitTag; then
    TAG="${BRANCH}"
  elif isPullRequest; then
    TAG="${GITHUB_SHA}"
  else
    TAG="${BRANCH}"
  fi;
}

function hasCustomTag() {
  [ $(echo "${INPUT_NAME}" | sed -e "s/://g") != "${INPUT_NAME}" ]
}

function isOnMaster() {
  [ "${BRANCH}" = "master" ]
}

function isGitTag() {
  [ $(echo "${GITHUB_REF}" | sed -e "s/refs\/tags\///g") != "${GITHUB_REF}" ]
}

function isPullRequest() {
  [ $(echo "${GITHUB_REF}" | sed -e "s/refs\/pull\///g") != "${GITHUB_REF}" ]
}

function changeWorkingDirectory() {
  cd "${INPUT_WORKDIR}"
}

function useCustomDockerfile() {
  BUILDPARAMS="${BUILDPARAMS} -f ${INPUT_DOCKERFILE}"
}

function addBuildArgs() {
  for ARG in $(echo "${INPUT_BUILDARGS}" | tr ',' '\n'); do
    BUILDPARAMS="${BUILDPARAMS} --build-arg ${ARG}"
    echo "::add-mask::${ARG}"
  done
}

function useBuildCache() {
  if docker pull ${DOCKERNAME} 2>/dev/null; then
    BUILDPARAMS="$BUILDPARAMS --cache-from ${DOCKERNAME}"
  fi
}

function uses() {
  [ ! -z "${1}" ]
}

function usesBoolean() {
  [ ! -z "${1}" ] && [ "${1}" = "true" ]
}

function pushWithSnapshot() {
  local LAST_TAG=$(echo ${GITHUB_REF} | sed -e "s/refs\/heads\///g" | sed -e "s/refs\/tags\///g")
  local LAST_VER=$(git describe --tags $(git rev-list --tags --max-count=1))
  local COMMITS_AHEAD=$(git rev-list ${LAST_VER}.. --count)
  local IMAGE_TAG1="${LAST_TAG}" 
  local IMAGE_TAG2="${LAST_TAG}-${LAST_VER}.${COMMITS_AHEAD}"
  if COMMITS_AHEAD="0"; then
    docker build ${INPUT_BUILDOPTIONS} ${BUILDPARAMS} -t ${DOCKERNAME} -t ${INPUT_NAME}:${IMAGE_TAG1} ${CONTEXT}
    docker push ${INPUT_NAME}:${IMAGE_TAG1}bolshe
  else
    docker build ${INPUT_BUILDOPTIONS} ${BUILDPARAMS} -t ${INPUT_NAME}:${IMAGE_TAG2} ${CONTEXT}
    docker push ${INPUT_NAME}:${IMAGE_TAG2}
  fi
}
##echo ::set-output name=snapshot-tag::"${SNAPSHOT_TAG}"

function pushWithoutSnapshot() {
  docker build ${INPUT_BUILDOPTIONS} ${BUILDPARAMS} -t ${DOCKERNAME} ${CONTEXT}
  docker push ${DOCKERNAME}
}

main