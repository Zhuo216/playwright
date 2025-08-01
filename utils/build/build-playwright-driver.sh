#!/usr/bin/env bash
set -e
set -x

trap "cd $(pwd -P)" EXIT
SCRIPT_PATH="$(cd "$(dirname "$0")" ; pwd -P)"
NODE_VERSION="22.17.1" # autogenerated via ./update-playwright-driver-version.mjs

cd "$(dirname "$0")"
PACKAGE_VERSION=$(node -p "require('../../package.json').version")
rm -rf ./output
mkdir -p ./output

echo "Building playwright-core package"
node ../../utils/pack_package.js playwright-core ./output/playwright-core.tgz

echo "Building api.json and protocol.yml"
API_JSON_MODE=1 node ../../utils/doclint/generateApiJson.js > ./output/api.json
cp ../../packages/protocol/src/protocol.yml ./output/

function build {
  NODE_DIR=$1
  SUFFIX=$2
  ARCHIVE=$3
  NODE_URL=https://nodejs.org/dist/v${NODE_VERSION}/${NODE_DIR}.${ARCHIVE}

  echo "Building playwright-${PACKAGE_VERSION}-${SUFFIX}"

  cd ${SCRIPT_PATH}

  mkdir -p ./output/playwright-${SUFFIX}
  tar -xzf ./output/playwright-core.tgz -C ./output/playwright-${SUFFIX}/

  curl --retry 10 --retry-all-errors ${NODE_URL} -o ./output/${NODE_DIR}.${ARCHIVE}
  NPM_PATH=""
  if [[ "${ARCHIVE}" == "zip" ]]; then
    cd ./output
    unzip -q ./${NODE_DIR}.zip
    cd ..
    cp ./output/${NODE_DIR}/node.exe ./output/playwright-${SUFFIX}/
    NPM_PATH="node_modules/npm/bin/npm-cli.js"
  elif [[ "${ARCHIVE}" == "tar.gz" ]]; then
    tar -xzf ./output/${NODE_DIR}.tar.gz -C ./output/
    cp ./output/${NODE_DIR}/bin/node ./output/playwright-${SUFFIX}/
    NPM_PATH="lib/node_modules/npm/bin/npm-cli.js"
  else
    echo "Unsupported ARCHIVE ${ARCHIVE}"
    exit 1
  fi

  cp ./output/${NODE_DIR}/LICENSE ./output/playwright-${SUFFIX}/
  cp ./output/api.json ./output/playwright-${SUFFIX}/package/
  cp ./output/protocol.yml ./output/playwright-${SUFFIX}/package/
  cd ./output/playwright-${SUFFIX}/package
  PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 node "../../${NODE_DIR}/${NPM_PATH}" install --omit=dev --ignore-scripts
  rm package-lock.json

  cd ..

  # NPM install does intentionally set the modification date back to 1985 for all the files. This confuses language binding
  # update mechanisms, which expect the modification date to be recent to decide which file to override. See:
  # - https://github.com/npm/npm/issues/20439#issuecomment-385121133
  # - https://github.com/microsoft/playwright-dotnet/issues/2069
  find . -type f -exec touch {} +

  zip -q -r ../playwright-${PACKAGE_VERSION}-${SUFFIX}.zip .
}

build "node-v${NODE_VERSION}-darwin-x64" "mac" "tar.gz"
build "node-v${NODE_VERSION}-darwin-arm64" "mac-arm64" "tar.gz"
build "node-v${NODE_VERSION}-linux-x64" "linux" "tar.gz"
build "node-v${NODE_VERSION}-linux-arm64" "linux-arm64" "tar.gz"
build "node-v${NODE_VERSION}-win-x64" "win32_x64" "zip"
build "node-v${NODE_VERSION}-win-arm64" "win32_arm64" "zip"
