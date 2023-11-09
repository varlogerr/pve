#!/usr/bin/env bash

FZF_RELEASE="${FZF_RELEASE-0.44.0}"
CLEANUP=false

declare -a DEPS=(epel-release)
declare -a PKGS=(
  # rsync speedtest
  bind-utils gzip htop jq less nano neovim net-tools
  tar telnet tmux tree unzip wget
  bash-completion man-pages
)

apply() {
  install_basic
  install_fzf
  cleanup
}

cleanup() {
  ${CLEANUP} || return 0
  dnf -y autoremove && dnf -y --enablerepo='*' clean all
}

_get_homes() {
  declare -a homes
  declare homes_txt; homes_txt="$(
    # shellcheck disable=SC1003
    find /home -mindepth 1 -maxdepth 1 -type d 2>/dev/null | grep '.'
  )" && mapfile -t homes <<< "${homes_txt}"

  printf -- '%s\n' "${homes[@]}" /root /etc/skel
}

install_basic() {
  declare to_install; to_install="$(printf -- '%s\n' "${PKGS[@]}" \
    | grep -vFxf <(dnf list installed | cut -d'.' -f1) | grep '.'
  )" && {
    CLEANUP=true

    mapfile -t PKGS <<< "${to_install}"
    (set -x; dnf install -y "${DEPS[@]}" && dnf install -y "${PKGS[@]}")
  }

  configure_tmux
  symlink_nvim
}

configure_tmux() {
  declare DL_URL=https://raw.githubusercontent.com/varlogerr/pve/master/toolbox/basic-tools/basic.conf
  declare -a HOMES; mapfile -t HOMES <<< "$(_get_homes)"
  declare CONF_DIR=/etc/tmux
  declare CONF_FILE="${CONF_DIR}/basic.conf"

  (set -x; mkdir -p "${CONF_DIR}"; curl -sSLo "${CONF_FILE}" "${DL_URL}")
  declare home; for home in "${HOMES[@]}"; do
    (set -x; ln -s "${CONF_DIR}/basic.conf" "${home}/.tmux.conf" 2>/dev/null)
  done
}

symlink_nvim() {
  (set -x; ln -s /usr/bin/nvim /usr/bin/vim 2>/dev/null)
}

install_fzf() {
  declare DL_SRC_URL=https://api.github.com/repos/junegunn/fzf/tarball/${FZF_RELEASE}
  declare DL_BIN_URL=https://github.com/junegunn/fzf/releases/download/${FZF_RELEASE}/fzf-${FZF_RELEASE}-linux_amd64.tar.gz
  declare INSTALL_DIR=/opt/junegunn/fzf
  declare version_line; version_line="$("${INSTALL_DIR}/bin/fzf" --version 2>/dev/null | head -n 1)"

  [[ " ${version_line} " == *" ${FZF_RELEASE} "* ]] || {
    # Reset install dir
    (set -x; rm -rf -- "${INSTALL_DIR}"; mkdir -p -- "${INSTALL_DIR}")

    # Install hooks
    declare tmp; tmp="$(set -x; mktemp -d)"
    (set -x; curl -sSL "${DL_SRC_URL}") | tar -xzf - -C "${tmp}" \
      && (set -x; mv "${tmp}"/*/shell "${INSTALL_DIR}")
    (set -x; rm -rf -- "${tmp}")

    # Install bin
    ( set -x; mkdir -p "${INSTALL_DIR}/bin"
      curl -sSL "${DL_BIN_URL}" | tar -xzf - -C "${INSTALL_DIR}/bin")
  }

  # Configure
  declare DL_URL=https://raw.githubusercontent.com/varlogerr/pve/master/toolbox/basic-tools/fzf.bash
  declare -a homes; mapfile -t homes <<< "$(_get_homes)"
  declare install_dir_repl; install_dir_repl="$(sed 's/\//\\&/g' <<< "${INSTALL_DIR}")"

  (set -x; curl -sSL "${DL_URL}") \
  | sed 's/{{\s*install_dir\s*}}/'"${install_dir_repl}"'/g' \
  | (set -x; tee -- "${INSTALL_DIR}/hook.bash" >/dev/null)

  declare rc_file
  declare home; for home in "${homes[@]}"; do
    rc_file="${home}/.bashrc"
    sed -i '/#\s*{{\s*fzf\/hook\.bash\s*\/}}\s*$/d' "${rc_file}"
    echo ". '${INSTALL_DIR}/hook.bash' # {{ fzf/hook.bash /}}" | (set -x; tee -a "${rc_file}" >/dev/null)
  done
}

(return 0 &>/dev/null) && return

apply
