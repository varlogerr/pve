# shellcheck disable=SC2120
{ : # {{ SNIP_SHLIB }}
  # @.log
  # @text_fmt
  # @text_prefix
  # @escape_sed_expr
  # @escape_sed_repl

  # Escape sed expression for basic regex.
  #
  # USAGE:
  #   escape_sed_expr FILE...
  #   escape_sed_expr <<< TEXT
  #
  # REFERENCES:
  #   * https://stackoverflow.com/a/2705678
  escape_sed_expr ()
  {
      {
          :
      };
      cat -- "${@}" | sed 's/[]\/$*.^[]/\\&/g'
  }

  # Escape sed replacement.
  #
  # USAGE:
  #   escape_sed_repl FILE...
  #   escape_sed_repl <<< TEXT
  #
  # REFERENCES:
  #   * https://stackoverflow.com/a/2705678
  escape_sed_repl ()
  {
      {
          :
      };
      cat -- "${@}" | sed 's/[\/&]/\\&/g'
  }

  # USAGE:
  #   [SHLIB_LOG_PREFIX] log_fuck FILE...
  #   [SHLIB_LOG_PREFIX] log_fuck <<< TEXT
  #
  # ENV:
  #   SHLIB_LOG_PREFIX  Custom log prefix, defaults to executor
  #                     filename (currently 'snippet.sh: ')
  log_fuck ()
  {
      {
          :
      };
      log_sth --what=FUCK -- "${@}"
  }

  # USAGE:
  #   [SHLIB_LOG_PREFIX] log_info FILE...
  #   [SHLIB_LOG_PREFIX] log_info <<< TEXT
  #
  # ENV:
  #   SHLIB_LOG_PREFIX  Custom log prefix, defaults to executor
  #                     filename (currently 'snippet.sh: ')
  log_info ()
  {
      {
          :
      };
      log_sth --what=INFO -- "${@}"
  }

  # Logger.
  #
  # USAGE:
  #   [SHLIB_LOG_PREFIX] log_sth [--what=''] FILE...
  #   [SHLIB_LOG_PREFIX] log_sth [--what=''] <<< TEXT
  #
  # ENV:
  #   SHLIB_LOG_PREFIX  Custom log prefix, defaults to executor
  #                     filename (currently 'snippet.sh: ')
  #
  # OPTIONS:
  #   --what  What to log
  #
  # DEMO:
  #   # Print with default prefix
  #   log_sth --what=ERROR 'Oh, no!' # STDERR: snippet.sh: [ERROR] Oh, no!
  log_sth ()
  {
      declare PREFIX;
      PREFIX="$(basename -- "${0}" 2>/dev/null)";
      PREFIX="${PREFIX:-snippet.sh}: ";
      {
          :
      };
      {
          declare -a ARG_FILE;
          declare -A OPT=([_endopts]=false [what]='');
          declare arg;
          while [[ -n "${1+x}" ]]; do
              ${OPT[_endopts]} && arg='*' || arg="${1}";
              case "${arg}" in
                  --)
                      OPT[_endopts]=true
                  ;;
                  --what=*)
                      OPT[what]="${1#*=}"
                  ;;
                  --what)
                      OPT[what]="${2}";
                      shift
                  ;;
                  *)
                      ARG_FILE+=("${1}")
                  ;;
              esac;
              shift;
          done
      };
      PREFIX="${SHLIB_LOG_PREFIX-${PREFIX}}";
      [[ -n "${OPT[what]}" ]] && PREFIX+="[${OPT[what]^^}] ";
      cat -- "${ARG_FILE[@]}" | text_prefix "${PREFIX}" 1>&2
  }

  # USAGE:
  #   [SHLIB_LOG_PREFIX] log_warn FILE...
  #   [SHLIB_LOG_PREFIX] log_warn <<< TEXT
  #
  # ENV:
  #   SHLIB_LOG_PREFIX  Custom log prefix, defaults to executor
  #                     filename (currently 'snippet.sh: ')
  log_warn ()
  {
      {
          :
      };
      log_sth --what=WARN -- "${@}"
  }

  # Format text.
  text_fmt ()
  {
      {
          :
      };
      declare text;
      text="$(cat -- "${@}")" || return;
      declare -i t_lines;
      t_lines="$(wc -l <<< "${text}")";
      declare -a rm_blanks=(grep -m1 -A "${t_lines}" -vx '\s*');
      text="$("${rm_blanks[@]}" <<< "${text}"     | tac | "${rm_blanks[@]}" | tac | grep '')" || return 0;
      declare offset;
      offset="$(sed -e '1!d' -e 's/^\(\s*\).*/\1/' <<< "${text}" | wc -m)";
      sed -e 's/^\s\{0,'$(( offset - 1 ))'\}//' -e 's/\s\+$//' <<< "${text}"
  }

  # Prefix text.
  #
  # USAGE:
  #   text_prefix PREFIX FILE...
  #   text_prefix [PREFIX=''] <<< TEXT
  #
  # DEMO:
  #   text_prefix '[pref] ' <<< 'My text.'  # STDOUT: [pref] My text.
  text_prefix ()
  {
      {
          :
      };
      declare prefix="${1}";
      declare escaped;
      escaped="$(escape_sed_expr <<< "${prefix}")";
      cat -- "${@:2}" | sed 's/^/'"${escaped}"'/'
  }
} # {{ SNIP_SHLIB }}
