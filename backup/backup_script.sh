#!/bin/bash

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/opt/java/bin

DATE=`date +%Y%m%d%H%M%S`

SNAME="snapshot-$DATE"

BACKUPDIRECTORY="/var/lib/cassandra/script_backup/"

if [ ! -d "$BACKUPDIRECTORY" ]; then
        echo "Directory $BACKUPDIRECTORY not found, creating..."
        mkdir $BACKUPDIRECTORY
fi

if [ ! -d "$BACKUPDIRECTORY" ]; then
        echo "Directory $BACKUPDIRECTORY not found, exit..."
        exit
fi

echo
echo "Snapshot name: $SNAME"
echo "Clear all snapshots"
nodetool -h 127.0.0.1 clearsnapshot

cd $BACKUPDIRECTORY

prev_snap_pattern="prev\-snapshot-[0-9]*\/"
snap_pattern="snapshot-[0-9]*\/"

X="`find */ -maxdepth 0 -type d`"

if [[ (! $X =~ $prev_snap_pattern) && ($X =~ $snap_pattern) ]]; then
	D="prev-$X"
        if [ ! -d "$D" ]; then
	        mkdir $D
        fi
fi

previousSnapFolder="`find */ -maxdepth 0  -regex $prev_snap_pattern`"
snapshotFolder="`find */ -maxdepth 0  -regex $snap_pattern`"

echo "$previousSnapFolder"
rm -rf "$previousSnapFolder"

mv "$snapshotFolder" "prev-$snapshotFolder"

echo "Taking snapshot"
nodetool -h 127.0.0.1 snapshot -t $SNAME
SFILES=`ls -1 -d /var/lib/cassandra/data/*/*/snapshots/$SNAME`
for f in $SFILES
do
        echo "Process snapshot $f"
        TABLE=`echo $f | awk -F/ '{print $(NF-2)}'`
        KEYSPACE=`echo $f | awk -F/ '{print $(NF-3)}'`

        if [ ! -d "$BACKUPDIRECTORY/$SNAME" ]; then
                mkdir $BACKUPDIRECTORY/$SNAME
        fi

        if [ ! -d "$BACKUPDIRECTORY/$SNAME/$KEYSPACE" ]; then
                mkdir $BACKUPDIRECTORY/$SNAME/$KEYSPACE
        fi

        mkdir $BACKUPDIRECTORY/$SNAME/$KEYSPACE/$TABLE
        find $f -maxdepth 1 -type f -exec mv -t $BACKUPDIRECTORY/$SNAME/$KEYSPACE/$TABLE/ {} +
done

echo "Clear Incremental Backups"
SFILES=`ls -1 -d /var/lib/cassandra/data/*/*/backups/`
for f in $SFILES
do
        echo "Clear $f"
        rm -f $f*
done
