#!/usr/bin/env bash

MARIADB_VERSION="${MARIADB_VERSION-11.1}"
PHP_VERSION="${PHP_VERSION-8.1}"
CLEANUP=false

apply() {
  install_apache
  configure_apache
  install_php
  configure_php_apache
  install_mariadb
  cleanup
}

cleanup() {
  ${CLEANUP} || return 0
  dnf -y autoremove && dnf -y --enablerepo='*' clean all
}

install_apache() {
  declare -a pkgs=(httpd mod_ssl)
  declare service=httpd

  declare to_install; to_install="$(printf -- '%s\n' "${pkgs[@]}" \
    | grep -vFxf <(dnf list installed | cut -d'.' -f1) | grep '.'
  )" && {
    CLEANUP=true

    mapfile -t pkgs <<< "${to_install}"
    (set -x; dnf install -y "${pkgs[@]}")
  }

  # shellcheck disable=SC2015
  systemctl is-active --quiet "${service}" \
  && systemctl is-enabled --quiet "${service}" \
  || (set -x; systemctl enable --now "${service}")
}

configure_apache() (
  # Allow default ports
  set -x
  firewall-cmd --permanent --add-port=80/tcp 2>/dev/null
  firewall-cmd --permanent --add-port=443/tcp 2>/dev/null
  firewall-cmd --reload 2>/dev/null
)

install_php() {
  declare version_expr
  # shellcheck disable=SC2001
  version_expr="$(sed 's/\./\\&/g' <<< "${PHP_VERSION}")"

  printf --  ' %s ' "$(php --version 2>/dev/null | head -n 1)" \
  | grep -q " ${version_expr}\\.[0-9]\\+ " || {
    CLEANUP=true

    declare -a repos=(
      https://dl.fedoraproject.org/pub/epel/epel-release-latest-"$(rpm -E '%{rhel}')".noarch.rpm
      https://rpms.remirepo.net/enterprise/remi-release-"$(rpm -E '%{rhel}')".rpm
    )
    declare -a pkgs=(
      php php-cli php-gd php-intl php-mbstring php-mcrypt
      php-mysqlnd php-pecl-redis5 php-pecl-zip php-pdo php-xml
    )

    ( set -x
      dnf install -y "${repos[@]}" \
      && dnf module reset -y php \
      && dnf module install -y php:remi-${PHP_VERSION} \
      && dnf -y install "${pkgs[@]}"
    )
  }
}

configure_php_apache() (
  declare mpm_conffile; mpm_conffile="$(find /etc/httpd -name '*-mpm.conf' | head -n 1)"
  set -x
  sed -i -e 's/^\([^#]\)/#\1/' -e 's/^#\(LoadModule\s.\+mpm_prefork.so\)$/\1/' "${mpm_conffile}"
)

install_mariadb() {
  declare REPO_URL=https://raw.githubusercontent.com/varlogerr/pve/master/toolbox/apiportal-prereq/mariadb.repo
  declare pkg=mariadb-server
  declare service=mariadb

  (set -x; curl -sSL "${REPO_URL}") | sed 's/{{\s*VERSION\s*}}/'"${MARIADB_VERSION}"'/g' \
  | (set -x; tee /etc/yum.repos.d/mariadb.repo >/dev/null)

  dnf list installed | grep -qi "^${pkg}\." || {
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
