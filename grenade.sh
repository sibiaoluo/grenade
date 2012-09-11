#!/usr/bin/env bash

# ``grenade.sh`` is an OpenStack upgrade test harness to exercise the
# OpenStack upgrade process.  It uses DevStack to perform the initial
# OpenStack install.

# Grenade assumes it is running on the system that will be hosting the
# upgrade processes

# ``grenade.sh [-s stop-label]``
#
# ``stop-label`` is the name of the step after which the script will stop.
# This is useful for debugging upgrades.

# Keep track of the devstack directory
GRENADE_DIR=$(cd $(dirname "$0") && pwd)

# Import common functions
source $GRENADE_DIR/functions

# Determine what system we are running on.  This provides ``os_VENDOR``,
# ``os_RELEASE``, ``os_UPDATE``, ``os_PACKAGE``, ``os_CODENAME``
# and ``DISTRO``
GetDistro

# Source params
source $GRENADE_DIR/grenaderc

# For debugging
set -o xtrace

if [[ -n "$1" && "$1" == "-s" && -n "$2" ]]; then
    STOP=$2
fi

function stop() {
    stop=$1
    shift
    if [[ "$@" =~ "$stop" ]]; then
        echo "STOP called for $1"
        exit 1
    fi
}


# Install 'Work' Build of OpenStack
# =================================

source $WORK_DEVSTACK_DIR/stackrc

$GRENADE_DIR/prep-work
stop $STOP prep-work 01

cd $WORK_DEVSTACK_DIR
./stack.sh
stop $STOP stack.sh 10

# Operation
# ---------

# Validate the install
echo $WORK_DEVSTACK_DIR/exercise.sh
stop $STOP exercise.sh 20

# Create a project, users and instances
$GRENADE_DIR/setup-javelin
stop $STOP setup-javelin 30

# Shut down running code
$WORK_DEVSTACK_DIR/unstack.sh
stop $STOP unstack.sh 40


# Logging
# =======

# Set up logging
# Set ``LOGFILE`` to turn on logging
# Append '.xxxxxxxx' to the given name to maintain history
# where 'xxxxxxxx' is a representation of the date the file was created
if [[ -n "$LOGFILE" ]]; then
    LOGDAYS=${LOGDAYS:-7}
    TIMESTAMP_FORMAT=${TIMESTAMP_FORMAT:-"%F-%H%M%S"}
    CURRENT_LOG_TIME=$(date "+$TIMESTAMP_FORMAT")

    # First clean up old log files.  Use the user-specified ``LOGFILE``
    # as the template to search for, appending '.*' to match the date
    # we added on earlier runs.
    LOGDIR=$(dirname "$LOGFILE")
    LOGNAME=$(basename "$LOGFILE")
    mkdir -p $LOGDIR
    find $LOGDIR -maxdepth 1 -name $LOGNAME.\* -mtime +$LOGDAYS -exec rm {} \;

    LOGFILE=$LOGFILE.${CURRENT_LOG_TIME}
    # Redirect stdout/stderr to tee to write the log file
    exec 1> >( tee "${LOGFILE}" ) 2>&1
    echo "grenade.sh log $LOGFILE"
    # Specified logfile name always links to the most recent log
    ln -sf $LOGFILE $LOGDIR/$LOGNAME
fi


# Save databases
# --------------

mkdir -p $SAVE_DIR
for db in keystone glance nova; do
    mysqldump -uroot -p$MYSQL_PASSWORD $db >$SAVE_DIR/$db.sql.$START_RELEASE
done
stop $STOP mysqldump 90


# Upgrades
# ========

$GRENADE_DIR/prep-trunk
stop $STOP prep-trunk 100
source $TRUNK_DEVSTACK_DIR/stackrc

# Create a new named screen to run processes in
screen -d -m -S $SCREEN_NAME -t shell -s /bin/bash
sleep 1
# Set a reasonable statusbar
SCREEN_HARDSTATUS=${SCREEN_HARDSTATUS:-'%{= .} %-Lw%{= .}%> %n%f %t*%{= .}%+Lw%< %-=%{g}(%{d}%H/%l%{g})'}
screen -r $SCREEN_NAME -X hardstatus alwayslastline "$SCREEN_HARDSTATUS"

# Upgrade OS packages and known Python updates
$GRENADE_DIR/upgrade-packages
stop $STOP upgrade-packages 110

# Upgrade DevStack
#$GRENADE_DIR/upgrade-devstack
stop $STOP upgrade-devstack 120

# Upgrade Keystone
$GRENADE_DIR/upgrade-keystone
stop $STOP upgrade-keystone 130

# Upgrade Glance
$GRENADE_DIR/upgrade-glance
stop $STOP upgrade-glance 140

# Upgrade Nova
$GRENADE_DIR/upgrade-nova
stop $STOP upgrade-nova 150

# Upgrade Volumes to Cinder
#$GRENADE_DIR/upgrade-volume
stop $STOP upgrade-volume 160


# Fin
# ===

echo "Grenade has completed the pre-programmed upgrade scripts."
