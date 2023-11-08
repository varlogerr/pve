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
