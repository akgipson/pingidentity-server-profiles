#!/usr/bin/env sh

${VERBOSE} && set -x

# Set PATH - since this is executed from within the server process, it may not have all we need on the path
export PATH="${PATH}:${SERVER_ROOT_DIR}/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${JAVA_HOME}/bin"

if test -f "${STAGING_DIR}/artifacts/artifact-list.json"; then
  # Check to see if the artifact file is empty
  ARTIFACT_LIST_JSON=$(cat "${STAGING_DIR}/artifacts/artifact-list.json")
  # Check to see if the source S3 bucket(s) are specified
  if test ! -z "${ARTIFACT_LIST_JSON}"; then
    if test ! -z "${ARTIFACT_REPO_URL}" -o ! -z "${PRIVATE_REPO_URL}"; then

      echo "Public Repo  : ${ARTIFACT_REPO_URL}"
      echo "Private Repo : ${PRIVATE_REPO_URL}"

      if ! which jq > /dev/null; then
        echo "Installing jq"
        pip3 install --no-cache-dir --upgrade jq
      fi

      # Check to see if the artifact list is a valid json string
      echo ${ARTIFACT_LIST_JSON} | jq
      if test $(echo $?) == "0"; then
        if ! which unzip > /dev/null; then
          echo "Installing unzip"
          pip3 install --no-cache-dir --upgrade unzip
        fi

        # Install AWS CLI if the upload location is S3
        if test ! "${ARTIFACT_REPO_URL#s3}" == "${ARTIFACT_REPO_URL}" -o ! "${PRIVATE_REPO_URL#s3}" == "${PRIVATE_REPO_URL}"; then
          echo "Installing AWS CLI"
          apk --update add python3
          pip3 install --no-cache-dir --upgrade pip
          pip3 install --no-cache-dir --upgrade awscli
        fi

        DOWNLOAD_DIR=$(mktemp -d)
        DIRECTORY_NAME=$(echo ${PING_PRODUCT} | tr '[:upper:]' '[:lower:]')

        PUBLIC_BASE_URL="${ARTIFACT_REPO_URL}"
        if test ! -z "${ARTIFACT_REPO_URL}"; then
          if ! test -z "${ARTIFACT_REPO_URL##*/pingfederate*}"; then
            PUBLIC_BASE_URL="${ARTIFACT_REPO_URL}/${DIRECTORY_NAME}"
          fi
        fi

        PRIVATE_BASE_URL="${PRIVATE_REPO_URL}"
        if test ! -z "${PRIVATE_REPO_URL}"; then
          if ! test -z "${PRIVATE_REPO_URL##*/pingfederate*}"; then
            PRIVATE_BASE_URL="${PRIVATE_REPO_URL}/${DIRECTORY_NAME}"
          fi
        fi

        for artifact in $(echo "${ARTIFACT_LIST_JSON}" | jq -c '.[]'); do
          _artifact() {
            echo ${artifact} | jq -r ${1}
          }

          ARTIFACT_NAME=$(_artifact '.name')
          ARTIFACT_VERSION=$(_artifact '.version')
          ARTIFACT_SOURCE=$(_artifact '.source')
          ARTIFACT_RUNTIME_ZIP=${ARTIFACT_NAME}-${ARTIFACT_VERSION}-runtime.zip

          # Make sure there aren't any duplicate entries for the artifact.
          # This is needed to avoid issues with multiple plugin versions
          ARTIFACT_NAME_COUNT=$(echo "${ARTIFACT_LIST_JSON}" | grep -iEo "${ARTIFACT_NAME}" | wc -l | xargs)

          if test "${ARTIFACT_NAME_COUNT}" == "1"; then

            # Get artifact source location
            if test "${ARTIFACT_SOURCE}" == "private"; then
              ARTIFACT_LOCATION=${PRIVATE_BASE_URL}/${ARTIFACT_NAME}/${ARTIFACT_VERSION}/${ARTIFACT_RUNTIME_ZIP}
            else
              ARTIFACT_LOCATION=${PUBLIC_BASE_URL}/${ARTIFACT_NAME}/${ARTIFACT_VERSION}/${ARTIFACT_RUNTIME_ZIP}
            fi

            echo "Download Artifact from ${ARTIFACT_LOCATION}"

            # Use aws command if ARTIFACT_REPO_URL is in s3 format otherwise use curl
            if ! test ${ARTIFACT_LOCATION#s3} == "${ARTIFACT_LOCATION}"; then
              aws s3 cp "${ARTIFACT_LOCATION}" ${DOWNLOAD_DIR}
            else
              curl "${ARTIFACT_LOCATION}" --output ${DOWNLOAD_DIR}/${ARTIFACT_RUNTIME_ZIP}
            fi

            if test $(echo $?) == "0"; then
              if ! unzip -o ${DOWNLOAD_DIR}/${ARTIFACT_RUNTIME_ZIP} "deploy/*" -d ${OUT_DIR}/instance/server/default
              then
                  echo Artifact ${DOWNLOAD_DIR}/${ARTIFACT_RUNTIME_ZIP}/deploy could not be unzipped.
              fi
               if ! unzip -o ${DOWNLOAD_DIR}/${ARTIFACT_RUNTIME_ZIP} "conf/*" -d ${OUT_DIR}/instance/server/default
              then
                  echo Artifact ${DOWNLOAD_DIR}/${ARTIFACT_RUNTIME_ZIP}/conf could not be unzipped.
              fi
            else
              echo "Artifact download failed from ${ARTIFACT_LOCATION}"
            fi

            # Cleanup
            if test -f "${DOWNLOAD_DIR}/${ARTIFACT_RUNTIME_ZIP}"; then
              rm ${DOWNLOAD_DIR}/${ARTIFACT_RUNTIME_ZIP}
            fi
          else
            echo "Artifact ${ARTIFACT_NAME} is specified more than once in ${STAGING_DIR}/artifacts/artifact-list.json"
          fi


        done

        # Print listed files from deploy and conf
        ls ${OUT_DIR}/instance/server/default/deploy
        ls ${OUT_DIR}/instance/server/default/conf/template
        ls ${OUT_DIR}/instance/server/default/conf/language-packs

      else
        echo "Artifacts will not be deployed as could not parse ${STAGING_DIR}/artifacts/artifact-list.json."
        exit 0
      fi
    else
      echo "Artifacts will not be deployed as the environment variable ARTIFACT_REPO_URL and PRIVATE_REPO_URL are empty."
      exit 0
    fi
  else
    echo "Artifacts will not be deployed as ${STAGING_DIR}/artifacts/artifact-list.json is empty."
    exit 0
  fi
else
  echo "Artifacts will not be deployed as ${STAGING_DIR}/artifacts/artifact-list.json doesn't exist."
  exit 0
fi