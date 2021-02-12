#!/bin/bash

# Github Action Continuous Integration for BuildRoot
# Author: Atom Long <atom.long@hotmail.com>

# Enable colors
if [[ -t 1 ]]; then
    normal='\e[0m'
    red='\e[1;31m'
    green='\e[1;32m'
    cyan='\e[1;36m'
fi

# Basic status function
_status() {
    local type="${1}"
    local status="${package:+${package}: }${2}"
    local items=("${@:3}")
    case "${type}" in
        failure) local -n nameref_color='red';   title='[BR2 CI] FAILURE:' ;;
        success) local -n nameref_color='green'; title='[BR2 CI] SUCCESS:' ;;
        message) local -n nameref_color='cyan';  title='[BR2 CI]'
    esac
    printf "\n${nameref_color}${title}${normal} ${status}\n\n"
    printf "${items:+\t%s\n}" "${items:+${items[@]}}"
}

# Get config information
_config_info() {
    local properties=("${@}")
    for property in "${properties[@]}"; do
        local -n nameref_property="${property}"
        nameref_property=($(
            source .config &>/dev/null
			[ -z ${nameref_property+x} ] && eval ${property}=$(sed -rn "s/^${property}(\w+)=y/\1/p" .config)
            declare -n nameref_property="${property}"
            echo "${nameref_property[@]}"))
    done
}

# Run command with status
execute(){
    local status="${1}"
    local command="${2}"
    local arguments=("${@:3}")
    message "${status}"
    if [[ "${command}" != *:* ]]; then
		${command} ${arguments[@]}
    else
		${command%%:*} | ${command#*:} ${arguments[@]}
    fi || failure "${status} failed"
}

# Status functions
failure() { local status="${1}"; local items=("${@:2}"); _status failure "${status}." "${items[@]}"; return 1; }
success() { local status="${1}"; local items=("${@:2}"); _status success "${status}." "${items[@]}"; return 0; }
message() { local status="${1}"; local items=("${@:2}"); _status message "${status}"  "${items[@]}"; }

# Build image
build_image()
{
local defconfig=${1}
[ -n "${defconfig}" ] || { echo "Usage: build_image <defconfig>"; exit 1; }
[ -f "configs/${defconfig}" ] || { echo "No deconfig named '${defconfig}'."; exit 1; }
[ -n "${TOOLCHAIN_URL}" ] && {
[ -z "${TOOLCHAIN_PREFIX}" ] && {
curl -OL ${TOOLCHAIN_URL} || { echo "Failed to download toolchain. Please recheck variable 'TOOLCHAIN_URL'."; return 1; }
TOOLCHAIN_FILE=$(basename ${TOOLCHAIN_URL})
TOOLCHAIN_DIR=$(tar tvf ${TOOLCHAIN_FILE} | grep ^d  | awk -F/ '{if(NF<4) print }' | sed -rn 's|.*\s(\S+)/$|\1|p')
[ -n "${TOOLCHAIN_DIR}" ] || { echo "Invalid toolchain."; exit 1; }
tar -xf ${TOOLCHAIN_FILE} -C /opt
rm -f ${TOOLCHAIN_FILE}
PATH=${PATH}:/opt/${TOOLCHAIN_DIR}/bin/
TOOLCHAIN_PREFIX=$(ls /opt/${TOOLCHAIN_DIR}/bin/*-gcc | sed -rn 's|.*/([^/]+)-gcc$|\1|p' | head -n 1)
TOOLCHAIN_GCC_VERSION=$(${TOOLCHAIN_PREFIX}-gcc --version | head -n 1 | sed -rn 's/.*\s+(\S+)$/\1/p')
TOOLCHAIN_LINUX_VERSION_CODE=$(sed -rn 's|#define\s+LINUX_VERSION_CODE\s+([0-9]+)|\1|p' $(${TOOLCHAIN_PREFIX}-gcc -print-sysroot)/usr/include/linux/version.h)
TOOLCHAIN_KERNEL_VERSION=$((TOOLCHAIN_LINUX_VERSION_CODE>>16 & 0xFF)).$((TOOLCHAIN_LINUX_VERSION_CODE>>8 & 0xFF)).$((TOOLCHAIN_LINUX_VERSION_CODE & 0xFF))
TOOLCHAIN_LIBC=$(sed -rn 's/^#\s*define\s+DEFAULT_LIBC\s+LIBC_(\w+)/\1/p' $(${TOOLCHAIN_PREFIX}-gcc -print-file-name=plugin)/include/tm.h)
BR2_TOOLCHAIN_EXTERNAL_INET_RPC=$( [ -f "$(${TOOLCHAIN_PREFIX}-gcc -print-sysroot)/usr/include/rpc/rpc.h" ] && echo "BR2_TOOLCHAIN_EXTERNAL_INET_RPC=y" || echo "# BR2_TOOLCHAIN_EXTERNAL_INET_RPC is not set")
BR2_TOOLCHAIN_EXTERNAL_CXX=$( ${TOOLCHAIN_PREFIX}-g++ -v > /dev/null 2>&1 && echo "BR2_TOOLCHAIN_EXTERNAL_CXX=y" || echo "# BR2_TOOLCHAIN_EXTERNAL_CXX is not set")
}
cp -f configs/${defconfig}{,.orig}
echo "BR2_TOOLCHAIN_EXTERNAL=y" >> configs/${defconfig}
echo "BR2_TOOLCHAIN_EXTERNAL_CUSTOM=y" >> configs/${defconfig}
echo "BR2_TOOLCHAIN_EXTERNAL_${TOOLCHAIN_LIBC}=y" >> configs/${defconfig}
echo "BR2_TOOLCHAIN_EXTERNAL_CUSTOM_${TOOLCHAIN_LIBC}=y" >> configs/${defconfig}
echo "BR2_TOOLCHAIN_EXTERNAL_GCC_${TOOLCHAIN_GCC_VERSION%%.*}=y" >> configs/${defconfig}
echo "BR2_TOOLCHAIN_GCC_AT_LEAST_${TOOLCHAIN_GCC_VERSION%%.*}=y" >> configs/${defconfig}
echo "BR2_TOOLCHAIN_EXTERNAL_HEADERS_$(sed -rn 's/^([0-9]+)\.([0-9]+).*/\1_\2/p' <<< ${TOOLCHAIN_KERNEL_VERSION})=y" >> configs/${defconfig}
echo "BR2_TOOLCHAIN_HEADERS_AT_LEAST_$(sed -rn 's/^([0-9]+)\.([0-9]+).*/\1_\2/p' <<< ${TOOLCHAIN_KERNEL_VERSION})=y" >> configs/${defconfig}
echo "# BR2_TOOLCHAIN_EXTERNAL_HEADERS_REALLY_OLD is not set" >> configs/${defconfig}
echo "BR2_TOOLCHAIN_EXTERNAL_PATH=\"/opt/${TOOLCHAIN_DIR}\"" >> configs/${defconfig}
echo "BR2_TOOLCHAIN_EXTERNAL_CUSTOM_PREFIX=\"${TOOLCHAIN_PREFIX}\"" >> configs/${defconfig}
echo "BR2_PACKAGE_PROVIDES_TOOLCHAIN_EXTERNAL=\"toolchain-external-custom\"" >> configs/${defconfig}
echo "${BR2_TOOLCHAIN_EXTERNAL_INET_RPC}" >> configs/${defconfig}
echo "${BR2_TOOLCHAIN_EXTERNAL_CXX}" >> configs/${defconfig}
}
make ${defconfig}
make clean
make
[ -f configs/${defconfig}.orig ] && mv -f configs/${defconfig}{.orig,}
}

# deploy artifacts
deploy_artifacts()
{
local deploypath=${1}
[ -n "${deploypath}" ] || { echo "Usage: deploy_artifacts <deploypath>"; return 1; }
[ -d "${ARTIFACTS_PATH}" ] || { echo "No artifacts folder '${ARTIFACTS_PATH}'."; exit 1; }
[ -f "${ARTIFACTS_PATH}/rootfs.tar" ] || { echo "No artifacts to deploy."; exit 0; }
which rclone &>/dev/null || sudo apt install rclone -y
[ -f ${HOME}/.config/rclone/rclone.conf ] || {
mkdir -pv ${HOME}/.config/rclone
printf "${RCLONE_CONF}" > ${HOME}/.config/rclone/rclone.conf
}
echo "Create checksum file..."
pushd ${ARTIFACTS_PATH}
sha512sum * > sha512.sum
popd
echo "Deploy files ..."
rclone copy "${ARTIFACTS_PATH}" "${deploypath}" --copy-links
}

# create mail message
create_mail_message()
{
local message \
	BR2_ARCH \
	BR2_GCC_TARGET_CPU \
	BR2_TARGET_GENERIC_HOSTNAME \
	BR2_TARGET_GENERIC_ROOT_PASSWD \
	BR2_INIT_ \
	BR2_ENABLE_LOCALE_WHITELIST \
	BR2_LINUX_KERNEL_VERSION \
	BR2_LINUX_KERNEL_DEFCONFIG
[ -f "${ARTIFACTS_PATH}/rootfs.tar" ] || return 0
_config_info BR2_ARCH \
			BR2_GCC_TARGET_CPU \
			BR2_TARGET_GENERIC_HOSTNAME \
			BR2_TARGET_GENERIC_ROOT_PASSWD \
			BR2_INIT_ \
			BR2_ENABLE_LOCALE_WHITELIST \
			BR2_LINUX_KERNEL_VERSION \
			BR2_LINUX_KERNEL_DEFCONFIG

message="<p>The root file system for '${DEFCONFIG/_defconfig/}' has been builded successfully.</p>"
message+="<p>The information about the file system is as follows:</p>"
message+="<p>Target Architecture: ${BR2_ARCH}</p>"
message+="<p>Target Architecture Variant: ${BR2_GCC_TARGET_CPU}</p>"
message+="<p>System hostname: ${BR2_TARGET_GENERIC_HOSTNAME}</p>"
message+="<p>Root password: ${BR2_TARGET_GENERIC_ROOT_PASSWD}</p>"
message+="<p>Init system: ${BR2_INIT_}</p>"
message+="<p>Locales to keep: ${BR2_ENABLE_LOCALE_WHITELIST}</p>"
message+="<p>Kernel version: ${BR2_LINUX_KERNEL_VERSION}</p>"
message+="<p>Name of the kernel defconfig file: ${BR2_LINUX_KERNEL_DEFCONFIG}</p>"
message+="<p>Build Number: ${CI_BUILD_NUMBER}</p>"
echo ::set-output name=message::${message}

return 0
}

# Run from here
cd ${CI_BUILD_DIR}
message 'Install build environment.'
ARTIFACTS_PATH=${CI_BUILD_DIR}/
ARTIFACTS_PATH+=$(sed -rn 's|^O := \$\(CURDIR\)/(.*)|\1|p' ${CI_BUILD_DIR}/Makefile)/
ARTIFACTS_PATH+=$(sed -rn 's|^BINARIES_DIR.*/(\w+)$|\1|p' ${CI_BUILD_DIR}/Makefile)
export ARTIFACTS_PATH="${ARTIFACTS_PATH}"
[ -z "${DEPLOY_PATH}" ] && { echo "Environment variable 'DEPLOY_PATH' is required."; exit 1; }
[[ ${DEPLOY_PATH} =~ '$' ]] && eval export DEPLOY_PATH=${DEPLOY_PATH}
[ -z "${RCLONE_CONF}" ] && { echo "Environment variable 'RCLONE_CONF' is required."; exit 1; }
[ -z "${DEFCONFIG}" ] && { echo "Environment variable 'DEFCONFIG' is required."; exit 1; }

sudo apt update -y
# sudo apt upgrade -y
# sudo apt --fix-broken install
sudo apt install build-essential unzip wget cpio rsync -y

success 'The build environment is ready successfully.'
# Build
for defcfg in $(find configs/${DEFCONFIG%_*}*_defconfig -type f -printf "%f\n"); do
execute "Building image for ${DEFCONFIG%_*}" build_image ${defcfg}
execute "Deploying artifacts for ${DEFCONFIG%_*}" deploy_artifacts ${DEPLOY_PATH%/}/${defcfg%_*}
done
create_mail_message
success 'All artifacts have been deployed successfully'
