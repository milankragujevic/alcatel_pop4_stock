#!/system/bin/sh

## !!!! If Itson has NOT been enabled by Perso, exit shell immediately.
# Getprop is not initialized yet, so parse system properties manually
PERSO_ITSON_ENABLE=$(grep -m 1 '^persist.sys.itson.enabled=' /system/build.prop)
PERSO_ITSON_ENABLE=${PERSO_ITSON_ENABLE#*=}
if [ $PERSO_ITSON_ENABLE -eq 1 ]; then
    bootlog "Itson has been enabled by Perso"
else
    bootlog "Itson has NOT been enabled by Perso"
    exit;
fi

bootlog() {
    log -p i -t "ItsOnBootstrapper" "$*"
}

bootlog "ItsOn bootstrapper starting"


PATH="/system/vendor/itson:${PATH}"

# Getprop is not initialized yet, so parse system properties manually
ANDROID_VERSION=$(grep -m 1 '^ro.build.version.release=' /system/build.prop)
ANDROID_VERSION=${ANDROID_VERSION#*=}
ANDROID_FINGERPRINT=$(grep -m 1 '^ro.build.fingerprint=' /system/build.prop)
ANDROID_FINGERPRINT=${ANDROID_FINGERPRINT#*=}
ANDROID_INCREMENTAL=$(grep -m 1 '^ro.build.version.incremental=' /system/build.prop)
ANDROID_INCREMENTAL=${ANDROID_INCREMENTAL#*=}

# ItsOn install location configuration
ITSON_BASE=$(grep -m 1 '^ro.itson.path=' /system/build.prop)
ITSON_BASE=${ITSON_BASE#*=}
ITSON_BASE=${ITSON_BASE%%/}

bootlog "Android version is ${ANDROID_VERSION}"
bootlog "Android fingerprint is ${ANDROID_FINGERPRINT}"
bootlog "Android build incremental is ${ANDROID_INCREMENTAL}"
bootlog "ItsOn base dir is ${ITSON_BASE}"

ENABLE_FLAG_BOOTSTRAPPER="/data/data/com.itsoninc.android.bootstrapper/itson.enable"
MANIFEST="${ITSON_BASE}/manifest"
FINGERPRINT_FILE="${ITSON_BASE}/android.fingerprint"
KERNEL_API_FILE="/system/vendor/itson/kernel.api"
KERNEL_SUPPORTED_FILE="${ITSON_BASE}/kernel.supported"
INTEGRATION_VERSION_FILE="/system/vendor/itson/integration.version"
INTEGRATION_SUPPORTED_FILE="${ITSON_BASE}/integration.supported"

UPDATE_ZIP_BOOTSTRAPPER="/data/data/com.itsoninc.android.bootstrapper/app_update_staging/itson-update.zip"
UPDATE_ZIP_SERVICE="/data/data/com.itsoninc.android.itsonservice/app_update_staging/itson-update.zip"

MODULE1_SYSTEM="/system/lib/modules/itson_module1.ko"
MODULE2_SYSTEM="/system/lib/modules/itson_module2.ko"
MODULE1_OTA="${ITSON_BASE}/resources/itson_module1-${ANDROID_VERSION}-${ANDROID_INCREMENTAL}.ko"
MODULE2_OTA="${ITSON_BASE}/resources/itson_module2-${ANDROID_VERSION}-${ANDROID_INCREMENTAL}.ko"

is_enabled() {
  # Flag file exists
  [ -f ${ENABLE_FLAG_BOOTSTRAPPER} ]
}

is_installed() {
  # Manifest file exists
  [ -f ${MANIFEST} ]
}

is_fingerprint_mismatch() {
  # Fingerprint file does not exist or has wrong fingerprint
  [ ! -f ${FINGERPRINT_FILE} ] || ! grep -Fxq "${ANDROID_FINGERPRINT}" ${FINGERPRINT_FILE}
}

update_fingerprint() {
  echo -E "${ANDROID_FINGERPRINT}" > ${FINGERPRINT_FILE}
  chmod 600 ${FINGERPRINT_FILE}
}

vercomp() {
  # Compare versions using dotted notation, ignore "-" suffixes, ignore letters/special characters
  local ver1=${1%%-*} ver2=${3%%-*} a b
  while [ -n "${ver1}" ] || [ -n "${ver2}" ]; do
    a=${ver1%%.*}
    ver1=${ver1#"${a}"}
    ver1=${ver1#.}
    a=${a//[!0-9]/}
    b=${ver2%%.*}
    ver2=${ver2#"${b}"}
    ver2=${ver2#.}
    b=${b//[!0-9]/}
    if (( "10#${a}" > "10#${b}" )); then
      [[ "$2" == ">" || "$2" == ">=" || "$2" == "!=" ]]; return $?
    fi
    if (( "10#${a}" < "10#${b}" )); then
      [[ "$2" == "<" || "$2" == "<=" || "$2" == "!=" ]]; return $?
    fi
  done
  [[ "$2" == "=" || "$2" == "==" || "$2" == ">=" || "$2" == "<=" ]]; return $?
}

is_kernel_api_supported() {
  # Kernel api is in list of OTAd supported kernels
  [ -f ${KERNEL_SUPPORTED_FILE} ] && grep -Fxq "$(cat ${KERNEL_API_FILE})" ${KERNEL_SUPPORTED_FILE}
}

is_framework_integration_supported() {
  # integration version (major only) <= OTAd supported version
  if [ -f ${INTEGRATION_SUPPORTED_FILE} ]; then
    local integration_version=$(cat ${INTEGRATION_VERSION_FILE})
    integration_version=${integration_version%%.*}
    vercomp "${integration_version}" "<=" "$(cat ${INTEGRATION_SUPPORTED_FILE})"
  else
    false
  fi
}

is_fail_closed() {
  # Fail close if carrier flag has fail=closed
  grep -Fxq "initial_service_mode=closed" ${ENABLE_FLAG_BOOTSTRAPPER}
}

# Install / Update / Remove
if is_enabled; then
  bootlog "ItsOn is enabled"

  if ! is_installed; then
    # Initial install
    bootlog "Performing initial install"
    rm -rf ${ITSON_BASE}
    itson_installer ${UPDATE_ZIP_BOOTSTRAPPER}
    rm -f ${UPDATE_ZIP_BOOTSTRAPPER}

    # Update fingerprint file
    update_fingerprint
  elif [ -f ${UPDATE_ZIP_SERVICE} ]; then
    # OTA update exists, apply it
    bootlog "Performing OTA update"
    itson_installer ${UPDATE_ZIP_SERVICE}
    rm -f ${UPDATE_ZIP_SERVICE}
  fi

  if is_fingerprint_mismatch; then
    # Ensure that installed version can handle this MR
    if ! is_framework_integration_supported; then
      bootlog "Performing MR update - installed version does not support framework integration"
      rm -rf ${ITSON_BASE}
    elif ! is_kernel_api_supported; then
      bootlog "Performing MR update - installed version does not support kernel api"
      rm -rf ${ITSON_BASE}
    else
      bootlog "Installed version supports this MR"
      update_fingerprint
    fi
  fi
else
  bootlog "ItsOn is not enabled"

  # Remove if installed
  if is_installed; then
    bootlog "Removing installation"
    rm -rf ${ITSON_BASE}
  fi
fi

# Initialize system
if is_installed; then
  # Apply SELinux policies if applicable
  if command -v restorecon &> /dev/null; then
    bootlog "Applying SELinux policies"
    restorecon -R ${ITSON_BASE}
  fi

  # Determine initial service mode
  if is_fail_closed; then
    INITIAL_SERVICE_MODE="2"
  else
    INITIAL_SERVICE_MODE="1"
  fi

  bootlog "Initial Service Mode is ${INITIAL_SERVICE_MODE}"

  # Load the kernel modules
  if [ -f ${MODULE1_OTA} ] && [ -f ${MODULE2_OTA} ]; then
    bootlog "Loading kernel modules from OTA"
    insmod ${MODULE1_OTA}
    insmod ${MODULE2_OTA} initial_service_mode=${INITIAL_SERVICE_MODE}
  else
    bootlog "Loading kernel modules from system"
    insmod ${MODULE1_SYSTEM}
    insmod ${MODULE2_SYSTEM} initial_service_mode=${INITIAL_SERVICE_MODE}
  fi
fi

bootlog "ItsOn bootstrapper done"
