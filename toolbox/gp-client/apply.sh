#!/usr/bin/env bash

declare -a DEPS=(tar gzip)
CLEANUP=false

apply() {
  install
  cleanup
}

cleanup() {
  ${CLEANUP} || return 0
  dnf -y autoremove && dnf -y --enablerepo='*' clean all
}

install() {
  dnf list installed | grep -q '^globalprotect\.' && return 0

  CLEANUP=true
  declare DL_URL=https://raw.githubusercontent.com/varlogerr/pve/master/toolbox/gp-client/installer.tar.gz
  declare TMP; TMP="$(set -x; mktemp -d)"

  ( set -x
    dnf install -y "${DEPS[@]}"
    curl -sSL "${DL_URL}" | tar -xzf - -C "${TMP}"
    dnf install -y "${TMP}"/*.rpm
    rm -rf "${TMP}"
    dnf -y autoremove && dnf -y --enablerepo='*' clean all
  )
}

(return 0 &>/dev/null) && return

apply
