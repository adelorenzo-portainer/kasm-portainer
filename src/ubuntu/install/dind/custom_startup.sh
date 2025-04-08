#!/usr/bin/env bash
set -ex

# Portainer settings
PORTAINER_START_COMMAND="/usr/bin/supervisord"
PORTAINER_PGREP="supervisord"
PORTAINER_DEFAULT_ARGS="-n"
PORTAINER_ARGS=${PORTAINER_APP_ARGS:-$PORTAINER_DEFAULT_ARGS}

# Chrome settings
CHROME_START_COMMAND="google-chrome"
CHROME_PGREP="chrome"
CHROME_DEFAULT_ARGS="--no-sandbox --kiosk --disable-infobars --disable-notifications --disable-features=TranslateUI --ignore-certificate-errors"
CHROME_URL="https://localhost:9443"

options=$(getopt -o gau: -l go,assign,url: -n "$0" -- "$@") || exit
eval set -- "$options"

while [[ $1 != -- ]]; do
    case $1 in
        -g|--go) GO='true'; shift 1;;
        -a|--assign) ASSIGN='true'; shift 1;;
        -u|--url) OPT_URL=$2; shift 2;;
        *) echo "bad option: $1" >&2; exit 1;;
    esac
done
shift

# Process non-option arguments.
for arg; do
    echo "arg! $arg"
done

FORCE=$2

# Start Portainer in the background
start_portainer() {
    echo "Starting Portainer..."
    /dockerstartup/portainer.sh &
    
    # Wait for Portainer to start (give it enough time to initialize)
    echo "Waiting for Portainer to initialize..."
    sleep 15
}

kasm_exec() {
    if [ -n "$OPT_URL" ] ; then
        URL=$OPT_URL
    elif [ -n "$1" ] ; then
        URL=$1
    else
        URL=$CHROME_URL
    fi 
    
    # Since we are execing into a container that already has the browser running from startup, 
    #  when we don't have a URL to open we want to do nothing. Otherwise a second browser instance would open. 
    if [ -n "$URL" ] ; then
        /usr/bin/filter_ready
        /usr/bin/desktop_ready
        $CHROME_START_COMMAND $CHROME_DEFAULT_ARGS $URL
    else
        echo "No URL specified for exec command. Doing nothing."
    fi
}

kasm_startup() {
    # Start Portainer first
    start_portainer
    
    if [ -n "$KASM_URL" ] ; then
        URL=$KASM_URL
    elif [ -z "$URL" ] ; then
        URL=${LAUNCH_URL:-$CHROME_URL}
    fi

    if [ -z "$DISABLE_CUSTOM_STARTUP" ] ||  [ -n "$FORCE" ] ; then
        echo "Entering process startup loop"
        set +x
        
        # First manage supervisord for Portainer
        while true; do
            if ! pgrep -x $PORTAINER_PGREP > /dev/null; then
                /usr/bin/filter_ready
                /usr/bin/desktop_ready
                set +e
                sudo /usr/bin/supervisord -n &
                set -e
                # Give supervisord time to start
                sleep 5
            fi
            
            # Now check and start Chrome if needed
            if ! pgrep -x $CHROME_PGREP > /dev/null; then
                /usr/bin/filter_ready
                /usr/bin/desktop_ready
                set +e
                echo "Starting Chrome in kiosk mode to Portainer interface..."
                $CHROME_START_COMMAND $CHROME_DEFAULT_ARGS $URL &
                set -e
            fi
            
            sleep 5
        done
        set -x
    fi
}

if [ -n "$GO" ] || [ -n "$ASSIGN" ] ; then
    kasm_exec
else
    kasm_startup
fi