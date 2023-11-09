# PATH
[[ ":${PATH}:" == *':{{ install_dir }}/bin:'* ]] || {
  PATH+=':{{ install_dir }}/bin'
}

# Auto-completion
# ---------------
[[ $- == *i* ]] && . '{{ install_dir }}/shell/completion.bash' 2> /dev/null

# Key bindings
# ------------
. '{{ install_dir }}/shell/key-bindings.bash' 2> /dev/null

__iife() {
  local -a opts

  opts+=(--height '100%')
  opts+=(--border)
  opts+=(--history-size 999999)
  # https://github.com/junegunn/fzf/issues/577#issuecomment-225953097
  opts+=(--preview "'echo {}'" --bind ctrl-p:toggle-preview)
  opts+=(--preview-window down:50%:wrap)

  FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS:+ }$(printf -- '%s ' "${opts[@]}" | sed -E 's/\s+$//')"
}; __iife; unset __iife
