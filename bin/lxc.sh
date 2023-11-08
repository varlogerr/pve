#!/usr/bin/env bash

# Uncomment and configure TARGET_REMOTE to execute the configuration
# against remote Proxmox machine. Alternatively:
# ```sh
# echo 'TARGET_REMOTE=root@192.168.96.69' > target-remote.conf.sh
# ```
# The script will apply it if it's in the same directory where it is
# or in the ${PWD}
#
# shellcheck disable=SC2034
# TARGET_REMOTE=root@192.168.96.69

# Templates list:
TPLS_URL=http://download.proxmox.com/images/system

# shellcheck disable=SC2034
{
  NAME=nas1.home
  ID=110
  TEMPLATE=ubuntu-22.04
  UNPRIVILEGED=1
  # ROOT_PASS=changeme # Handled by password preset
  STORAGE=local-lvm
  ONBOOT=1
  CORES=4
  MEMORY=4096
  DISK=15G
  # GATEWAY=192.168.0.1 # Handled by net preset
  # IP=192.168.0.10/24
  # USER_NAME=foo # Handled by user preset
  # USER_PASS=qwerty
  PRESETS=(password net user docker)
} # HOSTNAME=nas1.home

# shellcheck disable=SC2034
{
  NAME=servant1.home
  ID=110
  TEMPLATE=ubuntu-22.04
  UNPRIVILEGED=1
  # ROOT_PASS=changeme # Handled by password preset
  STORAGE=local-lvm
  ONBOOT=1
  CORES=2
  MEMORY=2048
  DISK=10G
  # GATEWAY=192.168.0.1 # Handled by net preset
  # IP=192.168.0.11/24
  # USER_NAME=foo # Handled by user preset
  # USER_PASS=qwerty
  PRESETS=(password net user docker vpn)
} # HOSTNAME=servant1.home

# shellcheck disable=SC2034
{
  NAME=servant2.home
  ID=110
  TEMPLATE=ubuntu-22.04
  UNPRIVILEGED=1
  # ROOT_PASS=changeme # Handled by password preset
  STORAGE=local-lvm
  ONBOOT=1
  CORES=2
  MEMORY=2048
  DISK=10G
  # GATEWAY=192.168.0.1 # Handled by net preset
  # IP=192.168.0.11/24
  # USER_NAME=foo # Handled by user preset
  # USER_PASS=qwerty
  PRESETS=(password net user docker vpn)
} # HOSTNAME=servant1.home

#######################
##### END OF CONF #####
#######################

# Development configuration
PVE_GIT_REPO="${PVE_GIT_REPO-varlogerr/pve}"
PVE_GIT_BRANCH="${PVE_GIT_BRANCH-master}"
PVE_DL_URL="https://raw.githubusercontent.com/${PVE_GIT_REPO}/${PVE_GIT_BRANCH}"

dl_to_stdout() {
  declare dl_url; dl_url="${1}"
  declare -a dl_tool=(curl -kLsS)

  "${dl_tool[@]}" --version &>/dev/null || {
    dl_tool=(wget -qO -); "${dl_tool[@]}" --version &>/dev/null
  } || {
    echo "Can't detect download tool." >&2; return 1
  }

  "${dl_tool[@]}" -- "${dl_url}"
}

dl_repo_page() {
  [[ "${PVE_LOCAL,,}" =~ ^(true|1|yes|y)$ ]] && {
    cat -- "$(dirname -- "${0}")/../${1}"
    return
  }

  dl_to_stdout "${PVE_DL_URL}/${1}?$(date +%s)"
}

LXC_SELF="${LXC_SELF-$(basename -- "${0}")}"

{ # Target remote
  TARGET_REMOTE_CONF="$(
    cat -- "$(pwd)/target-remote.conf.sh" 2>/dev/null \
    || cat -- "$(dirname -- "${0}")/target-remote.conf.sh" 2>/dev/null
  )" && {
    # shellcheck disable=SC1090
    . <(cat <<< "${TARGET_REMOTE_CONF}")
  }

  # Export environment for target remote
  # shellcheck disable=SC2034
  TARGET_REMOTE_EXPORT='
    LXC_SELF
    PVE_GIT_REPO
    PVE_GIT_BRANCH
  '

  inc_remote="$(dl_repo_page inc/target-remote.sh)" || exit
  # shellcheck disable=SC1090
  . <(cat <<< "${inc_remote}")
} # Target remote

SHLIB_LOG_PREFIX="${LXC_SELF}: "
inc_shlib="$(dl_repo_page inc/shlib.sh)" || exit
# shellcheck disable=SC1090
. <(printf -- '%s\n' "${inc_shlib}")

######################
##### LXC_ACTION #####
######################

declare -A CONF; CONF=(
  [secret_dir]=/root/.secrets/lxc
  [toolname]="${LXC_SELF}"
)

declare -A COMMAND_TO_SHORT=(
  [deploy]="Deploy lxc container(s) from deployment configuration"
  [demo-conf]="Print LXC deployment configuration demo"
  [root-pass]="Configure root password preset"
  [user]="Configure user preset"
)
print_help() {
  echo "
    Deploy LXC container.

    USAGE:
    =====
      # Configure environment
      [TARGET_REMOTE=REMOTE_SERVER]
      [PVE_GIT_BRANCH=BRANCH_NAME; esport PVE_GIT_BRANCH]
      [PVE_LOCAL=true; export PVE_LOCAL]

      # View command help
      ${CONF[toolname]} COMMAND --help

      # Run command
      ${CONF[toolname]} COMMAND [ARG]...

    COMMANDS:
  " | text_fmt

  printf -- '%s\n' "${!COMMAND_TO_SHORT[@]}" \
  | sort -n | while read -r cmd; do
    offset='          '
    printf "%s %s %s\n" "${cmd}" "${offset:${#cmd}}" "${COMMAND_TO_SHORT[${cmd}]}"
  done | text_prefix '  '

  echo
  echo "
    ENV:
      TARGET_REMOTE   Remote server to run configuration for (otherwise
                      current machine is used as the target). Also can
                      be configured in the configuration
      PVE_GIT_BRANCH  Branch to work with. Dev configuration
      PVE_LOCAL       Don't pull partials from git. Dev configuration
  " | text_fmt
}

declare COMMAND
parse_command() {
  case "${1}" in
    -\?|-h|--help ) print_help; exit ;;
    *             ) COMMAND="${1}" ;;
  esac

  [[ -n "${1+x}" ]] || {
    log_fuck <<< "COMMAND required."
    echo; print_help; return 2
  }

  [[ -n "${COMMAND_TO_SHORT[${COMMAND}]+x}" ]] || {
    log_fuck <<< "Unsupported COMMAND: '${COMMAND}'."
    echo; print_help; return 2
  }
}

parse_command "${@}" || exit
shift

inc_cmd="$(dl_repo_page "inc/lxc/cmd/${COMMAND}.sh")" || exit
# shellcheck disable=SC1090
. <(cat <<< "${inc_cmd}")


exit

{ # Helpers
  download() {
    declare url="${1}"
    declare dest="${2--}"
    declare -a tool=(curl -kLsS)

    "${tool[@]}" --version &>/dev/null && {
      tool+=(-o "${dest}")
    } || {
      tool=(wget -q); "${tool[@]}" --version &>/dev/null \
      && tool+=(-O "${dest}")
    } || {
      log_fuck <<< "Can't detect download tool."
      return 1
    }

    (set -x; "${tool[@]}" -- "${url}")
  }
} # Helpers

{ # Stages
  tpl_cache() {
    declare -gA TPLS_CACHE

    [[ -n "${TPLS_CACHE[${TEMPLATE}]}" ]] || {
      declare tpl_expr; tpl_expr="$(escape_sed_expr <<< "${TEMPLATE}")"
      declare tpls_url_repl; tpls_url_repl="$(escape_sed_repl <<< "${TPLS_URL}")"

      log_info <<< "Getting download URL for template: '${TEMPLATE}'."
      declare tpl_url; tpl_url="$(set -o pipefail
        download "${TPLS_URL}" \
          | sed -n 's/.*href="\('"${tpl_expr}"'[^"]*\.tar\.\(gz\|xz\|zst\)\)".*/\1/p' \
          | sort -V | tail -n 1 | grep '' | sed 's/^/'"${tpls_url_repl}"'\//'
      )" || {
        log_fuck <<< "Can't detect download URL."
        return 1
      }

      log_info <<< "Downloading template: '${TEMPLATE}'."
      declare tmp; tmp="$(mktemp --suffix "-${tpl_url##*/}")" || {
        log_fuck <<< "Can't create tmp file."
        return 1
      }

      download "${tpl_url}" "${tmp}" || {
        log_fuck <<< "Can't download template."
        return 1
      }

      TPLS_CACHE["${TEMPLATE}"]="${tmp}"
    }
  }

  clean_tmp() {
    [[ ${#TPLS_CACHE[@]} -gt 0 ]] && (set -x; rm -f "${TPLS_CACHE[@]}")
  }
} # Stages

{ # Presets
  preset_password() {
    unset -v ROOT_PASS

    declare pass; pass="$(
      set -x
      cd -- "${CONF[secret_dir]}" && {
        cat -- "${ID}.root.pass" 2>/dev/null \
        || cat -- "master.root.pass" 2>/dev/null \
        || cat -- "master.pass" 2>/dev/null
      }
    )" || {
      log_fuck <<< "Can't read password file."
      return 1
    }

    ROOT_PASS="${pass}"; return 0
  }

  trap_preset() {
    [[ " ${PRESETS[*],,} " == *" ${1,,} "* ]] || return 0

    declare callback="preset_${1}"
    "${callback}"
  }
} # Presets

CONF_PART="$(grep -B999 '.*#\s*{{\s*LXC_ACTION\s*\/}}\s*$' -- "${0}" | sed '$ d')"

CONF_BLOCKS_TXT="$(
  grep -n '}\s\+#\s*HOSTNAME=[^ ]\+\s*$' <<< "${CONF_PART}" \
  | grep -o '^[0-9]\+' | tac | while read -r line; do
    echo '---'
    head -n "${line}" <<< "${CONF_PART}" | tac \
    | grep -m 1 -x -B999 '\s*{.*' | tac | sed -e '1 d' -e '$ d' | tac
  done | tac
)"

declare -a CONF_BLOCKS
while b_end="$(grep -m1 -nx -- '---' <<< "${CONF_BLOCKS_TXT}" | grep -o '^[0-9]\+')"; do
  CONF_BLOCKS+=("$(head -n "$(( b_end - 1 ))" <<< "${CONF_BLOCKS_TXT}")")
  CONF_BLOCKS_TXT="$(tail -n +"$(( b_end + 1 ))" <<< "${CONF_BLOCKS_TXT}")"
done

pveversion &>/dev/null || { log_fuck <<< "Can't detect PVE."; exit 1; }
[[ ${#CONF_BLOCKS[@]} -gt 0 ]] || { log_fuck <<< "No configurations found."; exit 1; }

(
  for block in "${CONF_BLOCKS[@]}"; do
    # Ensure configuration doesn't come from environment or previous iteration
    unset -v NAME TEMPLATE ID UNPRIVILEGED PASSWORD \
      STORAGE ONBOOT CORES MEMORY DISK GATEWAY IP HOOKS

    # shellcheck disable=SC1090
    . <(echo "${block}")

    # Check LXC id already in use
    id_expr="$(escape_sed_expr <<< "${ID}")"
    if pct list | sed '1 d' | grep -q "^${id_expr}[^0-9]"; then
      log_info <<< "LXC already exists: '${ID}'."
    else
      # Exports TPLS_CACHE
      tpl_cache
      trap_preset password

      (set -x;
        # Always leave password in the very end for obfuscation
        pct create "${ID}" \
          "${TPLS_CACHE[$TEMPLATE]}" \
          -storage "${STORAGE}" \
          -unprivileged "${UNPRIVILEGED}" \
          -password "${ROOT_PASS}"
      ) 3>&2 2>&1 1>&3 \
      | sed 's/\(\s-password\)\( .\+\)/\1 *****/' 3>&2 2>&1 1>&3
    fi
  done

  clean_tmp
)
