#!/usr/bin/env bash

DOCROOT="$(dirname -- "${0}")"
. "${DOCROOT}/src/shlib.sh"

declare -a source_lines
source_expr='\s*#\s*{{\s*SOURCE=\([^ ]\+\)\s*\/}}\s*'
for tpl in "${DOCROOT}/src"/*.tpl.sh; do
  DEST="${DOCROOT}/bin/$(basename -s '.tpl.sh' -- "${tpl}").sh"
  TPL_BODY="$(cat -- "${tpl}")"

  log_info <<< "Building: '${DEST}'."

  # In reverse order
  source_lines_txt="$(set -o pipefail
    grep -nx -- "${source_expr}" <<< "${TPL_BODY}" \
    | sed 's/^\([0-9]\+:\)'"${source_expr}"'/\1\2/' | tac
  )" || continue
  mapfile -t source_lines <<< "${source_lines_txt}"

  for s_line in "${source_lines[@]}"; do
    LINE="${s_line%%:*}"
    INC="${s_line#*:}"

    TPL_BODY="$(
      head -n "$(( LINE - 1 ))" <<< "${TPL_BODY}"
      cat -- "${DOCROOT}/src/${INC}"
      tail -n +"$(( LINE + 1 ))" <<< "${TPL_BODY}"
    )"
  done

  DEST_BODY="$(cat -- "${DEST}")"
  BODY_END_LINE="$(grep -m1 -nFx '##### END OF CONF #####' <<< "${DEST_BODY}" | cut -d':' -f1)"

  DEST_BODY="$(
    head -n "${BODY_END_LINE}" <<< "${DEST_BODY}"
    sed -n "$(( BODY_END_LINE + 1 ))p" <<< "${DEST_BODY}"
    echo
    echo "${TPL_BODY}"
  )"

  echo "${DEST_BODY}" > "${DEST}"

  log_info <<< "Done: '${DEST}'."
done

