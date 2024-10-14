#!/usr/bin/env bash

# app. Application directory name within ./apps/*
# script. Artillery script name within ./artillery/*
app="${1}"
script="${2}"
logName="${3:-''}"
if [[ -z "$app" ]] || [[ -z "$script" ]]; then
  echo "Usage: monitor-remote.sh <app_name> <script_name>"
  exit 1;
fi

# Redirect stdout (1) and stderr (2) to a file
logFile="logs/${logName}-${app}-${script}.log"
mkdir -p logs
exec > "./${logFile}" 2>&1

# Initialize script constants
baseDir="${PWD}"

# Define helpers
function loadEnv() {
  if [[ -f $1 ]]; then
    # shellcheck disable=SC1090
    source "${1}"
    while read -r line; do
      eval "export ${line}"
    done <"$1"
  fi
}

function formatToEnv() {
  local str="${1}"
  str=$(echo ${str} | sed -r -- 's/ /_/g')
  str=$(echo ${str} | sed -r -- 's/\./_/g')
  str=$(echo ${str} | sed -r -- 's/\-/_/g')
  str=$(echo ${str} | tr -d "[@^\\\/<>\"'=]" | tr -d '*')
  str=$(echo ${str} | sed -r -- 's/\//_/g')
  str=$(echo ${str} | sed -r -- 's/,/_/g')
  str=$(echo ${str} | sed 'y/abcdefghijklmnopqrstuvwxyz/ABCDEFGHIJKLMNOPQRSTUVWXYZ/')
  echo "${str}"
}

function getMongoUrl() {
  echo "$(eval "echo \${MONGO_URL_$(formatToEnv ${app})}")"
}

function getRemoteUrl() {
  echo "$(eval "echo \${REMOTE_URL_$(formatToEnv ${app})}")"
}

function isRunningUrl() {
  local url="${1}"
  local urlStatus="$(curl -Is "${url}" | head -1)"
  echo "${urlStatus}" | grep -q "200"
}

# Ensure proper cleanup on interrupt the process
function cleanup() {
    verify="${1}"

    # Verify valid output
    if [[ "${verify}" == "true" ]]; then
      sleep 6
      if cat "${baseDir}/${logFile}" | grep -q "Timeout"; then
        echo -e "${RED}*** !!! ERROR: SOMETHING WENT WRONG !!! ***${NC}"
        echo -e "${RED}Output triggered an unexpected timeout (${logFile})${NC}"
        echo -e "${RED} Galaxy container is overloaded and unable to provide accurate comparison results.${NC}"
        echo -e "${RED} Try switching to a configuration that Galaxy container can handle.${NC}"

        exit 1
      else
        echo -e "${GREEN}Output is suitable for comparisons (${logFile})${NC}"
        echo -e "${GREEN} Galaxy container managed the configuration correctly.${NC}"

        exit 0
      fi
    fi

    builtin cd ${baseDir};
    # Kill all background processes
    pkill -P $$
    exit 0
}
trap cleanup SIGINT SIGTERM

loadEnv "${baseDir}/.env.prod"

mongoUrl="$(getMongoUrl)"
if [[ -z "${mongoUrl}" ]] || [[ -z "${MONGO_VERSION}" ]]; then
  echo "No Mongo URL and/or version provided in \${MONGO_URL_$(formatToEnv ${app})}"
  echo ""
  exit 1;
fi

export REMOTE_URL="$(getRemoteUrl)"
if [[ -z "${REMOTE_URL}" ]]; then
  echo "No remote URL provided in \${REMOTE_URL_$(formatToEnv ${app})}"
  exit 1;
fi

# Cleaning the collection from production first
npx m mongo "${MONGO_VERSION}" "${mongoUrl}" --ssl --sslAllowInvalidCertificates <<EOF
db.getCollectionNames().forEach(function(collectionName) {
   db[collectionName].deleteMany({});
});
EOF

if ! isRunningUrl "${REMOTE_URL}"; then
  echo "No app running at ${REMOTE_URL}"
  exit 1;
fi

# Run artillery script
npx artillery run --target "${REMOTE_URL}" "${baseDir}/artillery/${script}" &
artPid="$!"

# Wait for artillery script to finish the process
wait "${artPid}"

cleanup "true"
