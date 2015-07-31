#!/bin/bash
############################################################
# Run pkgcloud functions tests against an HP public cloud
#
# Steps: -
#   1. Build test environment
#   1.1. Clone pkgcloud repository
#   1.2. Clone pkgcloud-integration-tests repository
#   1.3. Change to 'pkgcloud-integration-tests' folder
#   1.4. Run npm install and npm link (to pkgcloud)
#   2. Run configurations
#   2.1. Create config file (if not existing)
#   2.2. Use config to get test args from a public cloud account
#   3. Run customized tests
#
# See repos -
#     https://github.com/pkgcloud/pkgcloud-integration-tests
#     https://github.com/pkgcloud/pkgcloud
############################################################

count=0
countSuccess=0
script_args=$@

# build up test environment
buildTest() {
  echo ""
  echo `date +"%Y-%m-%d %H:%M:%S"` "(1). Build test environment"
  echo "============================================================"
  # get number of colors of the console
  colors_tput=`tput colors`
  # get full path to this script itself
  script_file="${BASH_SOURCE[0]##*/}"
  script_path="$( cd "$( echo "${BASH_SOURCE[0]%/*}" )" && pwd )"
  pkg_test="pkgcloud-integration-tests"
  devex=`[[ "$(dirname ${script_path})" =~ (devex-tools/aft) ]] && echo "true"`

  # pkgcloud and test repositories
  repo_pkgcloud="https://github.com/pkgcloud/pkgcloud.git"
  repo_pkgcloud_fork="https://github.com/jasonzhuyx/pkgcloud.git"
  repo_pkgcloud_test="https://github.com/pkgcloud/${pkg_test}.git"
  repo_pkgcloud_test_fork="https://github.com/jasonzhuyx/${pkg_test}.git"

  if [[ "$PWD" != "${script_path}" ]]; then
    echo "PWD= $PWD"
    echo `date +"%Y-%m-%d %H:%M:%S"` "Change to ${script_path}"
    cd "${script_path}"
  fi

  echo "PWD= $PWD"

  # clone repository for devex-tools environment
  if [[ "${devex}" != "" ]]; then
    echo ""
    echo `date +"%Y-%m-%d %H:%M:%S"` "Cleaning up test environment ..."
    rm -rf "pkgcloud"
    rm -rf "pkgcloud-integration-tests"

    echo ""
    echo `date +"%Y-%m-%d %H:%M:%S"` "Cloning pkgcloud repository ..."
    echo "------------------------------------------------------------"
    git clone "${repo_pkgcloud_fork}"
    echo ""
    echo `date +"%Y-%m-%d %H:%M:%S"` "Cloning test repository ..."
    echo "------------------------------------------------------------"
    git clone "${repo_pkgcloud_test_fork}"

    # 2. create npm link and change to the test folder
    #    cd pkgcloud
    #		 npm link
    #    cd ../pkgcloud-integration-tests
    #		 npm install
    #		 npm link pkgcloud
    #		 pwd
    echo ""
    echo `date +"%Y-%m-%d %H:%M:%S"` "Installing pkgcloud and tests ..."
    echo "------------------------------------------------------------"
    rm -rf "${script_path}/npm"
    mkdir -p "${script_path}/npm/bin"
    export prefix=${script_path}/npm
    export PATH=${script_path}/npm/bin:$PATH
  fi

  # build pkgcloud test environment
  if [[ -e "pkgcloud" ]] && [[ -e "${pkg_test}" ]] ; then
    echo ""
    echo `date +"%Y-%m-%d %H:%M:%S"` "Creating npm link ..."
    echo "------------------------------------------------------------"
    cd pkgcloud
    npm link
    echo ""
    echo `date +"%Y-%m-%d %H:%M:%S"` "Change to ${pkg_test}"
    echo "------------------------------------------------------------"
    cd "../${pkg_test}"
    npm install
    echo ""
    echo `date +"%Y-%m-%d %H:%M:%S"` "Link to pkgcloud ..."
    echo "------------------------------------------------------------"
    npm link pkgcloud
    echo ""
  elif [[ "$(basename $PWD)" != "${pkg_test}" ]] && [[ -e "${pkg_test}" ]]; then
    echo "PWD= $PWD"
    cd "${pkg_test}"
  fi

  echo ""
  if [[ "$(basename $PWD)" == "${pkg_test}" ]]; then
    configArgs ${script_args}
  else
    echo "PWD= $PWD"
    echo "Abort: Cannot find ${pkg_test}"
    echo ""
    exit 1
  fi
}

# initialize global configuration and settings (only run once for all tests)
configArgs() {
  provider=hp
  echo ""
  echo `date +"%Y-%m-%d %H:%M:%S"` "(2). Start configuration"
  echo "============================================================"
  echo "PWD= $PWD"

  if [[ "${OS_USERNAME}" == "" ]]; then
    OS_USERNAME="Platform-AddIn-QA"
  fi
  if [[ "${OS_PASSWORD}" == "" ]]; then
    OS_PASSWORD="Helion123!"
  fi
  if [[ "${OS_AUTH_URL}" == "" ]]; then
    OS_AUTH_URL="https://region-a.geo-1.identity.hpcloudsvc.com:35357/"
  fi
  if [[ "${OS_AUTH_URL}" =~ (https://(region.+)\.identity\.hpcloudsvc\.com) ]]; then
    OS_REGION=${BASH_REMATCH[2]}
  elif [[ "${OS_REGION}" == "" ]]; then
    OS_REGION="region-a.geo-1"
  fi

  # settings for public cloud account
  config_key="${provider}"
  username="${OS_USERNAME}"
  password="${OS_PASSWORD}"
  auth_url="${OS_AUTH_URL}"
  region="${OS_REGION}"

  config_path="$PWD/config"
  config_filename="${config_path}/${config_key}.config.json"
  public_keyfile=`ls ~/.ssh/id_rsa.pub`

  # check if there is config file specified
  configArgsFromConfigFile ${script_args}

  # configure test args against public cloud account
  configArgsForTests

  echo "------------------------------------------------------------"
  echo ""
}

# read config file, if it is provided from command line argument $1
configArgsFromConfigFile() {
  # check if command line provides a config file
  if [[ "$1" != "" ]]; then
    echo `date +"%Y-%m-%d %H:%M:%S"` "Searching ${config_path}/$1* ..."
    for file in ${config_path}/$1*.config.json; do
      local readConfigKeyOkay=""
      if [[ -e "${file}" ]]; then
        local filename=$(basename "${file}")
        local conf_key=${filename/.config.json/}
        echo `date +"%Y-%m-%d %H:%M:%S"` "Checking ${filename} ..."
        while read -r line; do
          if [[ "${line}" =~ (\"$conf_key\":) ]]; then
            echo `date +"%Y-%m-%d %H:%M:%S"` "Loading $conf_key ..."
            config_key="$conf_key"
            config_filename="${config_path}/${config_key}.config.json"
            readConfigKeyOkay=true
          elif [[ "${readConfigKeyOkay}" == "true" ]]; then
            if [[ "${line}" =~ (\"provider\"[ ]*:[ ]*\"(.+)\") ]]; then
              echo "---- provider: ${BASH_REMATCH[2]}"
              provider="${BASH_REMATCH[2]}"
            fi
            if [[ "${line}" =~ (\"username\"[ ]*:[ ]*\"(.+)\") ]]; then
              echo "---- username: ${BASH_REMATCH[2]}"
              username="${BASH_REMATCH[2]}"
            fi
            if [[ "${line}" =~ (\"region\"[ ]*:[ ]*\"(.+)\") ]]; then
              echo "------ region: ${BASH_REMATCH[2]}"
              region="${BASH_REMATCH[2]}"
            fi
          fi
        done < ${file}
        if [[ "${readConfigKeyOkay}" == "true" ]]; then
          echo `date +"%Y-%m-%d %H:%M:%S"` "Loaded $conf_key ..."
          break
        fi
      fi
    done
  else
    echo `date +"%Y-%m-%d %H:%M:%S"` "Checking ${config_filename} ..."
  fi

  # create default config file if it is not existing
  if [[ ! -e "${config_filename}" ]]; then
    echo `date +"%Y-%m-%d %H:%M:%S"` "Create default configuration:"
    cat >${config_filename} <<!
{
  "${username}": {
    "username": "${username}",
    "password": "${password}",
    "provider": "${provider}",
    "authUrl": "${auth_url}",
    "region": "${region}"
  }
}
!
  fi

  # print configuation summary
  echo "------------------------------------------------------------"
  cat ${config_filename}
  echo "------------------------------------------------------------"
  echo ""
  echo `date +"%Y-%m-%d %H:%M:%S"` "Using configuration:"
  echo "------ config: ${config_key}.config.json"
  echo "---- provider: ${provider}"
  echo "---- username: ${username}"
  echo "------ region: ${region}"
  echo ""
}

# configure test args per public cloud account
configArgsForTests() {
  echo `date +"%Y-%m-%d %H:%M:%S"` Configuring tests args ...

  keyName="hpcloud"
  newKeyName="newKeyName"
  newName="newTest"
  # flavor_id -
  #   100-105 standard.xsmall, .small, .medium, .large, .xlarge, .2xlarge
  #   110 standard.4xlarge
  #   114 standard.8xlarge
  #   203-205 highmem.large, .xlarge, .2xlarge
  flavorId=101

  parseOutput_ModuleTest_getFlavors "standard.xlarge"
  parseOutput_ModuleTest_getServers
  parseOutput_ModuleTest_getImages

  # default extra argument placeholders for the tests
  addKeyName=${keyName}
  createImageId="128cfaa0-4736-408a-a5c2-df05a5d4a7d"
  createNetworkId="a686df42-2d41-4dd4-8db7-af954bd89bfc"
  createSecurityGroupId="bf7328a2-382b-4b98-a7da-fc78e2ebfd8c"
  createServerId="${serverId}"
}

# build a dynamic mapping dictionary of args to modules (for getArgs func)
configDynamicArgsDict() {
  local xtimes=$1
  local posKey=${xtimes}

  # ::: pre-defined arguments for the compute/ip tests ::: ====================
  # lib/compute/floating-ips/assignIp {serverId} {ip}
  args_assignIp="${createServerId} ${getIpsAvailableIp}"

  # lib/compute/floating-ips/deleteIp {ip}
  args_deleteIp="${addIpId}"

  # lib/compute/floating-ips/removeIp {serverId} {ip}
  args_removeIp="${createServerId} ${getIpsAvailableIp}"

  # ::: pre-defined arguments for the compute/keys tests ::: ====================
  # lib/compute/keys/addKey {keyName} {public_key}
  args_addKey="${newKeyName} ${public_keyfile}"

  # lib/compute/keys/deleteKey {keyName}
  args_deleteKey="${newKeyName}"

  # lib/compute/keys/destroyKey {keyName}
  args_destroyKey="${newKeyName}"

  # lib/compute/keys/getKey {keyName}
  args_getKey="${newKeyName}"

  # ::: pre-defined arguments for the compute tests ::: ====================
  # lib/compute/createImage {newImageName} {serverId}
  local newImage="newImage${posKey}"
  args_createImage="${newImage} ${createServerId}"

  # lib/compute/createImage {newSecurityGroup} {description}
  args_createSecurityGroup="newSecurityGroup newSecurityGroupDescription"

  # lib/compute/createServer {name} {flavor} {image} {keyname} {networkId}
  local newServer="newServer${posKey}"
  args_createServer="${newServer} 104 ${imageId} ${addKeyName} ${createNetworkId}"

  # lib/compute/deleteImage {imageId}
  args_deleteImage="${createImageId}"

  # lib/compute/deleteSecurityGroup {securityGroupId}
  args_deleteSecurityGroup="${createSecurityGroupId}"

  # lib/compute/deleteServer {serverId}
  args_deleteServer="${createServerId}"

  # lib/compute/deleteImage {imageId}
  args_deleteServer="${createServerId}"

  # lib/compute/getImage {imageId}
  args_getImage="${createImageId}"

  # lib/compute/getSecurityGroup {securityGroupId}
  args_getSecurityGroup="${createSecurityGroupId}"

  # lib/compute/getServer {serverId}
  args_getServer="${createServerId}"

  # ::: pre-defined arguments for the network tests ::: ====================
  # lib/network/createNetwork {newNetworkName}
  local newNetwork="newNetwork${posKey}"
  args_createNetwork="${newNetwork}"

  # lib/network/createPort {networkId}
  args_createPort="${createNetworkId}"

  # lib/network/createSubnet {networkId} {cidr} {ip_version}
  args_createSubnet="${createNetworkId} 10.0.0.0/24 4"

  # lib/network/deleteNetwork {networkId}
  args_deleteNetwork="${createNetworkId}"

  # lib/network/deleteNetwork {portId}
  args_deletePort="${createPortId}"

  # lib/network/deleteSubnet {subnetId}
  args_deleteSubnet="${createSubnetId}"

  # lib/network/getNetwork {networkId}
  args_getNetwork="${createNetworkId}"

  # lib/network/getPort {portId}
  args_getPort="${createPortId}"

  # lib/network/getSubnet {subnetId}
  args_getSubnet="${createSubnetId}"

  # lib/network/updateNetwork {networkId} {updatedNetworkName}
  args_updateNetwork="${createNetworkId} updatedNetwork${posKey}"

  # lib/network/updatePort {portId} {updatedPortName}
  args_updatePort="${createPortId} updatedPort${posKey}"

  # lib/network/updateSubnet {subnetId} {updatedSubnetName}
  args_updateSubnet="${createSubnetId} updatedSubnet"

  # ::: pre-defined arguments for the storage tests ::: ====================
  # lib/storage/createContainer {newContainerName}
  args_createContainer="${newName}"

  # lib/storage/deleteContainer {containerName}
  args_deleteContainer="${newName}"

  # lib/storage/deleteContainerRobust {containerName}
  args_deleteContainerRobust="${newName}"

  # lib/storage/getContainer {containerName}
  args_getContainer="${newName}"

  # lib/storage/getCountForContainer {containerName}
  args_getCountForContainer="${newName}"

  # lib/storage/getFile {containerName} {filename}
  args_getFile="${newName} test${xtimes}.json"

  # lib/storage/getFiles {containerName}
  args_getFiles="${newName}"

  # lib/storage/uploadFile {containerName} {newFileName} {source}
  args_uploadFile="${newName} test${xtimes}.json ${config_filename}"

}

# sleep for specific time (e.g. 10s, 5m)
delay() {
  echo `date +"%Y-%m-%d %H:%M:%S"` "Sleeping ${1-1s} ..."
  sleep ${1-1s}
}

# get arguments for a test module
# note: default arguments are ${provider} ${username} ${region} but some tests
#       requires additional arguments after ${provider}
getArgs() {
  local xtimes=${2-1}

  # build a global dynamic dictionary in order to get options for $1 test
  configDynamicArgsDict ${xtimes}

  arg=args_$1
  options="${config_key} ${!arg} ${username} ${region}"
  result="${options/  / }"
  echo "${result}"
}

# parse output from test result and
# get id for create* test if the test succeeded; otherwise
# print output if the test failed (when $2 not specified)
parseOutput() {
  local count_$2=""
  local parse_found="false"
  local IFS_SAVED=$IFS
  IFS='\n'

  while read -r line; do
    # assuming FAIL or Error (if $2 empty), to print output directly
    if [[ "$2" == "" ]]; then
      if [[ "${line}" =~ (error:[ ]*$) ]]; then break; fi
      if [[ "${line}" =~ ((\[31m)?error.?(\[39m)?:[ ]*$) ]]; then break; fi
      if [[ "${line}" =~ (name: (\[32m)?\'Error\'(\[39m)?) ]]; then break; fi
      echo  "${line}"
    # otherwise, for passed test, getting newly created id
    else
      if [[ "$2" == "addKey" ]]; then
        if [[ "${line}" =~ ( name:.+\'(.+)\') ]]; then
          echo "----------- New Key Name: ${BASH_REMATCH[2]}"
          addKeyName="${BASH_REMATCH[2]}"
          break
        fi
      elif [[ "$2" == "addIp" ]]; then
        if [[ "${line}" =~ (ip:.+\'(([0-9]{1,3}\.){3}[0-9]{1,3})\') ]]; then
            echo "----- New Floating IP ==: ${BASH_REMATCH[2]}"
            addIpNewIp="${BASH_REMATCH[2]}"
        fi
        if [[ "${line}" =~ ( id:.+\'([0-9a-z-]{36})\') ]]; then
          echo "----- New Floating IP Id: ${BASH_REMATCH[2]}"
          addIpId="${BASH_REMATCH[2]}"
          break
        fi
      elif [[ "$2" == "createImage" ]]; then
        if [[ "${line}" =~ (images/([0-9a-z]{8}(-[0-9a-z]{4}){3}-[0-9a-z]{12})) ]]; then
          echo "----------- New Image Id: ${BASH_REMATCH[2]}"
          createImageId="${BASH_REMATCH[2]}"
          delay 30s
          break
        fi
      elif [[ "$2" == "createNetwork" ]]; then
      # if [[ "${line}" =~ ([0-9a-z]{8}(-[0-9a-z]{4}){3}-[0-9a-z]{12}) ]]; then
        if [[ "${line}" =~ ( id:.+\'([0-9a-z-]{36})\') ]]; then
          echo "--------- New Network Id: ${BASH_REMATCH[2]}"
          createNetworkId="${BASH_REMATCH[2]}"
          hasDoneCreation_Network=true
          break
        fi
      elif [[ "$2" == "createPort" ]]; then
        if [[ "${line}" =~ ( id:.+\'([0-9a-z-]{36})\') ]]; then
          echo "------------ New Port Id: ${BASH_REMATCH[2]}"
          createPortId="${BASH_REMATCH[2]}"
          break
        fi
      elif [[ "$2" == "createSubnet" ]]; then
        if [[ "${line}" =~ ( id:.+\'([0-9a-z-]{36})\') ]]; then
          echo "------------ New Port Id: ${BASH_REMATCH[2]}"
          createSubnetId="${BASH_REMATCH[2]}"
          break
        fi
      elif [[ "$2" == "createSecurityGroup" ]]; then
        if [[ "${line}" =~ ( id:.+\'([0-9a-z-]{36})\') ]]; then
          echo "-- New Security Group Id: ${BASH_REMATCH[2]}"
          createSecurityGroupId="${BASH_REMATCH[2]}"
          break
        fi
      elif [[ "$2" == "createServer" ]]; then
        if [[ "${line}" =~ ( id:.+\'([0-9a-z-]{36})\') ]]; then
          echo "---------- New Server Id: ${BASH_REMATCH[2]}"
          createServerId="${BASH_REMATCH[2]}"
          break
        fi
      elif [[ "$2" == "deleteNetwork" ]]; then
        hasDoneCreation_Network=false
        break
      elif [[ "$2" == "deletePort" ]]; then
        if [[ "${line}" =~ (ports/([0-9a-z]{8}(-[0-9a-z]{4}){3}-[0-9a-z]{12})) ]]; then
          echo "----------- deleted port: ${BASH_REMATCH[2]}"
          portMatchSubnet=""
          break
        fi
      elif [[ "$2" == "deleteServer" ]]; then
        hasDoneCreation_Server=false
        delay 10s
        break
      elif [[ "$2" == "getFlavors" ]]; then
        if [[ "${line}" =~ ( id:.+\'([0-9]{3})\') ]]; then
          count_getFlavors=$((${count_getFlavors}+1))
          if [[ "${parse_found}" != "true" ]]; then
            activeFalvorId="${BASH_REMATCH[2]}"
          fi
        elif [[ "${count_getFlavors}" != "" ]]; then
          if [[ "${line}" =~ (name:) ]] && \
             [[ "${line}" =~ (name:.+\'${flavorName}\') ]]; then
              echo "----- 1st matched flavor: ${activeFalvorId}"
          fi
        fi
      elif [[ "$2" == "getImages" ]]; then
        if [[ "${line}" =~ ( id:.+\'([0-9a-z-]{36})\') ]]; then
          count_getImages=$((${count_getImages}+1))
          if [[ "${parse_found}" != "true" ]]; then
            activeImageId="${BASH_REMATCH[2]}"
          fi
        elif [[ "${parse_found}" != "true" ]] && \
             [[ "${count_getImages}" != "" ]]; then
          if [[ "${line}" =~ (name:.+\'(.+)\') ]]; then
            activeImageName="${BASH_REMATCH[2]}"
            if [[ "${line}" =~ (deprecated) ]]; then
              activeImageId=""
              activeImageName=""
            fi
          elif [[ "${line}" =~ (status:.+\'ACTIVE\') ]]; then
            echo "---- 1st Active Image Id: ${activeImageId} [${activeImageName}]"
            parse_found="true"
          fi
        fi
      elif [[ "$2" == "getIps" ]]; then
        if [[ "${line}" =~ (instance_id:) ]]; then
          count_getIps="$((${count_getIps}+1))"
          if [[ "${line}" =~ (instance_id:.+(\[1m)?null.?(\[22m)?,) ]]; then
            getIpsAvailable="true"
          fi
        elif [[ "${parse_found}" != "true" ]] && \
             [[ "${getIpsAvailable}" == "true" ]]; then
        # if [[ "${line}" =~ (\'(([0-9]{1,3}\.){3}[0-9]{1,3})'\) ]]; then
          if [[ "${line}" =~ (ip:.+\'(([0-9]{1,3}\.){3}[0-9]{1,3})\') ]]; then
              echo "------- 1st Available IP: ${BASH_REMATCH[2]}"
              getIpsAvailableIp="${BASH_REMATCH[2]}"
              parse_found="true"
          fi
        fi
      elif [[ "$2" == "getPorts" ]]; then
        if [[ "${portMatchSubnet}" == "true" ]]; then
          if [[ "${line}" =~ ( id:.+\'([0-9a-z-]{36})\') ]]; then
            echo "----- associated port id: ${BASH_REMATCH[2]}"
            associatePortId="${BASH_REMATCH[2]}"
            portMatchSubnet=""
            break
          fi
        else
          if [[ "${line}" =~ ( networkId:.+\'([0-9a-z-]{36})\') ]] && \
             [[ "${createNetworkId}" == "${BASH_REMATCH[2]}" ]]; then
              portMatchSubnet="true"
          elif [[ "${line}" =~ ( subnet_id:.+\'([0-9a-z-]{36})\') ]]; then
            if [[ "${createSubnetId}" == "${BASH_REMATCH[2]}" ]]; then
              portMatchSubnet="true"
            fi
          fi
        fi
      elif [[ "$2" == "getServer" ]]; then
        if [[ "${line}" =~ ( id:.+\'([0-9a-z-]{36})\') ]]; then
           if [[ "${createServerId}" == "${BASH_REMATCH[2]}" ]]; then
             createServerStatus="unknown"
           else
             createServerStatus=""
           fi
        fi
        if [[ "${createServerStatus}" == "unknown" ]]; then
          if [[ "${line}" =~ ( name:.+\'(.+)\') ]]; then
              createServerName="${BASH_REMATCH[2]}"
          elif [[ "${line}" =~ ( status:.+\'(.+)\') ]]; then
              echo "------ recent new server: ${createServerId} [${createServerName}]"
              echo "------ get server status: ${BASH_REMATCH[2]}"
              createServerStatus="${BASH_REMATCH[2]}"
              break
          fi
        fi
      elif [[ "$2" == "getServers" ]]; then
        if [[ "${line}" =~ ( id:.+\'([0-9a-z-]{36})\') ]]; then
          count_getServers="$((${count_getServers}+1))"
          if [[ "${parse_found}" != "true" ]]; then
            activeServerId="${BASH_REMATCH[2]}"
          fi
        elif [[ "${parse_found}" != "true" ]] && \
             [[ "${count_getServers}" != "" ]]; then
          if [[ "${line}" =~ (name:.+\'(.+)\') ]]; then
            activeServerName="${BASH_REMATCH[2]}"
          elif [[ "${line}" =~ (status:) ]]; then
            if [[ "${line}" =~ (status:.+\'RUNNING\') ]]; then
                echo "----- 1st avaible server: ${activeServerId} [${activeServerName}]"
                parse_found="true"
            fi
            activeServerName=""
          fi
        fi
      else
        break
      fi
    fi
  done <<< "$1"
  IFS=$IFS_SAVED

  local count=count_$2
  # run post-test jobs (checking error and dependencies)
  postTest "$1" "$2" "${!count}"
}

# parse result of a module test
parseOutput_ModuleTest() {
  local filepath=$1
  local filename=$(basename "${filepath}")
  local module_name="${filename%.*}"
  local args="$(getArgs ${module_name} $i)"
  echo "=== cmd: node ${filepath} ${args}"
  local output=$(node ${filepath} ${args} 2>&1)

  if [[ "$?" -eq "0" ]]; then
    parseOutput "${output}" ${module_name}
  fi;
}

parseOutput_ModuleTest_getFlavors() {
  flavorName=${1-standard.xlarge}
  echo `date +"%Y-%m-%d %H:%M:%S"` Getting \'${flavorName}\' flavor ...
  activeFalvorId=""
  parseOutput_ModuleTest 'lib/compute/getFlavors.js'

  if [[ "${activeFalvorId}" != "" ]]; then
    echo "----- Use matched flavor: ${activeFalvorId}"
    flavorId="${activeFalvorId}"
  fi
  echo ""
}

parseOutput_ModuleTest_getImages() {
  echo `date +"%Y-%m-%d %H:%M:%S"` Getting active image ...
  parseOutput_ModuleTest 'lib/compute/getImages.js'

  if [[ "${activeImageId}" != "" ]]; then
    echo "---- Use Active Image Id: ${activeImageId}"
    imageId="${activeImageId}"
  fi
  echo ""
}

parseOutput_ModuleTest_getServers() {
  echo `date +"%Y-%m-%d %H:%M:%S"` Getting active server ...
  parseOutput_ModuleTest 'lib/compute/getServers.js'

  if [[ "${activeServerId}" != "" ]]; then
    echo "--- Use 'running' server: ${activeServerId}"
    serverId="${activeServerId}"
  fi
  echo ""
}

# post-test jobs for error-check, clean-up, and next test preparation
postTest() {
  # post-test checking for any error message
  shopt -s nocasematch
  local hasError=`[[ "$1" =~ (error|not found) ]] && echo true`
  local asPassed=`[[ "$2" != "" ]] && echo true`
  if [[ "$asPassed" == "true" ]] && [[ "$hasError" == "true" ]]; then
    if [[ ! "$2" =~ (getServers) ]]; then
      while read -r line; do
        echo "${line}"
      done <<< "$1"
    fi
  fi

  # post-test checking dependencies for next test(s)
  if [[ "$2" == "createServer" ]]; then
    # making sure the new server is up running
    postTest_getServerTest
  elif [[ "$2" == "deleteServer" ]]; then
    # making sure all associated ports are removed after deleted server
    postTest_removePorts
  elif [[ "$2" == "getFlavors" ]]; then
    echo "----- all flavors counts: $3"
  elif [[ "$2" == "getImages" ]]; then
    echo "------ all images counts: $3"
  elif [[ "$2" == "getServers" ]]; then
    echo "----- all servers counts: $3"
  elif [[ "$2" == "getIps" ]]; then
    echo "----- floating-ip counts: $3"
  fi
}

# parse result of getServer test (after createServer) to get status
postTest_getServerTest() {
  local filepath="lib/compute/getServer.js"

  createServerStatus=""
  echo `date +"%Y-%m-%d %H:%M:%S"` Checking new server status ...
  for i in {1..20}; do
    parseOutput_ModuleTest "${filepath}"

    if [[ "${createServerStatus}" == "RUNNING" ]]; then
      hasDoneCreation_Server=true
      break
    else
      delay 10s
    fi
  done
}

# remove ports associated with ${createNetworkId} or ${createSubnetId}
postTest_removePorts() {
  associatePortId=""
  portMatchSubnet=""
  local create_id="${createPortId}"

  echo `date +"%Y-%m-%d %H:%M:%S"` Checking associated port ...
  echo "----- recent new network: ${createNetworkId}"
  echo "------ recent new subnet: ${createSubnetId}"

  for i in {1..10}; do
    parseOutput_ModuleTest "lib/network/getPorts.js"

    if [[ "${associatePortId}" == "" ]]; then
      echo "----- no more port found. all associated ports deleted."
      break
    else
      createPortId="${associatePortId}"
      echo `date +"%Y-%m-%d %H:%M:%S"` Deleting associated port ...
      parseOutput_ModuleTest "lib/network/deletePort.js"
    fi
    associatePortId=""
    portMatchSubnet=""
  done

  createPortId="${create_id}"
  echo ""
}

# print test status ($1) of a module ($2)
printStatus() {
  local status=$1
  local module=$2

  if [[ "${status}" == 'FAIL' ]]; then
    if [[ "${colors_tput}" -ge "16" ]]; then
      status="\033[31m${status}\033[0m"
    fi
  elif [[ ${status} == 'WARN' ]]; then
    if [[ "${colors_tput}" -ge "16" ]]; then
      status="\033[33m${status}\033[0m"
    fi
  else # Pass
    if [[ "${colors_tput}" -ge "16" ]]; then
      status="\033[32m${status}\033[0m"
      module="\033[34m${module}\033[0m"
    fi
  fi;

  echo -e `date +"%Y-%m-%d %H:%M:%S"` ${status}: ${module}
}

# run test of a given module ($1) for ($2) times (default: 1)
runModuleTest() {
  local filepath=$1
  local runtimes=${2-1}

  local filename=$(basename "${filepath}")
  local extension="${filename##*.}"
  local module_name=${filename%.*}

  for ((i=1; i<=${runtimes}; i++)); do
    count=$((count+1))
    echo `date +"%Y-%m-%d %H:%M:%S"` Start testing ${module_name} x $i ...
    local args="$(getArgs ${module_name} $i)"
    echo "=== cmd: node ${filepath} ${args}"
    local output=$(node ${filepath} ${args} 2>&1)

    shopt -s nocasematch
    if [[ "$?" -ne "0" ]]; then
      printStatus "FAIL" ${filepath}
      parseOutput "${output}"
    elif [[ "${output}" =~ (name: \[32m\'Error\') ]] || \
         [[ "${output}" =~ (throw er) ]] || \
         [[ "${output}" =~ (error:) ]]; then
      printStatus "WARN" ${filepath}
      parseOutput "${output}"
    else
      countSuccess=$((countSuccess+1))
      parseOutput "${output}" ${module_name}
      printStatus "PASS" ${filepath}
    fi;
    echo ""
    echo "............................................................"
    echo ""
  done
}

# run tests for compute modules (incl. floating-ips, with create/delete network)
runComputeModulesTests() {
  # ::: run compute tests :::
  local computeTests="
    getImages
    getFlavors
    createServer
    createSecurityGroup
    createImage
    getImage
    getSecurityGroup
    getSecurityGroups
    getServer
    getServers
    getVersion
    deleteImage
    deleteSecurityGroup
    deleteServer
    "
  runModuleTest "lib/compute/keys/addKey.js"
  runModuleTest "lib/network/createNetwork.js"
  runModuleTest "lib/network/createSubnet.js"

  for test in ${computeTests}; do
    if [[ "${test}" == "createServer" ]]; then
      if [[ "${provider}" == "hp" ]]; then
        runModuleTest "lib/providers/hp/compute/${test}.js"
      else
        runModuleTest "lib/compute/${test}.js"
      fi
      # assigning IP after created a server
      runModuleTest "lib/compute/floating-ips/addIp.js"
      runModuleTest "lib/compute/floating-ips/getIps.js"
    # runModuleTest "lib/compute/floating-ips/assignIp.js"
    elif [[ "${test}" == "deleteServer" ]]; then
    # runModuleTest "lib/compute/floating-ips/removeIp.js"
      runModuleTest "lib/compute/floating-ips/deleteIp.js"
      runModuleTest "lib/compute/${test}.js"
    else
      runModuleTest "lib/compute/${test}.js"
    fi
  done

  if [[ "${config_key}" == "hp" ]]; then
    runModuleTest "lib/providers/hp/compute/getServers.js"
  fi

  runModuleTest "lib/compute/keys/destroyKey.js"

  runModuleTest "lib/network/deleteSubnet.js"
  runModuleTest "lib/network/deleteNetwork.js"
}

# run tests for compute modules (with existing serverId)
runComputeModulesAndIpsTests() {
  # ::: run compute modules tests :::
  runModuleTest "lib/network/createNetwork.js"

  for service in compute providers/hp/compute; do
    for action in create update get delete; do
      for filepath in lib/${service}/${action}*.js; do
        if [[ -e "${filepath}" ]]; then
          runModuleTest "${filepath}"
        fi
      done;
    done;
  done;

  runModuleTest "lib/compute/floating-ips/deleteIp.js"

  # runNetworkModulesTests

  runModuleTest "lib/network/deleteNetwork.js"
}

# run tests for compute/keys modules
runKeysModulesTests() {
  # ::: run compute/keys tests :::
  local keysTests="
    addKey
    getKey
    getKeys
    destroyKey
    "
  for test in ${keysTests}; do
    runModuleTest "lib/compute/keys/${test}.js"
  done
}

# run tests for network modules
runNetworkModulesTests() {
  # ::: run network tests :::
  local networkTests="
    createPort
    createSubnet
    updateNetwork
    updatePort
    updateSubnet
    getNetwork
    getNetworks
    getPort
    getPorts
    getSubnet
    getSubnets
    deletePort
    deleteSubnet
    "
  local hasNetwork=`[[ "${hasDoneCreation_Network}" == "true" ]] && echo true`

  if [[ "$hasNetwork" != "true" ]]; then
    runModuleTest "lib/network/createNetwork.js"
  fi

  for test in ${networkTests}; do
    runModuleTest "lib/network/${test}.js"
  done

  if [[ "$hasNetwork" != "true" ]]; then
    runModuleTest "lib/network/deleteNetwork.js"
  fi
}

# run tests for storage modules
runStorageModulesTests() {
  # ::: run storage tests :::
  runModuleTest "lib/storage/createContainer.js"
  runModuleTest "lib/storage/uploadFile.js" 11
  runModuleTest "lib/storage/deleteContainerRobust.js"

  local storageTests="
    createContainer
    uploadFile
    getContainer
    getContainers
    getCountForContainer
    getFile
    getFiles
    deleteContainerRobust
    deleteContainer
    "
  for test in ${storageTests}; do
    runModuleTest "lib/storage/${test}.js"
  done
}

# run all/customized tests
runTests() {
  # initialize cloud settings and global variables
  buildTest

  echo ""
  echo `date +"%Y-%m-%d %H:%M:%S"` "(3). Run customized tests"
  echo "============================================================"
  # runModuleTest 'lib/compute/floating-ips/getIps.js'
  runComputeModulesTests
  # runComputeModulesAndIpsTests # (partial tests)
  runKeysModulesTests

  runNetworkModulesTests
  runStorageModulesTests

  echo "Passed: ${countSuccess} / ${count}"
}

# start running tests
runTests
