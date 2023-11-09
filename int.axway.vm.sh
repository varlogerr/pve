#!/usr/bin/env bash

# List of available images
TPLS_URL=http://download.proxmox.com/images/system
# Remote to run on. If the machine the current script is
# running on is a PVE server, this setting will be disregarded
TARGET_REMOTE=root@192.168.69.95

# CONTAINERS CONFIGURATION
# ========================
# Any LXC_CONF_* variable will be used for container creation
# and configuration

# shellcheck disable=SC2034
declare -A LXC_CONF_INT1=(
  # Init only settings
  [TEMPLATE]=almalinux-8-default_20210928_amd64.tar.xz
  [ID]=141
  [ROOT_PASS]=changeme
  [STORAGE]='local-lvm'
  [UNPRIVILEGED]=0
  # Mutable settings
  [IP]=192.168.69.41/24
  [GATEWAY]=192.168.69.1
  [DISK]=5G
  # Optional
  [HOSTNAME]=int1.axway.vm
  [ONBOOT]=1
  [PRESETS]='
    vpn
    docker
  '
  [TOOLBOX]='
    ssh-server
    basic-tools
    gp-client
    apiportal-prereq
  '
)

#######################
##### END OF CONF #####
#######################

#
# LIBRARY
#

# shellcheck disable=SC2120
get_conf_vars_txt() (
  declare rename="${1-false}"
  declare expr='\(LXC_CONF_[^=]\+\)'

  declare -a rename_filter=(cat)
  ${rename} && rename_filter=(sed 's/'"${expr}"'/LXC_CONF/')

  set -o pipefail
  (set -o posix; set) | grep "^${expr}" \
  | sed 's/^'"${expr}"'.*/\1/' \
  | while read -r v; do
    declare -p "${v}"
  done | grep '^declare -A' | "${rename_filter[@]}"
)

deploy() (
  create() {
    pct list | sed '1 d' | grep -q "^${LXC_CONF[ID]}[^0-9]" && {
      echo "[INFO] CT exists: '${LXC_CONF[ID]}'." >&2
      return
    }

    declare TPL_FILE; TPL_FILE="$(set -x; mktemp --suffix .lxc-template.tar.xz)"
    declare -i RC=0

    (set -x; curl -kLsS "${TPLS_URL}/${LXC_CONF[TEMPLATE]}" \
    | tee -- "${TPL_FILE}" >/dev/null)

    (set -o pipefail
      (set -x
        # Create container
        pct create "${LXC_CONF[ID]}" \
          "${TPL_FILE}" \
          -storage "${LXC_CONF[STORAGE]}" \
          -unprivileged "${LXC_CONF[UNPRIVILEGED]}" \
          -password "${LXC_CONF[ROOT_PASS]}"
      ) 3>&2 2>&1 1>&3 \
      | sed 's/\(\s-password\)\( .\+\)/\1 *****/' 3>&2 2>&1 1>&3
    ) || {
      RC=$?
      echo "[FUCK] Couldn't create CT: '${LXC_CONF[ID]}'."
    }

    (set -x; rm -f "${TPL_FILE}")
    return ${RC}
  }

  configure() {
    (set -x; pct resize "${LXC_CONF[ID]}" rootfs "${LXC_CONF[DISK]}")
    (set -x; pct set "${LXC_CONF[ID]}" -net0 \
      name=eth0,bridge=vmbr0,firewall=1,ip="${LXC_CONF[IP]}",gw="${LXC_CONF[GATEWAY]}"
    ) 3>&2 2>&1 1>&3 | sed 's/\(,\(ip\|gw\)=\)[^,]\+/\1*****/g'

    [[ -n "${LXC_CONF[HOSTNAME]}" ]] && (
      set -x; pct set "${LXC_CONF[ID]}" -hostname "${LXC_CONF[HOSTNAME]}"
    )
    [[ -n "${LXC_CONF[ONBOOT]}" ]] && (
      set -x; pct set "${LXC_CONF[ID]}" -onboot "${LXC_CONF[ONBOOT]}"
    )

    return 0
  }

  presets() {
    declare conffile="/etc/pve/lxc/${LXC_CONF[ID]}.conf"
    # Remove space-only lines, trim spaces and uncomment
    declare -A PRESETS=(
      [vpn]='
        # Allow VPN: https://pve.proxmox.com/wiki/OpenVPN_in_LXC
        lxc.mount.entry: /dev/net dev/net none bind,create=dir 0 0
        lxc.cgroup2.devices.allow: c 10:200 rwm
      '
      [docker]='
        # Allow docker: https://gist.github.com/varlogerr/9805998a6ac9ad4fa930a07951e9a3dc
        lxc.apparmor.profile: unconfined
        lxc.cgroup2.devices.allow: a
        lxc.cap.drop:
      '
    )

    declare presets_req; presets_req="$(
      set -o pipefail; grep -v '^\s*#'  <<< "${LXC_CONF[PRESETS]}" \
      | tr ' ' '\n' | sed -e '/^\s*$/d' -e 's/^\s*//' -e 's/\s*$//' -e '/^#/d' \
      | grep -Fxf <(printf -- '%s\n' "${!PRESETS[@]}")
    )" || {
      echo "[INFO] No presets requested."
      return 0
    }

    {
      echo '[INFO] Requested presets:'
      # shellcheck disable=SC2001
      sed 's/^/[INFO] * /' <<< "${presets_req}"
    } >&2

    declare presets_conf
    declare p; while read -r p; do
      presets_conf+="${presets_conf+$'\n'}${PRESETS[$p]}"
    done <<< "${presets_req}"

    # Remove space-only lines, trim spaces and uncomment
    presets_conf="$(sed -e '/^\s*$/d' -e 's/^\s*//' -e 's/\s*$//' \
      -e '/^#/d' <<< "${presets_conf}"
    )"

    declare CONF_TEXT; CONF_TEXT="$(cat -- "${conffile}")"
    declare CURRENT_CONF; CURRENT_CONF="$(
      # Ensure new line and dummy snapshot marker to the configuration
      # shellcheck disable=SC1003
      sed '$a\' <<< "${CONF_TEXT}" | { cat; echo '[dummy]'; } \
      | grep -m1 -B 9999 -x '\s*\[[^]]\+\]\s*' | sed -e '$ d' -e 's/^\s*//' -e 's/\s*$//'
    )"

    declare insert; insert="$(grep -vFxf <(cat <<< "${CURRENT_CONF}") <<< "${presets_conf}")" && {
      # shellcheck disable=SC1003
      CURRENT_CONF+=$'\n'"${insert}"

      {
        echo '[INFO] New LXC configurations:'
        cat <<< "${insert}" | sed -e 's/^/[INFO] * /'
      } >&2

      {
        echo "${CURRENT_CONF}"
        # shellcheck disable=SC1003
        { cat <<< "${CONF_TEXT}"; echo '[dummy]'; } \
        | grep -m1 -A 9999 -x '\s*\[[^]]\+\]\s*' | sed -e '$ d'
      } | (set -x; tee -- "${conffile}") >/dev/null
    }

    return 0
  }

  provision() {
    declare toolbox_req; toolbox_req="$(
      set -o pipefail; grep -v '^\s*#'  <<< "${LXC_CONF[TOOLBOX]}" \
      | tr ' ' '\n' | sed -e '/^\s*$/d' -e 's/^\s*//' -e 's/\s*$//'
    )" || {
      echo "[INFO] No toolbox requested."
      return 0
    }

    {
      echo '[INFO] Requested toolbox:'
      # shellcheck disable=SC2001
      sed 's/^/[INFO] * /' <<< "${toolbox_req}"
    } >&2

    declare -a TOOLBOX; mapfile -t TOOLBOX <<< "${toolbox_req}"

    declare TOOLBOX_URL=https://raw.githubusercontent.com/varlogerr/pve/master/toolbox
    declare WAS_RUNNING=false
    pct status "${LXC_CONF[ID]}" | grep -q 'running$' && WAS_RUNNING=true

    if ! ${WAS_RUNNING}; then
      # Boot the CT
      (set -x
        pct start "${LXC_CONF[ID]}"
        lxc-wait "${LXC_CONF[ID]}" --state="RUNNING" -t 10
      ) || {
        echo "[FUCK] Failed to start the CT. Skipping." >&2
        (set -x; pct stop "${LXC_CONF[ID]}"); return 0
      }
    fi

    # Give it 5 seconds to warm up the services
    uptime="$(pct exec "${LXC_CONF[ID]}" -- bash -c \
      '(set -x; grep -o "^[0-9]\\+" /proc/uptime 2>/dev/null)')"
    [[ "${uptime:-0}" -lt 5 ]] && sleep $(( 5 - "${uptime:-0}" ))

    declare i; for i in "${TOOLBOX[@]}"; do
      (set -x; curl -sSL "${TOOLBOX_URL}/${i}/apply.sh") | pct exec "${LXC_CONF[ID]}" -- bash -s
    done

    # Shut down the CT only if it was not running
    ! ${WAS_RUNNING} && (set -x; pct stop "${LXC_CONF[ID]}")
  }

  # Get config vars
  configs_txt="$(set -o pipefail; get_conf_vars_txt true)" || {
    echo "[WARN] No 'LXC_CONF_' configs detected." >&2
    exit
  }; mapfile -t configs <<< "${configs_txt}"

  for conf in "${configs[@]}"; do
    # This will produce LXC_CONF variable
    eval "${conf}"

    create && configure && presets && provision
  done
)

gen_user() {
  # TODO: implement
  echo "Not implemented" >&2
  return 2
}

gen_root() {
  # TODO: implement
  return 2
}

print_help() (
  declare tool; tool="$(basename -- "${0}")"

  declare toolbox; toolbox="$(
    curl -s https://api.github.com/repos/varlogerr/pve/contents/toolbox \
    | grep '^\s*"name":' | sed 's/.*"\([^"]\+\)",\?/\1/'
  )"

  usage() { echo "
    USAGE:
    =====
   ,  ${tool} COMMAND
  "; }

  commands() { echo "
    COMMANDS:
    ========
   ,  deploy      Deploy the configuration
   ,  gen-user    Generate user configuration. Target only
   ,  gen-root    Generate root password. Target only
   ,
   Target only commands can only be performed on a PVE host.
  "; }

  presets() { echo "
    PRESETS:
    =======
   ,  vpn     Make container VPN server ready
   ,  docker  Make container docker installation ready
   ,
    In the configuration block presets are new line or space
    separated. Offset, empty or #-comment lines ignored.
  "; }

  toolbox() {
    # shellcheck disable=SC2001
    echo "
      TOOLBOX:
      =======
      $(sed 's/^/,  /' <<< "${toolbox}")
    "
  }

  [[ -n "${1+x}" ]] && {
    "$1" | sed -e '/^\s*$/d' -e 's/^\s\+//' -e 's/^,//'; return
  }

  # shellcheck disable=SC2001
  echo "
    For configuration see LXC_CONF_* configurations in the top
    of '${0}'.
   ,
    $(usage)
   ,
    $(commands)
   ,
    $(presets)
   ,
    $(toolbox)
  " | sed -e '/^\s*$/d' -e 's/^\s\+//' -e 's/^,//'
)

run_cmd() {
  declare dry=false
  # It can be a check-command
  [[ "${1}" == '_' ]] && { dry=true; shift; }

  [[ -n "${1}" ]] || {
    echo "[FUCK] Command required."
    echo
    print_help commands
    return 2
  } >&2

  declare CMD
  case "${1}" in
    -\?|-h|--help ) print_help; exit ;;
    deploy        ) CMD=deploy ;;
    gen-user      ) CMD=gen_user ;;
    gen-root      ) CMD=gen_root ;;
  esac

  [[ -n "${CMD}" ]] || {
    echo "[FUCK] Invalid command: '${1}'."
    echo
    print_help commands
    return 2
  } >&2

  declare -a target_only=(
    gen-user gen-root
  )

  [[ " ${target_only[*]} " == *" ${1} "* ]] && ! ${IS_TARGET_DIRECT} && {
    echo "[FUCK] This command can only be performed on a PVE target machine." >&2
    return 1
  }

  ${dry} && return 0
  "${CMD}"
}

####################
##### ENDPOINT #####
####################

# Ensure some hard to reproduce and meaningless first arg for marker
TARGET_REMOTE_MARKER='s?NXs#{Bb8}ir:4ehUok633iQ0>k5uM~'
IS_TARGET_DIRECT=false

(
  pveversion &>/dev/null \
  || [[ "${1}" == "${TARGET_REMOTE_MARKER}" ]]
) && { # TARGET MACHINE
  # The script is either initially is running on the PVE machine
  # or we came here via ssh.

  # Ensure TARGET_REMOTE_MARKER argument is shifted
  [[ "${1}" == "${TARGET_REMOTE_MARKER}" ]] && {
    shift
  } || {
    IS_TARGET_DIRECT=true
  }

  pveversion &>/dev/null || {
    echo "[FUCK] Not a PVE target machine." >&2
    exit 1
  }

  run_cmd "${@}"; exit

  ###########################
  ##### END OF LXC CONF #####
  ###########################
} # TARGET MACHINE

#
# Launch on remote from local machine
#

run_cmd '_' "${@}" || exit

escape_dq() { sed -e 's/"/\\"/g' -e 's/^/"/' -e 's/$/"/'; }

TARGET_REMOTE_ARGS=(); for arg in "${@}"; do
  # shellcheck disable=SC2001
  TARGET_REMOTE_ARGS+=("$(escape_dq <<< "${arg}")")
done

# shellcheck disable=SC2016
echo '
  tmp="$(mktemp)"; chmod 0700 "${tmp}"
  base64 -d <<< "'"$(base64 -- "${0}")"'" > "${tmp}"

  # Send target remote marker
  "${tmp}" "'"${TARGET_REMOTE_MARKER}"'" '"${TARGET_REMOTE_ARGS[*]}"'
  RC=$?

  rm -f "${tmp}"
  exit ${RC}
' | ssh "${TARGET_REMOTE}" bash -s
