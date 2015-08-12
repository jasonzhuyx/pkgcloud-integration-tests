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
script_source=${BASH_SOURCE[0]}
script_args=$@

# build up test environment
buildTest() {
  echo ""
  echo `date +"%Y-%m-%d %H:%M:%S"` "(1). Build test environment"
  echo "============================================================"
  count=0
  countSuccess=0
  # get number of colors of the console
  colors_tput=`tput colors`
  # get full path to this script itself
  script_file="${script_source##*/}"
  script_path="$( cd "$( echo "${script_source%/*}" )" && pwd )"
  # get runtime path info
  pkg_test="pkgcloud-integration-tests"
  nodejs=`which nodejs || echo node`
  # pkgcloud and test repositories
  repo_pkgcloud="https://github.com/pkgcloud/pkgcloud.git"
  repo_pkgcloud_fork="https://github.com/jasonzhuyx/pkgcloud.git"
  repo_pkgcloud_test="https://github.com/pkgcloud/${pkg_test}.git"
  repo_pkgcloud_test_fork="https://github.com/jasonzhuyx/${pkg_test}.git"

  # list npm config and environment settings
  echo "${nodejs##*/} version= `${nodejs} --version` - `which ${nodejs##*/}`"
  echo -e "npm version= `npm --version` - `which npm`\n`npm config ls -l`"
  echo "------------------------------------------------------------"
  (set -o posix; set)
  echo "------------------------------------------------------------"

  if [[ "$PWD" != "${script_path}" ]]; then
    echo "PWD= $PWD"
    echo `date +"%Y-%m-%d %H:%M:%S"` "Change to ${script_path//$PWD/}"
    cd "${script_path}"
  fi
  echo "PWD= $PWD"

  local devex=`[[ "${script_source}" =~ (devex-tools/aft) ]] && echo "true"`
  local devex_top=`[[ ! -d "pkgcloud" ]] && [[ ! -d "${pkg_test}" ]] && \
     [[ "${PWD##*/}" != "${pkg_test}" ]] && echo "true"`
  # clone repository for devex-tools environment
  if [[ "${devex}" == "true" ]] || [[ "${devex_top}" == "true" ]]; then
    echo ""
    echo `date +"%Y-%m-%d %H:%M:%S"` "Cleaning up test environment ..."
    rm -rf "pkgcloud"
    rm -rf "pkgcloud-integration-tests"
    repo="${repo_pkgcloud_fork}"
    echo ""
    echo `date +"%Y-%m-%d %H:%M:%S"` "Cloning pkgcloud - ${repo} ..."
    echo "------------------------------------------------------------"
    git clone "${repo}"

    repo_test="${repo_pkgcloud_test_fork}"
    echo ""
    echo `date +"%Y-%m-%d %H:%M:%S"` "Cloning test repository - ${repo_test} ..."
    echo "------------------------------------------------------------"
    git clone "${repo_test}"

    echo ""
    echo `date +"%Y-%m-%d %H:%M:%S"` "Installing pkgcloud and tests ..."
    echo "------------------------------------------------------------"
    find . -type d -exec chmod u+w {} +
    rm -rf "${script_path}/npm"
    mkdir -p "${script_path}/npm/bin"
    echo "prefix=${script_path}/npm" >> ~/.npmrc
    export PATH=${script_path}/npm/bin:$PATH
    echo "PATH=$PATH"
  fi

  # build test environment - create npm link and change to the test folder
  if [[ -d "pkgcloud" ]] && [[ -d "${pkg_test}" ]] ; then
    echo ""
    echo `date +"%Y-%m-%d %H:%M:%S"` "Creating npm link ..."
    echo "------------------------------------------------------------"
    cd pkgcloud && npm link
    echo ""
    echo `date +"%Y-%m-%d %H:%M:%S"` "Change to ${pkg_test}"
    echo "------------------------------------------------------------"
    cd "../${pkg_test}"
    git checkout test && echo ""
    npm install
    echo ""
    echo `date +"%Y-%m-%d %H:%M:%S"` "Link to pkgcloud ..."
    echo "------------------------------------------------------------"
    npm link pkgcloud
    echo ""
  elif [[ "${PWD##*/}" != "${pkg_test}" ]] && [[ -d "${pkg_test}" ]]; then
    echo "PWD= $PWD"
    cd "${pkg_test}"
  fi
  echo ""
  if [[ "${PWD##*/}" == "${pkg_test}" ]]; then
    configArgs ${script_args}
  else
    echo "Abort: Cannot find ${pkg_test} in PWD= $PWD"
    exit 1
  fi
}

# initialize global configuration and settings (only run once for all tests)
configArgs() {
  provider=hp
  default_username="Platform-AddIn-QA"
  default_password="Helion123!"
  default_auth_url="https://region-a.geo-1.identity.hpcloudsvc.com:35357/"
  openstack_use_internal="false"
  openstack_strict_ssl="true"
  echo ""
  echo `date +"%Y-%m-%d %H:%M:%S"` "(2). Start configuration"
  echo "============================================================"
  echo "PWD= $PWD"
  OS_USERNAME="${OS_USERNAME:=$default_username}"
  OS_PASSWORD="${OS_PASSWORD:=$default_password}"
  OS_AUTH_URL="${OS_AUTH_URL:=$default_auth_url}"

  if [[ "${OS_AUTH_URL}" =~ (https://(region.+)\.identity\.hpcloudsvc\.com) ]]; then
    OS_REGION=${BASH_REMATCH[2]}
  elif [[ "${OS_AUTH_URL}" =~ (https://(([0-9]+\.){3}[0-9]+\:[0-9]+)) ]]; then
    OS_AUTH_URL="https://${BASH_REMATCH[2]}"
    OS_REGION="regionOne"
    openstack_use_internal="true"
    openstack_strict_ssl="false"
    configProxy "off"
  elif [[ "${OS_REGION}" == "" ]]; then
    OS_REGION="region-a.geo-1"
  fi

  # settings for public cloud account
  auth_url="${OS_AUTH_URL}"
  username="${OS_USERNAME}"
  password="${OS_PASSWORD}"
  region="${OS_REGION}"
  config_key="${provider}"
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
      if [[ -e "${file}" ]]; then
        local filename=$(basename "${file}")
        local conf_key=${filename/.config.json/}
        local conf_provider="" conf_auth_url="" conf_region=""
        local conf_username="" conf_password=""
        local readConfigUser=""
        echo `date +"%Y-%m-%d %H:%M:%S"` "Checking ${filename} ..."
        while read -r line; do
          if [[ "${readConfigUser}" == "" ]] && \
            ([[ "${line}" =~ (\"$conf_key\":) ]] || \
             [[ "${line}" =~ (\"(.+)\":.+{) ]]); then
            echo `date +"%Y-%m-%d %H:%M:%S"` "Loading $conf_key ..."
            readConfigUser=true
          elif [[ "${line}" =~ (\"username\"[ ]*:[ ]*\"(.+)\") ]]; then
            echo "---- username: ${BASH_REMATCH[2]}"
            conf_username="${BASH_REMATCH[2]}"
          elif [[ "${line}" =~ (\"password\"[ ]*:[ ]*\"(.+)\") ]]; then
            conf_password="${BASH_REMATCH[2]}"
          elif [[ "${line}" =~ (\"provider\"[ ]*:[ ]*\"(.+)\") ]]; then
            echo "---- provider: ${BASH_REMATCH[2]}"
            conf_provider="${BASH_REMATCH[2]}"
          elif [[ "${line}" =~ (\"region\"[ ]*:[ ]*\"(.+)\") ]]; then
            echo "------ region: ${BASH_REMATCH[2]}"
            conf_region="${BASH_REMATCH[2]}"
          fi
        done < ${file}
        if [[ "${readConfigUser}" == "true" ]] &&
           [[ "${conf_username}" != "" ]] && [[ "$conf_password" != "" ]] && \
           [[ "${conf_provider}" != "" ]] && [[ "$conf_region" != "" ]]; then
          echo `date +"%Y-%m-%d %H:%M:%S"` "Loaded $conf_key"
          config_key="${conf_key}"
          config_filename="${config_path}/${conf_key}.config.json"
          provider="${conf_provider}"
          username="${conf_username}"
          region="${conf_region}"
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
    "strictSSL": ${openstack_strict_ssl},
    "useInternal": ${openstack_use_internal},
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

  preTestKey=`date +"%Y%m%d_%H%M%S"`"r$((RANDOM%10))"
  newKeyName="newKey-${preTestKey}"
  newName="newTest-${preTestKey}"
  # flavor_id -
  #   100-105 standard.xsmall, .small, .medium, .large, .xlarge, .2xlarge
  #   110,114 standard.4xlarge, standard.8xlarge
  #   203-205 highmem.large, .xlarge, .2xlarge
  flavorId=101

  # get test args from a public cloud account
  parseOutput_ModuleTest_getFlavors "xlarge"
  parseOutput_ModuleTest_getNetworks
  parseOutput_ModuleTest_getServers
  parseOutput_ModuleTest_getImages

  containerName="${newName}-container"
  addKeyName="${newKeyName}"
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
  args_createImage="newImage-${preTestKey}-${posKey} ${createServerId}"
  # lib/compute/createImage {newSecurityGroup} {description}
  args_createSecurityGroup="newSG-${preTestKey} newSecurityGroupDescription-${preTestKey}"
  # lib/compute/createServer {name} {flavor} {image} {keyname} {networkId}
  local newServer="newServer-${preTestKey}-${posKey}"
  args_createServer="${newServer} ${flavorId} ${imageId} ${addKeyName} ${createNetworkId}"
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
  args_createNetwork="newNetwork-${preTestKey}-${posKey}"
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
  args_updateNetwork="${createNetworkId} updatedNetwork-${preTestKey}-${posKey}"
  # lib/network/updatePort {portId} {updatedPortName}
  args_updatePort="${createPortId} updatedPort-${preTestKey}-${posKey}"
  # lib/network/updateSubnet {subnetId} {updatedSubnetName}
  args_updateSubnet="${createSubnetId} updatedSubnet-${preTestKey}-${posKey}"

  # ::: pre-defined arguments for the storage tests ::: ====================
  # lib/storage/createContainer {newContainerName}
  args_createContainer="${containerName}"
  # lib/storage/deleteContainer {containerName}
  args_deleteContainer="${containerName}"
  # lib/storage/deleteContainerRobust {containerName}
  args_deleteContainerRobust="${containerName}"
  # lib/storage/getContainer {containerName}
  args_getContainer="${containerName}"
  # lib/storage/getCountForContainer {containerName}
  args_getCountForContainer="${containerName}"
  # lib/storage/getFile {containerName} {filename}
  args_getFile="${containerName} test${xtimes}.json"
  # lib/storage/getFiles {containerName}
  args_getFiles="${containerName}"
  # lib/storage/uploadFile {containerName} {newFileName} {source}
  args_uploadFile="${containerName} test${xtimes}.json ${config_filename}"
  # lib/storage/other/download-to-stdout {containerName} {remoteFileName}
  args_download_to_stdout="${containerName} test.json"
  # lib/storage/other/upload-end-write {containerName} {remoteFileName}
  args_upload_end_write="${containerName} test.json"
}

# enable/disable proxy settings
configProxy() {
  if [[ "$1" =~ (on) ]] || [[ "$1" =~ (enabled) ]]; then
    if [[ "${HTTP_PROXY:=$http_proxy}" == "" ]]; then
      echo `date +"%Y-%m-%d %H:%M:%S"` "Restoring proxy settings ..."
      export http_proxy="${env_http_proxy}"
      export https_proxy="${env_http_sproxy}"
    fi
  elif [[ "${HTTP_PROXY:=$http_proxy}" != "" ]]; then
      echo `date +"%Y-%m-%d %H:%M:%S"` "Disabling proxy settings ..."
      env_http_proxy="${HTTP_PROXY:=$http_proxy}"
      env_https_proxy="${HTTPS_PROXY:=$https_proxy}"
      export http_proxy=""
      export HTTP_PROXY=""
      export https_proxy=""
      export HTTPS_PROXY=""
  fi
}

# sleep for specific time (e.g. 10s, 5m)
delay() {
  #for i in {1..60}; do echo -n .; done; # printf '.=%.0s' {1..60}
  echo `date +"%Y-%m-%d %H:%M:%S"` "Sleeping ${1-1s} ..."
  sleep ${1-1s}
}

# get arguments for a test module
# note: default arguments are ${provider} ${username} ${region} but some tests
#       requires additional arguments after ${provider}
getArgs() {
  local module="${1//-/_}"
  local xtimes="${2-1}"

  # build a global dynamic dictionary in order to get options for $1 test
  configDynamicArgsDict ${xtimes}

  arg=args_$module
  options="${config_key} ${!arg} ${username} ${region}"
  result="${options/  / }"
  echo "${result}"
}

# parse output from test result and
# get id for create* test if the test succeeded; otherwise
# print output if the test failed (when $2 not specified)
parseOutput() {
  local module="${2//-/_}"
  local count_${module}=""
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
      elif [[ "$2" == "getCountForContainer" ]]; then
        if [[ "${line}" =~ ( info.?:.+\'(\d+)\') ]]; then
          echo "---- counts in container: ${BASH_REMATCH[2]}"
        fi
      elif [[ "$2" == "getFlavors" ]]; then
        if [[ "${line}" =~ ( id:.+\'([0-9]+)\') ]]; then
          count_getFlavors=$((${count_getFlavors}+1))
          if [[ "${parse_found}" != "true" ]]; then
            activeFlavorId="${BASH_REMATCH[2]}"
          fi
        elif [[ "${count_getFlavors}" != "" ]] && [[ "${parse_found}" != "true" ]]; then
          if [[ "${line}" =~ (name:) ]] && \
             [[ "${line}" =~ (name:.+\'.*\.${flavorName}\') ]]; then
              echo "----- 1st matched flavor: ${activeFlavorId}"
              parse_found="true"
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
      elif [[ "$2" == "getNetworks" ]]; then
        if [[ "${line}" =~ (name:.+\'(.+)\') ]]; then
          count_getNetworks="$((${count_getNetworks}+1))"
          if [[ "${parse_found}" != "true" ]]; then
            activeNetworkName="${BASH_REMATCH[2]}"
          fi
        elif [[ "${parse_found}" != "true" ]] && \
             [[ "${count_getNetworks}" != "" ]] && \
             [[ "${activeNetworkName}" != "Ext-Net" ]]; then
          if [[ "${line}" =~ ( id:.+\'([0-9a-z-]{36})\') ]]; then
            activeNetworkId="${BASH_REMATCH[2]}"
          elif [[ "${line}" =~ (status:) ]]; then
            if [[ "${line}" =~ (status:.+\'ACTIVE\') ]]; then
                echo "----- 1st Active Network: ${activeNetworkId} [${activeNetworkName}]"
                parse_found="true"
            fi
            activeNetworkName=""
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

  local count=count_${module}
  # run post-test jobs (checking error and dependencies)
  postTest "$1" "$2" "${!count}"
}

# parse result of a module test
parseOutput_ModuleTest() {
  local filepath=$1
  local filename=$(basename "${filepath}")
  local module_name="${filename%.*}"
  local args="$(getArgs ${module_name} $i)"
  echo "=== cmd: ${nodejs} ${filepath} ${args}"
  local output=$(${nodejs} ${filepath} ${args} 2>&1)

  if [[ "$?" -eq "0" ]]; then
    parseOutput "${output}" ${module_name}
  fi;
}

parseOutput_ModuleTest_getFlavors() {
  flavorName=${1-standard.xlarge}
  echo `date +"%Y-%m-%d %H:%M:%S"` Getting \'${flavorName}\' flavor ...
  activeFlavorId=""
  parseOutput_ModuleTest 'lib/compute/getFlavors.js'

  if [[ "${activeFlavorId}" != "" ]]; then
    echo "----- Use matched flavor: ${activeFlavorId}"
    flavorId="${activeFlavorId}"
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

parseOutput_ModuleTest_getNetworks() {
  echo `date +"%Y-%m-%d %H:%M:%S"` Getting active network ...
  parseOutput_ModuleTest 'lib/network/getNetworks.js'

  if [[ "${activeNetworkId}" != "" ]]; then
    echo "--- Use 'active' network: ${activeNetworkId}"
    networkId="${activeNetworkId}"
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
  local IFS_SAVE=$IFS
  IFS='\n'
  if [[ "$asPassed" == "true" ]] && [[ "$hasError" == "true" ]]; then
    if [[ ! "$2" =~ (getServers) ]]; then
      while read -r line; do
        echo "${line}"
      done <<< "$1"
    fi
  fi
  IFS=$IFS_SAVE

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
  elif [[ "$2" == "getNetworks" ]]; then
    echo "---- all networks counts: $3"
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
    echo "=== cmd: ${nodejs} ${filepath} ${args}"
    local output=$(${nodejs} ${filepath} ${args} 2>&1)

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
  runModuleTest "lib/storage/getCountForContainer.js"
  runModuleTest "lib/storage/deleteContainerRobust.js"

  local storageTests="
    createContainer
    uploadFile
    other/upload-end-write
    other/download-to-stdout
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
  runModuleTest "lib/compute/floating-ips/getIps.js"
  # runComputeModulesTests
  # runKeysModulesTests
  # runNetworkModulesTests
  # runStorageModulesTests

  echo "Passed: ${countSuccess} / ${count}"
}

# start running tests
runTests
