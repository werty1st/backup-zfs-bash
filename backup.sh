#!/bin/bash

# device ID
DISK="/dev/disk/by-id/scsi-SST5000DM_000-xxx" #5000GB Seagate

# Pool mit den zu sichernden Daten
MASTERPOOL="poolz8tb"

# Backup-Pool
BACKUPPOOL="backup5000"

# Datasets, die in das Backup sollen
DATASETS=("Audio" "Downloads" "Serien")

# Anzahl der zu behaltenden letzten Snapshots, mindestens 1
KEEPOLD=1

# Praefix fuer Snapshot-Namen
PREFIX="usb"

# Debug
# DATASET=Audio
# zfs load-key -L file:///root/zfs_key_5tb backup5000/Audio
# zfs mount backup5000/Audio
# zfs list -rt bookmark
# zfs list -rt snap

# -------------- ab hier nichts aendern ---------------

zpool import $BACKUPPOOL 2> /dev/null

# Setup
if [ $? -ne 0 ] 
    then
        if (whiptail --title "$BACKUPPOOL not found" --yesno "Create $BACKUPPOOL on device $DISK?" 8 78); then
            echo "Creating pool $BACKUPPOOL on device $DISK"
            zpool create $BACKUPPOOL $DISK
        else
            echo "Aborting"
            exit 1
        fi
fi

for DATASET in ${DATASETS[@]}
do
    # Namen des aktuellsten Snapshots aus dem Backup holen
    recentBSnap=$(zfs list -rt snap -H -o name "${BACKUPPOOL}/${DATASET}" | grep "@${PREFIX}-" | tail -1 | cut -d@ -f2)
    if [ -z "$recentBSnap" ] 
        then
            # Kein Snapshot gefunden
            # Backup initialisieren
            _NAME="${PREFIX}-$(date '+%Y-%m-%d-%H:%M:%S')"
            NEWSNAP="${MASTERPOOL}/${DATASET}@${_NAME}"
            BOOKMARK="#${_NAME}"
            zfs snapshot -r "$NEWSNAP"
            zfs bookmark "$NEWSNAP" "$BOOKMARK"
            zfs send -v -w "$NEWSNAP" | zfs recv -v -d -F "${BACKUPPOOL}"   
            zfs destroy "$NEWSNAP" #save space
            continue #with next dataset         
    fi

	OLDBOOKMARK=$(zfs list -rt bookmark -H -o name "${MASTERPOOL}/${DATASET}" | grep $recentBSnap | cut -d@ -f2)
   
    # Check ob der korrespondierende Bookmark im Master-Pool existiert
    if [ -z "$OLDBOOKMARK" ]
        then
            echo "Fehler: Zum letzten Backup-Spanshot ${recentBSnap} existiert im Master-Pool kein zugehoeriger Bookmark."
            continue
    fi
    
    echo "aktuellster Snapshot im Backup: ${BACKUPPOOL}/${DATASET}@${recentBSnap}"
    
    _SNAPNAME="${PREFIX}-$(date '+%Y-%m-%d-%H:%M:%S')"
    NEWSNAP="${MASTERPOOL}/${DATASET}@${_SNAPNAME}"
    BOOKMARK="#${_SNAPNAME}"
    zfs snapshot -r "$NEWSNAP"
    zfs bookmark "$NEWSNAP" "$BOOKMARK"
    zfs send -v -w -i "$OLDBOOKMARK" "$NEWSNAP" | zfs recv -v -d -F "${BACKUPPOOL}"
    zfs destroy "$NEWSNAP" #save space

    #cleanup old
   	zfs list -rt snap -H -o name "${BACKUPPOOL}/${DATASET}" | grep "@${PREFIX}-" | head -n -$KEEPOLD | xargs -n 1 zfs destroy -r

done

zpool export $BACKUPPOOL
