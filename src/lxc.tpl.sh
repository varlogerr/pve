# {{ SOURCE=shlib.sh /}}

SELF_NAME="${SELF_NAME-$(basename -- "${0}")}"
# shellcheck disable=SC2034
SHLIB_LOG_PREFIX="${SELF_NAME} :"

declare -A CONF; CONF=(
  [secret_dir]=/root/.secrets/lxc
)

declare -a LOCAL_ONLY_COMMANDS=(demo-conf help)
declare -A COMMAND_TO_SHORT=(
  [deploy]="Deploy lxc container(s) from deployment configuration"
  [demo-conf]="Print LXC deployment configuration demo"
  [root-pass]="Configure root password preset"
  [user]="Configure user preset"
)
trap_help() {
  echo "
    Deploy LXC container.

    USAGE:
    =====
      # View command help
      ${SELF_NAME} COMMAND --help

      # Configure environment
      [TARGET_REMOTE=REMOTE_SERVER; export TARGET_REMOTE]

      # Run command
      ${SELF_NAME} COMMAND [ARG]...

    COMMANDS:
  " | text_fmt

  printf -- '%s\n' "${!COMMAND_TO_SHORT[@]}" \
  | sort -n | while read -r suffixed; do
    cmd="${suffixed%%:*}"
    offset='          '
    printf "%s %s %s\n" "${cmd}" "${offset:${#cmd}}" "${COMMAND_TO_SHORT[${suffixed}]}"
  done | text_prefix '  '

  echo
  echo "
    ENV:
      TARGET_REMOTE   Remote server to run configuration for (otherwise
                      current machine is used as the target). Also can
                      be configured in the configuration
  " | text_fmt
}

declare COMMAND
parse_command() {
  case "${1}" in
    # Pass through, it will be validated later
    -\?|-h|--help ) return ;;
    *             ) COMMAND="${1}" ;;
  esac

  [[ -n "${1+x}" ]] || {
    log_fuck <<< "COMMAND required."
    echo; print_help; return 2
  }

  # Make sure the command is without semicolon
  [[ -n "${COMMAND_TO_SHORT[${COMMAND}]+x}" ]] || {
    log_fuck <<< "Unsupported COMMAND: '${COMMAND}'."
    echo; print_help; return 2
  }
}

parse_command "${@}" || exit

#
# Target remote
#
TARGET_REMOTE_CONF="$(
  cat -- "$(pwd)/pve.conf.sh" 2>/dev/null \
  || cat -- "$(dirname -- "${0}")/pve.conf.sh" 2>/dev/null
)" && {
  # shellcheck disable=SC1090
  . <(cat <<< "${TARGET_REMOTE_CONF}")
}
# Export environment for target remote
# shellcheck disable=SC2034
TARGET_REMOTE_EXPORT='
  SELF_NAME
'
# {{ SOURCE=target-remote.sh /}}

######################
##### LXC_ACTION #####
######################

# The command is parsed, we can shift
shift

# {{ SOURCE=lxc/cmd/demo-conf.sh /}}
# {{ SOURCE=lxc/cmd/deploy.sh /}}
# {{ SOURCE=lxc/cmd/root-pass.sh /}}
# {{ SOURCE=lxc/cmd/user.sh /}}
