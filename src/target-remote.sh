# Ensure some hard to reproduce and meaningless first arg for marker
TARGET_REMOTE_MARKER='s?NXs#{Bb8}ir:4ehUok633iQ0>k5uM~'

[[ "${1}" == "${TARGET_REMOTE_MARKER}" ]] && {
  # It is a remote, prevent recursion
  unset TARGET_REMOTE; shift
}

while [[ -n "${TARGET_REMOTE+x}" ]]; do
  #
  # Launch on remote from local machine
  #

  escape_dq() { sed -e 's/"/\\"/g' -e 's/^/"/' -e 's/$/"/'; }

  TARGET_REMOTE_ARGS=(); for arg in "${@}"; do
    # shellcheck disable=SC2001
    TARGET_REMOTE_ARGS+=("$(escape_dq <<< "${arg}")")
  done

  TARGET_REMOTE_EXPORT_EXPR="$(
    grep -vx '^\s*$' <<< "${TARGET_REMOTE_EXPORT}" \
    | while read -r varname; do
      [[ -n "${!varname+x}" ]] || {
        echo "[WARN] ${varname} from TARGET_REMOTE_EXPORT seems to be undefined." >&2
        continue
      }
      value="${!varname}"
      echo "${varname}=$(escape_dq <<< "${value}"); export ${varname}"
    done
  )"

  # shellcheck disable=SC2016
  # shellcheck disable=SC1004
  echo '
    tmp="$(mktemp)"; chmod 0700 "${tmp}"
    base64 -d <<< "'"$(base64 -- "${0}")"'" > "${tmp}"

    '"${TARGET_REMOTE_EXPORT_EXPR}"'
    "${tmp}" "'"${TARGET_REMOTE_MARKER}"'" '"${TARGET_REMOTE_ARGS[*]}"'
    RC=$?

    rm -f "${tmp}"
    exit ${RC}
  ' | ssh "${TARGET_REMOTE}" bash -s

  exit
done
