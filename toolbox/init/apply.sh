#!/usr/bin/env bash

INSTALL_DIR=/opt/varlog/init
BIN_DIR="${INSTALL_DIR}/bin"
HOOKS_DIR="${INSTALL_DIR}/hooks"

DL_TOOL_URL=https://raw.githubusercontent.com/varlogerr/pve/master/toolbox/init/init.sh
DL_KEEPOUT_URL=https://raw.githubusercontent.com/varlogerr/pve/master/toolbox/init/keepout.sh

apply() {
  install
  configure
}

_get_homes() {
  declare -a homes
  declare homes_txt; homes_txt="$(
    # shellcheck disable=SC1003
    find /home -mindepth 1 -maxdepth 1 -type d 2>/dev/null | grep '.'
  )" && mapfile -t homes <<< "${homes_txt}"

  printf -- '%s\n' "${homes[@]}" /root /etc/skel
}

install() {
  declare hooks_dir_repl; hooks_dir_repl="$(sed 's/\//\\&/g' <<< "${HOOKS_DIR}")"

  (set -x; mkdir -p "${BIN_DIR}" "${HOOKS_DIR}")
  (set -x; curl -sSL "${DL_TOOL_URL}") \
  | sed 's/{{\s*HOOKS_DIR\s*}}/'"${hooks_dir_repl}"'/g' \
  | (set -x; tee "${BIN_DIR}/init.sh" >/dev/null)
  (set -x; curl -sSL "${DL_KEEPOUT_URL}" -o "${BIN_DIR}/keepout.sh")
  (set -x; chmod 0755 "${BIN_DIR}"/*)
}

configure() {
  (set -x; ln -sf "${BIN_DIR}/init.sh" /root/init.sh)
}

(return 0 &>/dev/null) && return

apply
