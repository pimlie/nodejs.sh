#!/usr/bin/env bash
#
# MIT License
#
# Copyright (c) 2019 pimlie
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
set -e

commandToRun=$(basename "$0")
commandArguments=("$@")

function findProjectRoot {
  declare -n "_rootDir=$1"

  _rootDir="$2"
  while [ ! -e "${_rootDir}/${rcFile}" ] && [ "${_rootDir}" != "/" ]; do
    _rootDir=$(dirname "$_rootDir")
  done
}

function loadSource {
  file=$1

  if [ -e "$file" ]; then
    source "$file"
  fi
}

function setOption {
  declare -n "_opt=$1"
  optname=$2
  optmatch=$3

  envName=${optname^^}
  envName=${envName//-/_}

  declare -n "_envVar=$envName"

  if [ -n "$_envVar" ]; then
    _opt="$_envVar"
  fi

  for i in "${!commandArguments[@]}"; do
    arg=${commandArguments[i]}

    if [ "$arg" = "--${optname}" ]; then
      if [ -z "$optmatch" ]; then
        _opt=1
        unset 'commandArguments[i]'
        break
      fi

      (( k=i+1 ))
      val=${commandArguments[k]}

      if [ "${k:0:1}" != "-" ]; then
        if [[ ! "$val" =~ $optmatch ]]; then
          echo "Error, expected value for ${optname} to match pattern '${optmatch}', received '${val}'"
          exit 1
        fi

        _opt="$val"

        unset 'commandArguments[i]'
        unset 'commandArguments[k]'
        break
      fi
    fi
  done
}

# copyEnvironment
#
# All arguments passed to this function are matched against all environment
# variables, if a match is found the environment variable is copied to
# a key=value string which is returned by echo'ing
function copyEnvironment {
  declare -n "_copiedEnv=$1"
  shift

  # make copyEnv an associative array to prevent duplicates
  declare -A copyEnv
  local IFS=$'\n'

  local regexes=()
  for re in "$@"; do
    if [ -z "$re" ]; then
      continue
    fi

    # convert comma separated list to regex
    if [[ "$re" =~ ^[a-zA-Z0-9_,]+$ ]] && [[ "$re" == *","* ]]; then
      re="^(${re//,/|})$"
    fi

    regexes+=("$re")
  done

  for e in $(env); do
    key=${e%%=*}

    for re in "${regexes[@]}"; do
      # -z is not strictly correct but fine here
      if [[ $key =~ $re ]] && [ -z "${copyEnv[$key]}" ]; then
        copyEnv[$key]="${e#*=}"
      fi
    done
  done

  IFS=' '
  retval=()
  for key in "${!copyEnv[@]}"; do
    retval+=("${key}=\"${copyEnv[$key]}\"")
  done

  _copiedEnv="${retval[*]}"
}

function addVolumes {
  declare -n "_volumes=$1"
  declare -n "_confVolumes=$2"

  if [ -n "${_confVolumes+x}" ] && [ ${#_confVolumes[@]} -gt 0 ]; then
    for volume in "${_confVolumes[@]}"; do
      _volumes+=("--volume=${volume}:${volume}")
    done
  fi
}

function addOpts {
  declare -n "_options=$1"
  declare -n "_confOptions=$2"

  if [ -n "${_confOptions+x}" ] && [ ${#_confOptions[@]} -gt 0 ]; then
    for option in "${_confOptions[@]}"; do
      _options+=("${option}")
    done
  fi
}

# from: https://stackoverflow.com/questions/3685970/check-if-a-bash-array-contains-a-value
function containsElement {
  local e match="$1"
  shift
  for e; do [[ "$e" == "$match" ]] && return 0; done
  return 1
}

declare copyEnvVars
declare nodeId
declare nodeVersion
declare nodeUser
declare removeContainer
declare rootDir
declare -a volumes

# Load default settings
loadSource "/etc/nodejs-sh.conf"

# Set default rc file name
rcFile=${rcFile:-.noderc}

# Find root folder of node project
findProjectRoot rootDir "$PWD"

# Load project settings
loadSource "${rootDir}/${rcFile}"

# Set node options
setOption nodeId "node-id" "([^-]+)"
setOption nodeVersion "node-version" "(([0-9]+)(\\.[0-9]+)?(\\.[0-9]+)?)"
setOption nodeUser "node-user" "([^-]+)"
setOption removeContainer "node-remove"
setOption copyEnvVars "copy-env" "([^-]+)"

# Automatically run command as root for global commands
defaultUser="node"
if containsElement "-g" "${commandArguments[@]}" || containsElement "--global" "${commandArguments[@]}"; then
  defaultUser="root"
fi
nodeUser=${nodeUser:-$defaultUser}

# Set default node id if not set
nodeId=${nodeId:-$defaultNodeId}

# Set imageTag to alpine if not set
imageTag=${imageTag-alpine}
if [ -n "$nodeVersion" ]; then
  imageTag="${nodeVersion}-${imageTag}"
fi

# Set container name based on options
containerName="node-${imageTag}"
if [ -n "$nodeId" ]; then
  containerName="${containerName}-${nodeId}"
fi

# Remove container first if requested so we create a new one
if [ -n "$removeContainer" ]; then
  docker stop "$containerName" >/dev/null 2>&1
  docker rm "$containerName" >/dev/null 2>&1
fi

# Create container when the name doesnt exists
status="$(docker ps -af "name=^${containerName}$" --format "{{.Status}}")"
if [ -z "${status}" ]; then
  declare -a vols
  addVolumes vols "volumes"
  addVolumes vols "volumes_${nodeId}"

  declare -a opts
  addOpts opts "dockerOptions"
  addOpts opts "dockerOptions_${nodeId}"

  docker run -it -d --net host "--name=${containerName}" "${vols[@]}" "${opts[@]}" "node${imageTag:+:$imageTag}" /bin/sh -c 'touch /var/log/node.log && tail -f /var/log/node.log'

# Resume the container if its paused
elif [[ $status == "Up "*"(Paused)" ]]; then
  docker unpause "$containerName"

# Start the container if it was stopped
elif [[ $status != "Up "* ]]; then
  docker start "$containerName"
fi

# Trap signals so we can kill the node process in the running container
KILLED=0
trap 'KILLED=1' TERM INT

# This is used to keep track of commands started by this script
SCRIPT_PID=$$

# Determine which ENV variables we need to copy, always copy NODE_* vars
declare copiedEnv
copyEnvironment copiedEnv "^(NODE_.*)$" "$copyEnvVars"

# Escape the command arguments
commandArgs=""
for arg in "${commandArguments[@]}"; do
  commandArgs="${commandArgs} \"${arg}\""
done

# Run the requested command in the container
docker exec --user "${nodeUser}" -it -w "$PWD" "${containerName}" /bin/sh -ic "__SCRIPT_PID=$SCRIPT_PID $copiedEnv $commandToRun $commandArgs"

# Find the pid on the host for the started command
EXEC_PID=$(pgrep -f "__SCRIPT_PID=$SCRIPT_PID")

# Wait until the command has finished
while [ $KILLED -eq 0 ] && [ -n "$EXEC_PID" ] && [ -n "$(ps -p "$EXEC_PID" -o pid=)" ]; do
  sleep 1
done

# If this bash process was killed, also kill the node process (tree) within the container
if [ $KILLED -eq 1 ]; then
  docker exec --user "${nodeUser}" "${containerName}" /bin/sh -c 'pgrep -f "__SCRIPT_PID='$SCRIPT_PID'" | xargs ps --forest -o pid= -g | xargs kill'
fi

