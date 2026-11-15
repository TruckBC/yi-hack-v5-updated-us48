#!/bin/sh

# 0.4.1j

script_name=$(basename -- "$0")

if pidof "$script_name" -o $$ >/dev/null;then
   echo "Already Running - Quitting"
   exit 1
fi

CONF_FILE="etc/system.conf"

YI_HACK_PREFIX="/tmp/sd/yi-hack-v5"
MODEL_SUFFIX=$(cat /home/app/.camver)

LOG_FILE="/tmp/sd/wd_rtsp.log"
#LOG_FILE="/dev/null"

get_config()
{
    key=$1
    grep -w $1 $YI_HACK_PREFIX/$CONF_FILE | cut -d "=" -f2 | awk 'NR==1 {print; exit}'
}

COUNTER=0
COUNTER_LIMIT=10
INTERVAL=10

if [[ "$(get_config USERNAME)" != "" ]] ; then
    USERNAME=$(get_config USERNAME)
    PASSWORD=$(get_config PASSWORD)
fi

RRTSP_RES=$(get_config RTSP_STREAM)
RRTSP_AUDIO=$(get_config RTSP_AUDIO)
RRTSP_MODEL=$MODEL_SUFFIX
RRTSP_PORT=$(get_config RTSP_PORT)
if [ ! -z $USERNAME ]; then
    RRTSP_USER="-u $USERNAME"
fi
if [ ! -z $PASSWORD ]; then
    RRTSP_PWD="-w $PASSWORD"
fi

restart_rtsp()
{
    killall -q rRTSPServer
    rRTSPServer -r $RRTSP_RES -a $RRTSP_AUDIO -p $RRTSP_PORT $RRTSP_USER $RRTSP_PWD &
}

restart_grabber()
{
    killall -q rRTSPServer
    killall -q h264grabber
    if [[ $(get_config RTSP_STREAM) == "low" ]]; then
        h264grabber -r low -m $MODEL_SUFFIX -f &
    fi
    if [[ $(get_config RTSP_STREAM) == "high" ]]; then
        h264grabber -r high -m $MODEL_SUFFIX -f &
    fi
    if [[ $(get_config RTSP_STREAM) == "both" ]]; then
        h264grabber -r low -m $MODEL_SUFFIX -f &
        h264grabber -r high -m $MODEL_SUFFIX -f &
    fi
    if [[ $(get_config RTSP_AUDIO) == "yes" ]]; then
        h264grabber -r AUDIO -m $MODEL_SUFFIX -f &
    fi
    rRTSPServer -r $RRTSP_RES -a $RRTSP_AUDIO -p $RRTSP_PORT $RRTSP_USER $RRTSP_PWD &
}

restart_cloud()
{
    if [[ $(get_config DISABLE_CLOUD) == "yes" ]] ; then
    (
        cd /home/app || exit 1
        ./cloud &
    )
    fi
}

restart_mqttv4()
{
    mqttv4 &
}

check_rtsp()
{
    SOCKET=`/bin/netstat -an 2>&1 | grep ":$RRTSP_PORT " | grep LISTEN | grep -c ^`
    PID=`pidof rRTSPServer | awk '{print $1}'`

    if [ -z "$PID" ]; then
        echo "$(date +'%Y-%m-%d %H:%M:%S') - No running processes, restarting rRTSPServer ..." >> $LOG_FILE
        killall -q rRTSPServer
        sleep 1
        restart_rtsp
        COUNTER=0
        return
    fi

    # Robust lock detection: measure the CPU time consumed by rRTSPServer
    # between two checks, reading the process CPU jiffies directly from /proc.
    # A stalled rRTSPServer (LIVE555 blocked on a dead client, delivering 0
    # bytes to new PLAY requests) consumes no CPU at all. The previous
    # 'top'-based check was too flaky: single-sample CPU flickered between
    # 0.0 and >0 so the lock counter never reached the restart threshold.
    # Only treat zero CPU as a lock while at least one client connection is
    # established on the RTSP port. With no clients the server idles at 0%
    # CPU, which is healthy and must not trigger a restart.
    CLIENTS=`/bin/netstat -an 2>&1 | grep ":$RRTSP_PORT " | grep -c ESTABLISHED`
    if [ $CLIENTS -eq 0 ]; then
        COUNTER=0
        LAST_UTIME=
        return
    fi

    UTIME=`awk '{print $14+$15}' /proc/$PID/stat 2>/dev/null`
    if [ -z "$UTIME" ]; then
        return
    fi
    if [ ! -z "$LAST_UTIME" ]; then
        DELTA=$((UTIME-LAST_UTIME))
        if [ $DELTA -lt 0 ]; then
            # rRTSPServer was restarted mid-measurement; re-baseline
            LAST_UTIME=$UTIME
            return
        fi
        if [ $DELTA -le 0 ]; then
            COUNTER=$((COUNTER+1))
            echo "$(date +'%Y-%m-%d %H:%M:%S') - Detected possible locked process ($COUNTER, delta=$DELTA)" >> $LOG_FILE
            if [ $COUNTER -ge $COUNTER_LIMIT ]; then
                echo "$(date +'%Y-%m-%d %H:%M:%S') - Restarting rtsp process" >> $LOG_FILE
                killall -q rRTSPServer
                sleep 1
                restart_rtsp
                COUNTER=0
                LAST_UTIME=
                return
           fi
        else
            if [ $COUNTER -gt 0 ]; then
                echo "$(date +'%Y-%m-%d %H:%M:%S') - Lock cleared (delta=$DELTA)" >> $LOG_FILE
            fi
            COUNTER=0
        fi
    fi
    LAST_UTIME=$UTIME
}

check_cloud()
{
    CPU=`top -b -n 1 | grep cloud | grep -v grep | tail -n 1 | awk '{print $8}'`
    if [[ $(get_config DISABLE_CLOUD) == "yes" ]] ; then
    (
    if [ "$CPU" == "" ]; then
        echo "$(date +'%Y-%m-%d %H:%M:%S') - No running processes, restarting ./cloud & ..." >> $LOG_FILE
        restart_cloud
        COUNTER=0
    fi
    )
    fi
}

check_rmm()
{
    PS=`ps | grep rmm | grep -v grep | grep -c ^`

    if [ $PS -eq 0 ]; then
        echo "$(date +'%Y-%m-%d %H:%M:%S') - ./rmm is not running, restarting the camera  ..." >> $LOG_FILE
        reboot
    fi
}

check_grabber()
{
    PS=`ps | grep h264grabber | grep -v grep | grep -c ^`

    if [ $PS -eq 0 ]; then
        echo "$(date +'%Y-%m-%d %H:%M:%S') - No running processes, restarting h264grabber ..." >> $LOG_FILE
        killall -q h264grabber
        sleep 1
        restart_grabber
    fi
}

check_mqttv4()
{
    # Only monitor mqttv4 when MQTT is actually enabled in the config;
    # otherwise the watchdog respawns it forever even though it's unused.
    if [[ $(get_config MQTT) != "yes" ]] ; then
        return
    fi

    PS=`ps | grep mqttv4 | grep -v grep | grep -c ^`

    if [ $PS -eq 0 ]; then
        echo "$(date +'%Y-%m-%d %H:%M:%S') - No running processes, restarting mqttv4 ..." >> $LOG_FILE
        killall -q mqttv4
        sleep 1
        restart_mqttv4
    fi
}

if [[ $(get_config RTSP) == "no" ]] ; then
    exit
fi

# Re-enabled when its starting
echo "$(date +'%Y-%m-%d %H:%M:%S') - Starting RTSP watchdog..." >> $LOG_FILE

while true
do
    check_grabber
    check_rtsp
    check_rmm
    check_cloud
    check_mqttv4
    if [ $COUNTER -eq 0 ]; then
        sleep $INTERVAL
    fi
done
