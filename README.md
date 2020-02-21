# benjiRestore

Are you using the awesome [Benji backup](https://github.com/elemental-lf/benji). Then check out this script to make restore of benji backups a piece of cake. 

### Is pveSnapBackup the tool of choice for me?
If you backup Proxmox VE KVM disks from Ceph storage with benji then this is a perfect match. If you are using benji backup with another infrastructure then you will be able to edit the script to your needs in minutes. Currently it is tightly cuppled to my backup wrapper for benji and PVE - [pveSnapBackup](https://github.com/networkhell/pve-snapbackup). Contributions to make it more general purpose are welcome.

### Features

#### Restore to NBD Server
Automatically set up and mount a NBD device (default is /dev/nbd666) to gain file level access to your benji backups. 

### Restore to File 
Restore your benji backup to a raw disk image file. You will need enough disk space on your backup host. 

### Restore to Ceph
Restore a benji backup directly to its original CEPH storage pool. 

