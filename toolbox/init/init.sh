#!/usr/bin/env bash

hooks_txt="$(
  find '{{ HOOKS_DIR }}' -type f -name 'hook.sh' | grep '.'
)" || exit

declare -a hooks; mapfile -t hooks <<< "${hooks_txt}"
for hook in "${hooks[@]}"; do
  bash "${hook}"
done
