if [[ "${COMMAND}" == demo-conf ]]; then
  print_demo_conf_help() {
    echo "
      Print LXC deployment configuration demo to stdout.

      USAGE:
        ${SELF_NAME} ${COMMAND}
    " | text_fmt
  }

  while [[ -n "${1+x}" ]]; do
    case "${1}" in
      -\?|-h|--help   ) print_demo_conf_help; exit ;;
    esac
    shift
  done

  # TODO: complete the self documentation
  echo "
    # Uncomment and configure TARGET_REMOTE to execute the configuration
    # against remote Proxmox machine. Alternatively:
    # \`\`\`sh
    # echo 'TARGET_REMOTE=root@192.168.96.69' >> pve.conf.sh
    # \`\`\`
    # The script will apply it if it's in the same directory where it is
    # or in the \${PWD}
    #
    # shellcheck disable=SC2034
    # TARGET_REMOTE=root@192.168.96.69

    {
      # Requirements, limitations and guidance:
      # ======================================
      # * Each configuration block must:
      #   * start with '^\s*{.*$'
      #   * end with '^.*}\s\+#\s*HOSTNAME=[^ ]\+\s*$'
      # * Variables don't override each other when they are in different blocks
      #   (see the list of supported vars below).
      # * Multiple blocks are allowed. That's one of the ways to keep multiple
      #   configurations in one file.
      # * Code outside configuration blocks is not evaluated for configuration.
      #   I.e. you can't factor out a common setting outside a configuration block.
      # * The following fields are required:
      #   * ID            - immutable after the container creation
      #   * TEMPLATE      - immutable after the container creation
      #   * UNPRIVILEGED  - immutable after the container creation
      #   * ROOT_PASS
      # * With any setting but required ones removed or set to empty they won't be
      #   applied.
      #
      # The basic idea of presets is:
      # * To hide some sensitive information about your infra. Same can be
      #   easily achieved with \`. <(cat CONTAINER_ID)\`.
      # * To simplify some configurations
      #
      # Available presets:
      # =================
      # * password - configure container root password from a file in the
      #   filesystem. When enabled, ROOT_PASS is ignored. The password files
      #   (plain text or encoded with \`openssl passwd -5 \"\${PASS}\"\`) are
      #   search in the '${CONF[secret_dir]}' directory with the following
      #   precedence: \"\${CONTAINER_ID}.root.pass\", \"master.root.pass\",
      #   \"root.pass\".
      # * net - same as password, but the searched files are
      #   \"\${CONTAINER_ID}.net.sh\", \"master.net.sh\", and \"net.sh\", and their
      #   contents is expected to be of 2 optional variables IP=\"...\" and
      #   GATEWAY=\"...\". You can declare more, but it's it's better to keep the
      #   convention. It's convenient to declare IP in the container file and
      #   GATEWAY in 'net.sh' to avoid duplication.
      # * net - same as 'password', but the searched files are
      #   \"\${CONTAINER_ID}.net.sh\", \"master.net.sh\", and \"net.sh\", and their
      #   contents is expected to be of 2 optional variables IP=\"...\" and
      #   GATEWAY=\"...\". You can declare more, but it's it's better to keep the
      #   convention. It's convenient to declare IP in the container file and
      #   GATEWAY in 'net.sh' to avoid duplication.
      # * user - same as with 'net', file suffix is \"user.sh\", expected vars are:
      #   USER_NAME, USER_UID, USER_PASS, USER_GID, USER_GROUP, USER_HOME. Without
      #   USER_NAME other settings are ignored and user is not created. USER_PASS
      #   value can be encrypted (see 'password' preset) or plain text.
      # * docker - configures the container to work with containers, no additional
      #   settings on the file system level. It manipulates lxc conf files.
      # * vpn - same as 'docker', but configures for VPN server.
      #
      # Hooks:
      # =====
      # ${SELF_NAME} by default creates a hook named \"\${CONTAINER_ID}\".conf
      # in the
      #
      NAME=sendbox.portal.local
      ID=169
      TEMPLATE=ubuntu-22.04
      UNPRIVILEGED=1
      ROOT_PASS=changeme    # Can be overriden by 'password' preset
      STORAGE=local-lvm
      ONBOOT=1
      CORES=2
      MEMORY=2048
      DISK=15G
      GATEWAY=192.168.0.1   # Can be overriden by 'net' preset
      IP=192.168.0.69/24
      USER_NAME=foo         # Can be overriden by 'user' preset
      USER_PASS=qwerty
      USER_GROUP=foo
      USER_UID=1001
      USER_GID=1002
      USER_HOME=/home/foo
      PRESETS=(docker vpn)
      BIND_MOUNT=(
        # Format: 'HOST_DIR:LXC_DIR'
        '/home/father/porn:/mnt/share/kids/cartoons'
      )
    } # {{ PVE_PLACEHOLDER=demo.local /}}
  " | text_fmt | sed 's/PVE_PLACEHOLDER/LXC_HOSTNAME/'
fi
