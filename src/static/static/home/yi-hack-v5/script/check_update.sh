#!/bin/sh

# 48US rewrite: TLS via bundled static curl 8.21.0 + OpenSSL 3.5.7,
# checking THIS fork's releases (TruckBC/yi-hack-v5-updated-us48).
# The stock script used busybox wget --no-check-certificate against
# alienatedsec/yi-hack-v5 and silently accepted MITM; the stock curl on
# the camera links libssl.so.1.1 (broken without script env). This one
# runs the self-contained curl with a Mozilla CA bundle.

CONF_FILE="etc/system.conf"

YI_HACK_PREFIX="/tmp/sd/yi-hack-v5"

CURL="$YI_HACK_PREFIX/bin/curl"
CA_BUNDLE="$YI_HACK_PREFIX/etc/ssl/cacert.pem"

get_config()
{
    key=$1
    grep -w $1 $YI_HACK_PREFIX/$CONF_FILE | cut -d "=" -f2 | awk 'NR==1 {print; exit}'
}

MAX_RETRY=10
N_RETRY=0

REMOTE_RELEASE_URL=https://api.github.com/repos/TruckBC/yi-hack-v5-updated-us48/releases/latest
REMOTE_RELEASE_FILE=/tmp/.hackremoterel
REMOTE_VERSION_FILE=/tmp/.hackremotever
REMOTE_NEWVERSION_FILE=/tmp/.hacknewver

LOCAL_VERSION_FILE=/tmp/sd/yi-hack-v5/version

if [[ $(get_config CHECK_UPDATES) == "yes" ]] ; then
    # Never disable TLS verification: if the CA bundle is missing, the
    # check fails closed (no update prompt) instead of trusting anything.
    if [ -f $CA_BUNDLE ]; then
        CURL_TLS="--cacert $CA_BUNDLE"
    else
        CURL_TLS=""
        echo "check_update: missing CA bundle $CA_BUNDLE, skipping TLS fetch" 2>/dev/null
    fi

    while : ; do
        if [ -n "$CURL_TLS" ]; then
            $CURL $CURL_TLS -f -sS --connect-timeout 10 --max-time 20 -o $REMOTE_RELEASE_FILE $REMOTE_RELEASE_URL &> /dev/null
        fi

        if [ ! -f $REMOTE_RELEASE_FILE ]; then
            # The remote version number hasn't been downloaded yet (timeout)
            # The camera might be connecting to the wifi
            # Keep checking every 5 seconds and increment retry number
            sleep 5
            ((N_RETRY++))
        fi

        [ ! -f $REMOTE_RELEASE_FILE ] && [ $N_RETRY -le $MAX_RETRY ] || break
    done

    if [ -f $REMOTE_RELEASE_FILE ] ; then
        jq -r .tag_name < $REMOTE_RELEASE_FILE > $REMOTE_VERSION_FILE 2>/dev/null
        rm $REMOTE_RELEASE_FILE
        V_LOCAL=$(cat $LOCAL_VERSION_FILE | cut -d'_' -f1)
        V_REMOTE=$(cat $REMOTE_VERSION_FILE | cut -d'_' -f1)

        # Rolling "latest"/non-semantic tags mean "no versioned update"
        case "$V_REMOTE" in
            [0-9]*.[0-9]*.[0-9]*) ;;
            *) echo "no_currentversionisbeta" > $REMOTE_NEWVERSION_FILE ; exit 0 ;;
        esac

        LOCAL_MAJOR=$(echo $V_LOCAL | cut -d'.' -f1)
        LOCAL_MINOR=$(echo $V_LOCAL | cut -d'.' -f2)
        LOCAL_PATCH=$(echo $V_LOCAL | cut -d'.' -f3)

        REMOTE_MAJOR=$(echo $V_REMOTE | cut -d'.' -f1)
        REMOTE_MINOR=$(echo $V_REMOTE | cut -d'.' -f2)
        REMOTE_PATCH=$(echo $V_REMOTE | cut -d'.' -f3)

        V_LOCAL_NUM=$(printf "%03d%03d%03d" $LOCAL_MAJOR $LOCAL_MINOR $LOCAL_PATCH)
        V_REMOTE_NUM=$(printf "%03d%03d%03d" $REMOTE_MAJOR $REMOTE_MINOR $REMOTE_PATCH)

        if [ $V_LOCAL_NUM -lt $V_REMOTE_NUM ] ; then
            echo "yes" > $REMOTE_NEWVERSION_FILE
        elif [ $V_LOCAL_NUM -eq $V_REMOTE_NUM ] ; then
            echo "no" > $REMOTE_NEWVERSION_FILE
        elif [ $V_LOCAL_NUM -gt $V_REMOTE_NUM ] ; then
            echo "no_currentversionisbeta" > $REMOTE_NEWVERSION_FILE
        fi
    fi
fi
