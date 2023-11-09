if [[ "${COMMAND}" == deploy ]]; then
  { # Stages
    tpl_cache() {
      declare -gA TPLS_CACHE

      [[ -n "${TPLS_CACHE[${TEMPLATE}]}" ]] || {
        declare tpl_expr; tpl_expr="$(escape_sed_expr <<< "${TEMPLATE}")"
        declare tpls_url_repl; tpls_url_repl="$(escape_sed_repl <<< "${TPLS_URL}")"

        log_info <<< "Getting download URL for template: '${TEMPLATE}'."
        declare tpl_url; tpl_url="$(set -o pipefail
          dl_to_stdout "${TPLS_URL}" \
          | sed -n 's/.*href="\('"${tpl_expr}"'[^"]*\.tar\.\(gz\|xz\|zst\)\)".*/\1/p' \
          | sort -V | tail -n 1 | grep '' | sed 's/^/'"${tpls_url_repl}"'\//'
        )" || { log_fuck <<< "Can't detect download URL."; return 1; }

        log_info <<< "Downloading template: '${tpl_url}'."
        declare tmp; tmp="$(mktemp --suffix "-${tpl_url##*/}")" || {
          log_fuck <<< "Can't create tmp file."
          return 1
        }

        dl_to_stdout "${tpl_url}" > "${tmp}" || {
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

      log_info <<< "Reading password file."
      declare pass; pass="$(set -x
        cd -- "${CONF[secret_dir]}" 2>/dev/null && {
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

  CONF_PART="$(grep -xF -m1 -B999 '##### END OF CONF #####' -- "${0}" | sed '$ d')"

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
    # Ensure they are not unset
    # shellcheck disable=SC2034
    readonly PATH
    unset_vars="$(
      while read -r v; do
        unset -v "${v}" &>/dev/null
      done <<< "$(set -o posix; set \
        | grep -io '^\([[:alnum:]]\|_\)\+=' | sed 's/=$//'
      )"

      # shellcheck disable=SC1090
      . <("${0}" demo-conf)

      # https://askubuntu.com/a/275972
      set -o posix; set | grep -io '^\([[:alnum:]]\|_\)\+=' \
      | sed 's/=$//'
    )"
    for block in "${CONF_BLOCKS[@]}"; do
      # Ensure configuration doesn't come from environment or previous iteration
      # shellcheck disable=SC2046
      unset -v $(echo "${unset_vars}" | xargs) &>/dev/null

      # shellcheck disable=SC1090
      . <(cat <<< "${block}")

      # Check LXC id already in use
      id_expr="$(escape_sed_expr <<< "${ID}")"
      if pct list | sed '1 d' | grep -q "^${id_expr}[^0-9]"; then
        log_info <<< "LXC already exists: '${ID}'."
      else
        # Exports TPLS_CACHE
        tpl_cache
        trap_preset password || { log_warn <<< "Skipping: '${ID}'."; continue; }

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
fi
