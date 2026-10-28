#!/bin/bash

set -u          # throws an error on unset variable expansion instead of expanding to ""
UNIT=gpu-switch # this is needed since the script invovles restarting the DE, which would kill the session, stopping this script.

SCRIPT_PATH=$(realpath $0)
SCRIPT_DIR=${SCRIPT_PATH%/*}

GPU="0000:$(head -1 ${SCRIPT_DIR}/info.txt | cut --delimiter=' ' --fields 1)"
AUD="0000:$(tail -1 ${SCRIPT_DIR}/info.txt | cut --delimiter=' ' --fields 1)"

GPU_HOST_DRIVER=$(head -1 ${SCRIPT_DIR}/info.txt | cut --delimiter=' ' --fields 2)
AUD_HOST_DRIVER=$(tail -1 ${SCRIPT_DIR}/info.txt | cut --delimiter=' ' --fields 2)

stop_desktop() {
    if ! systemctl --quiet is-active display-manager.service; then
        return 0
    fi
    systemctl stop display-manager.service #this only stops the login manager, not the active compositor instance

    # wait until DM is actually stopped
    for i in {1..10}; do
        if ! systemctl --quiet is-active display-manager.service; then
            break
        fi
        sleep 1
    done

    local session_id session_type sessions_user_id line
    while IFS= read -r line; do #
        session_id=$(awk '{print $1}' <<<$line)
        if [[ -z $session_id ]]; then continue; fi
        session_type=$(loginctl show-session "$session_id" -p Type --value 2>/dev/null)
        sessions_user_id=$(loginctl show-session "$session_id" -p User --value 2>/dev/null)
        if [[ "$session_type" == "x11" || "$session_type" == "wayland" ]]; then
            #loginctl terminate-session "$session_id" 2>/dev/null || true # avoiding crash in edge case where session ends before terminate-session does it
            #systemctl stop user@$sessions_user_id
            loginctl terminate-user "$sessions_user_id"
        fi
    done < <(loginctl list-sessions --no-legend 2>/dev/null)

}

start_desktop() {
    systemctl start display-manager.service
}

check_gpu_free() {
    nodes=()
    for i in /sys/bus/pci/devices/"$GPU"/drm/*; do
        #Extended Regular Expression
        if [[ $i =~ /(card|renderD)[0-9]+$ ]]; then
            #Globbing
            nodes+=("/dev/dri/${i##*/}")
        fi
    done

    if fuser -s "${nodes[@]}"; then
        echo "GPU is in use by: " >&2
        fuser -v "${nodes[@]}"
        return 1
    fi
    return 0
}

get_current_driver() {
    local link
    link=$(readlink "/sys/bus/pci/devices/$1/driver") || return ""
    basename "$link"
}

rebind() {
    local device=$1 driver=$2

    echo -n on >"/sys/bus/pci/devices/$device/power/control" #ensure device is not sleeping

    if [[ $(get_current_driver "$device") = "$driver" ]]; then
        return #no need to rebind
    fi

    if [[ -n $(get_current_driver "$device") ]]; then
        echo -n "$device" >"/sys/bus/pci/devices/$device/driver/unbind" #unbind current driver
    fi
    sleep 5
    echo -n $driver >"/sys/bus/pci/devices/$device/driver_override" #bind new driver
    echo -n $device >"/sys/bus/pci/drivers/$driver/bind"

    echo >"/sys/bus/pci/devices/$device/driver_override" #cleanup
}

rebind_nocheck() {
    local device=$1 driver=$2

    echo -n on >"/sys/bus/pci/devices/$device/power/control" #ensure device is not sleeping

    echo -n $device >"/sys/bus/pci/devices/$device/driver/unbind" #unbind current driver
    sleep 5
    echo -n $driver >"/sys/bus/pci/devices/$device/driver_override" #bind new driver
    echo -n $device >"/sys/bus/pci/drivers/$driver/bind"

    echo >"/sys/bus/pci/devices/$device/driver_override" #cleanup
}

switch_to_vfio() {
    modprobe vfio-pci
    if ! check_gpu_free; then
        stop_desktop
    fi
    rebind_nocheck "$AUD" "vfio-pci"
    rebind_nocheck "$GPU" "vfio-pci"
    start_desktop
}

switch_to_host() {
    modprobe "$GPU_HOST_DRIVER"
    modprobe "$AUD_HOST_DRIVER"
    stop_desktop
    rebind_nocheck "$GPU" "$GPU_HOST_DRIVER"
    rebind_nocheck "$AUD" "$AUD_HOST_DRIVER"
    start_desktop
}

# --collect unloads unit on end
# inside variable expansion ${VAR} ---> - means 'default for not set'. :- means 'default for not set or null'
if [[ -z ${EXECUTED_FROM_SYSTEMD_ENV-} ]]; then
    exec systemd-run --unit=$UNIT \
        --collect \
        --setenv=EXECUTED_FROM_SYSTEMD_ENV=1 \
        --working-directory="$SCRIPT_DIR" \
        "$SCRIPT_PATH" "$@"
    # exit 0            not need because of exec
fi

gpu_current_driver=$(get_current_driver "$GPU")
aud_current_driver=$(get_current_driver "$AUD")

if [[ -z ${1-} ]]; then
    #if state is rendering host
    if [[ $GPU_HOST_DRIVER = "$gpu_current_driver" && $AUD_HOST_DRIVER = "$aud_current_driver" ]]; then
        switch_to_vfio
    #if state is passthrough
    elif [[ "vfio-pci" = "$gpu_current_driver" && "vfio-pci" = "$aud_current_driver" ]]; then
        switch_to_host
    else
        echo "state is ambiguous, run with --to-vfio --to-host"
        exit 1
    fi
elif [[ $1 = "--to-vfio" ]]; then
    switch_to_vfio
elif [[ $1 = "--to-host" ]]; then
    switch_to_host
fi
