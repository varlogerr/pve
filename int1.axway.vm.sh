#!/usr/bin/env bash

TARGET_REMOTE=root@192.168.69.95

# Ensure some hard to reproduce and meaningless first arg for marker
TARGET_REMOTE_MARKER='s?NXs#{Bb8}ir:4ehUok633iQ0>k5uM~'

[[ "${1}" == "${TARGET_REMOTE_MARKER}" ]] && {
  # It is a remote, prevent recursion
  unset TARGET_REMOTE; shift

  TEMPLATE=almalinux-9-default_20221108_amd64.tar.xz
  TPLS_URL=http://download.proxmox.com/images/system

  TPL_FILE="$(set -x; mktemp --suffix .image.tar.xz)"
  (set -x; curl -kLsS "${TPLS_URL}/${TEMPLATE}" | tee -- "${TPL_FILE}" >/dev/null)

  (set -x
    # Create container
    pct create "141" \
      "${TPL_FILE}" \
      -storage "local-lvm" \
      -unprivileged 0 \
      -password "changeme"
  ) 3>&2 2>&1 1>&3 \
  | sed 's/\(\s-password\)\( .\+\)/\1 *****/' 3>&2 2>&1 1>&3

  rm -f tmp
}

[[ -n "${TARGET_REMOTE+x}" ]] || exit 0

#
# Launch on remote from local machine
#

escape_dq() { sed -e 's/"/\\"/g' -e 's/^/"/' -e 's/$/"/'; }

TARGET_REMOTE_ARGS=(); for arg in "${@}"; do
  # shellcheck disable=SC2001
  TARGET_REMOTE_ARGS+=("$(escape_dq <<< "${arg}")")
done

# shellcheck disable=SC2016
# shellcheck disable=SC1004
echo '
  tmp="$(mktemp)"; chmod 0700 "${tmp}"
  base64 -d <<< "'"$(base64 -- "${0}")"'" > "${tmp}"

  "${tmp}" "'"${TARGET_REMOTE_MARKER}"'" '"${TARGET_REMOTE_ARGS[*]}"'
  RC=$?

  rm -f "${tmp}"
  exit ${RC}
' | ssh "${TARGET_REMOTE}" bash -s
