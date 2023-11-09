#!/usr/bin/env bash

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
  declare pkg=openssh-server
  declare service=sshd

  dnf list installed | grep -qi "^${pkg}\\." || {
    CLEANUP=true
    (set -x; dnf install -y "${pkg}")
  }

  # shellcheck disable=SC2015
  systemctl is-active --quiet "${service}" \
  && systemctl is-enabled --quiet "${service}" \
  || (set -x; systemctl enable --now "${service}")
}

(return 0 &>/dev/null) && return

apply
