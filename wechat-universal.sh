#!/bin/bash
XDG_DOCUMENTS_DIR="${XDG_DOCUMENTS_DIR:-$(xdg-user-dir DOCUMENTS)}"
if [[ -z "${XDG_DOCUMENTS_DIR}" ]]; then
    echo 'Error: Failed to get XDG_DOCUMENTS_DIR, refuse to continue'
    exit 1
fi
export XAUTHORITY="${XAUTHORITY:-${HOME}/.Xauthority}"
WECHAT_DATA_DIR="$(readlink -f -- "${WECHAT_DATA_DIR:-${XDG_DOCUMENTS_DIR}/WeChat_Data}")"
WECHAT_FILES_DIR="${WECHAT_DATA_DIR}/xwechat_files"
WECHAT_HOME_DIR="${WECHAT_DATA_DIR}/home"

env_add() {
    BWRAP_ENV_APPEND+=(--setenv "$1" "$2")
}
BWRAP_ENV_APPEND=()
# wechat-universal only supports xcb
env_add QT_QPA_PLATFORM xcb
env_add PATH "/sandbox:${PATH}"
env_add LC_ALL C

dir_add() {
  BWRAP_DIR_APPEND+=(--bind "$1" "$2")
}
BWRAP_DIR_APPEND=()
# example: WECHAT_CUSTOM_DIRS="${HOME}/Desktop ${HOME}/Desktop:${HOME}/Downloads ${HOME}/Downloads"
if [ ! -z "${WECHAT_CUSTOM_DIRS}" ]; then
  for dir in $(IFS=':';echo ${WECHAT_CUSTOM_DIRS}); do
    src="$(readlink -f ${dir%%" "*})"
    dest="$(readlink -f ${dir##*" "})"
    mkdir -p "${src}"
    dir_add "${src}" "${dest}"
  done
fi

case "${XMODIFIERS}" in 
    *@im=fcitx*)
        echo "Workaround for fcitx applied"
        env_add QT_IM_MODULE fcitx
        env_add GTK_IM_MODULE fcitx    
        ;;
    *@im=ibus*)
        echo "Workaround for ibus applied"
        env_add QT_IM_MODULE ibus
        env_add GTK_IM_MODULE ibus
        env_add IBUS_USE_PORTAL 1
        ;;
esac

BWRAP_DEV_BINDS=()
for DEV_NODE in /dev/{nvidia{-uvm,ctl,*[0-9]},video*[0-9]}; do
    [[ -e "${DEV_NODE}" ]] && BWRAP_DEV_BINDS+=(--dev-bind "${DEV_NODE}"{,})
done

mkdir -p "${WECHAT_FILES_DIR}" "${WECHAT_HOME_DIR}"
ln -snf "${WECHAT_FILES_DIR}" "${WECHAT_HOME_DIR}/xwechat_files"

BWRAP_ARGS=(
    # Drop privileges
    --unshare-all
    --share-net
    --cap-drop ALL
    --die-with-parent

    # /usr
    --ro-bind /usr{,}
    --symlink usr/lib /lib
    --symlink usr/lib /lib64
    --symlink usr/bin /bin
    --symlink usr/bin /sbin
    --bind /usr/bin/{true,lsblk}

    # /sandbox
    --ro-bind /{usr/lib/flatpak-xdg-utils,sandbox}/xdg-open
    --ro-bind /{usr/share/wechat-universal/usr/bin,sandbox}/dde-file-manager

    # /dev
    --dev /dev
    --dev-bind /dev/dri{,}
    --tmpfs /dev/shm

    # /proc
    --proc /proc

    # /etc
    --ro-bind /etc/machine-id{,}
    --ro-bind /etc/passwd{,}
    --ro-bind /etc/nsswitch.conf{,}
    --ro-bind /etc/resolv.conf{,}
    --ro-bind /etc/localtime{,}
    --ro-bind-try /etc/fonts{,}

    # /sys
    --dir /sys/dev # hack for Intel / AMD graphics, mesa calling virtual nodes needs /sys/dev being 0755
    --ro-bind /sys/dev/char{,}
    --ro-bind /sys/devices{,}

    # /tmp
    --tmpfs /tmp

    # /opt, Wechat-beta itself
    --ro-bind /opt/wechat-universal{,}

    # license fixups in various places
    --ro-bind {/usr/share/wechat-universal,}/usr/lib/license
    --ro-bind {/usr/share/wechat-universal,}/var/
    --ro-bind {/usr/share/wechat-universal,}/etc/os-release
    --ro-bind {/usr/share/wechat-universal,}/etc/lsb-release

    # /home
    --bind "${WECHAT_HOME_DIR}" "${HOME}"
    --bind "${WECHAT_FILES_DIR}"{,}
    --bind-try "${HOME}/.pki"{,}
    --ro-bind-try "${HOME}/.fontconfig"{,}
    --ro-bind-try "${HOME}/.fonts"{,}
    --ro-bind-try "${HOME}/.config/fontconfig"{,}
    --ro-bind-try "${HOME}/.local/share/fonts"{,}
    --ro-bind-try "${HOME}/.icons"{,}
    --ro-bind-try "${HOME}/.local/share/.icons"{,}

    # /run
    --dev-bind /run/dbus{,}
    --ro-bind /run/systemd/userdb{,}
    --ro-bind-try "${XAUTHORITY}"{,}
    --ro-bind "${XDG_RUNTIME_DIR}/bus"{,}
    --ro-bind "${XDG_RUNTIME_DIR}/pulse"{,}
)

exec bwrap "${BWRAP_ARGS[@]}" "${BWRAP_DEV_BINDS[@]}" "${BWRAP_DIR_APPEND[@]}" "${BWRAP_ENV_APPEND[@]}" /opt/wechat-universal/wechat "$@"