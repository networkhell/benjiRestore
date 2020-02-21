#!/usr/bin/env bash
# exit on any error -E is for capturing ERR signals from functions!!!
set -euo pipefail

# set return code of cancel button
: ${DIALOG_CANCEL=1}
: ${DIALOG_ESC=1}
# cleanup trap
trap 'cleanup' SIGINT ERR

source /usr/local/benji/bin/activate
# virtualenv is now active.
#
# Global Vars
SQLITE="/data/backup/benji/db/benji.sqlite"

function menu_1 { 
	local vmid=""
	local vmids=()
	for i in `benji --log-level ERROR -m ls | jq -r '.versions[] | select(.status|test("valid"))| .volume' |cut -d"/" -f2 |cut -d "-" -f2 | sort | uniq`; do 
		vmids+=($i)
		vmids+=("")
		vmids+=("off")
	done
	vmid=$(getVmid)  
	GETVMID_RC=$?

	if [ $GETVMID_RC -eq 1 ]; then
	    return 1
	fi    
	if [ "$vmid" = "" ]; then
	    dialog --title "BenjiRestore" --msgbox "\n\nPlease select a VMID to continue!" 10 30 3>&1 1>&2 2>&3
	    menu_1
	else
	    echo "$vmid"
	fi
}

function getVmid {
	local vmid=""
	local rc=""
	vmid=$(dialog --title "Benji Restore" --radiolist "Select VMID" 15 60 ${#vmids[@]} "${vmids[@]}" 3>&1 1>&2 2>&3)
        rc=$?
	if [ $rc -eq 1 ]; then
	    return 1 
        else
	  echo $vmid
	fi
}

function menu_2 () {
	local disk=""
	local disks=()
	for i in `benji --log-level ERROR -m ls | jq -r --arg VMID "$1" '.versions[] | select(.status|test("valid")) | select(.volume|contains($VMID)) | .volume' | sort | uniq`; do
	    disks+=($i)
	    disks+=("")
	    disks+=("off")
	done 
	disk=$(getDisk)  
	GETDISK_RC=$?

	if [ $GETDISK_RC -eq 1 ]; then
	    return 1
	elif [ $GETDISK_RC -eq 3 ]; then
	    VMID=""
	    DISK=""
	    VERSION=""
	    menu_1
	fi    
	if [ "$disk" = "" ]; then
	    menu_2 ${1}
	else
	    echo $disk
	fi
}

function getDisk {
	local disk=""
	disk=$(dialog --title "Benji Restore" --radiolist "Select disk to restore" 15 60 ${#disks[@]} "${disks[@]}" 3>&1 1>&2 2>&3)
        rc=$?
	if [ $rc -eq 1 ]; then
	    return 1 
	fi
        echo "$disk"
}

function menu_3 () {
	local version=""
	local versions=()
	local IFS=$'\n'
	for i in $(benji --log-level ERROR -m ls | jq -r --arg DISK "$1" '.versions[] | select(.status|test("valid")) | select(.volume|contains($DISK)) | [.uid, .date]| "\(.[0]) \(.[1])"'| sort -r -k2,2); do
            versions+=($(echo "$i" | cut -d ' ' -f 1))
            versions+=($(echo "$i" | cut -d ' ' -f 2))
	    versions+=("off")
	done 
	version=$(getVersion)  
	GETVERSION_RC=$?

	if [ $GETVERSION_RC -eq 1 ]; then
	    return 1
	fi    
	if [ "$version" = "" ]; then
	    menu_3 $1
	else
	    echo "$version"
	fi

}

function getVersion {
	local version=""
	version=$(dialog --title "Benji Restore" --radiolist "Select snapshot ID to restore - Columns:      | -------- UID ------- | ------- Backup Date ------- |" 15 150 ${#versions[@]} "${versions[@]}" 3>&1 1>&2 2>&3)
        rc=$?
	if [ $rc -eq 1 ]; then
	    return 1 
	fi
        echo "$version"
}

function menu_4 () {
	local restore=""
	restore=$(getRestore $1)
	GETRESTORE_RC=$?

	if [ $GETRESTORE_RC -eq 1 ]; then
	    return 1
	fi

	echo "$restore"
}

function getRestore () {
	local restore=""
	local mount=$(echo ${1} | cut -d "/" -f2)
	restore=`dialog --title "Benji Restore" --menu "How to restore the disk image?" 0 0 0 \
	 "NBD" "READONLY - Spin up an NBD server and mount the image on /mnt/benjiRestore/$mount" "RBD" "Restore the disk image to Ceph - ${1}" "FILE" "Restore the disk image to a raw disk image file on the local file system in /data/benjiRestore/..." 3>&1 1>&2 2>&3`
        rc=$?
	if [ $rc -eq 1 ]; then
	    return 1
        else
           echo "$restore"
	fi
}

# Argument needed: VERSION / 
function launchNbd () {
    clear
    BASEPATH=/mnt/benjiRestore
    MOUNT=$(echo ${1} | cut -d "/" -f2)
    modprobe nbd
    benji nbd -r & > /dev/null 2>&1
    NBD_PID=$!
    mkdir -p $BASEPATH/$MOUNT
    nbd-client -d /dev/nbd666
    sleep 2
    nbd-client -b 512 -t 10 -N ${1} localhost /dev/nbd666
    sleep 2
    partprobe /dev/nbd666
    mount -o ro /dev/nbd666p1 $BASEPATH/$MOUNT
    while :
    do
	clear
        echo "You can now access the data of $DISK on the file systen $BASEPATH/$MOUNT"
        echo "Open a second shell to this server to access the data!"
        echo "Press <CTRL+C> to exit and cleanup the mounts."
	sleep 1
    done
}


# Argument needed: VERSION / 
function launchFileRestore () {
    clear
    BASEPATH=/data/benjiRestore
    DISK=$(echo ${1} | cut -d "/" -f2)
    POOL=$(echo ${1} | cut -d "/" -f1)
    RESTORE_DIR=${BASEPATH}/${DISK}
    RESTORE_FILE=${POOL}_${DISK}.img
    mkdir -p ${RESTORE_DIR}
    if [ -e "${RESTORE_DIR}/${RESTORE_FILE}" ]; then
        echo "File ${RESTORE_DIR}/${RESTORE_FILE} already exists, aborting the restore"
	return 1
    fi
    echo "Starting the restore of ${RESTORE_DIR}/${RESTORE_FILE}. This likely will take a long time..."
    benji restore --sparse ${VERSION} file:///${RESTORE_DIR}/${RESTORE_FILE}
    echo "Disk image is restored. Use it as you like."
}

# Argument needed: VERSION / 
function launchRbdRestore () {
    clear
    DISK=$(echo ${1} | cut -d "/" -f2)
    POOL=$(echo ${1} | cut -d "/" -f1)
    echo "Starting the restore of ${DISK} to Ceph pool ${POOL}. This will likely take a while..."
    benji restore --sparse ${VERSION} rbd:${VERSION}
    echo "Disk image is restored. Use it as you like."
    rbd info ${VERSION}
}

function cleanup {
    clear
    if [ "$RESTORE" = "NBD" ] && [ "$MOUNT" != "" ]; then
      umount -f $BASEPATH/$MOUNT && rmdir $BASEPATH/$MOUNT
      nbd-client -d /dev/nbd666
      kill -9 $NBD_PID
      if [ "$(echo 'select * from locks;'|sqlite3 $SQLITE)" != "" ]; then
          echo "backing up database before modifying it" 
          cp -v $SQLITE $SQLITE.bak_$(date +%s)
          TRY=1
          while [ "$(echo 'select * from locks;'|sqlite3 $SQLITE)" != "" ]; do
              echo "trying to delete locks from database"
              echo "DELETE FROM locks WHERE reason = 'NBD';"|sqlite3 $SQLITE
	      sleep 1
	      ((TRY++))
              if [ "$TRY" -gt 5 ]; then
                  echo "Failed to unlock database.. giving up"
                  exit 1
              fi
          done
      fi
    fi
}

VMID=""
DISK=""
VERSION=""
MOUNT=""
RESTORE=""
## Start Logic
VMID=$(menu_1)
if [ $VMID != "" ]; then
    DISK=$(menu_2 $VMID)
    if [ $DISK != "" ]; then 
        VERSION=$(menu_3 $DISK)
	    if [ $VERSION != "" ]; then 
		RESTORE=$(menu_4 $VERSION)
		if [ $RESTORE = "NBD"  ]; then
		    launchNbd $VERSION;
		fi
		if [ $RESTORE = "FILE"  ]; then
		    launchFileRestore $VERSION;
		fi
		if [ $RESTORE = "RBD"  ]; then
		    launchRbdRestore $VERSION;
		fi
	    fi
    fi
fi



