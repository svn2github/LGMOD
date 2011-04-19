#!/bin/sh
#
# LGMOD v.1.5.7
# http://openlgtv.org.ru
# Copyright 2009 Vuk
# Copyright 2010 Arno1
#
CFG_DIR="/mnt/lg/user/lgmod"
NETCONFIG="$CFG_DIR/network"
UPNPCFG="$CFG_DIR/upnp"
FS_MNT="$CFG_DIR/ndrvtab"
HTTPD_CONF="$CFG_DIR/httpd.conf"
A_SH="$CFG_DIR/auto_start.sh"
S_SH="$CFG_DIR/auto_stop.sh"
P_SH="$CFG_DIR/patch.sh"
USB1_DIR="/mnt/usb1/Drive1/nfs"

# Init usb
echo 1 > /proc/usercalls

# Wait until connect usb drive
k=0;
while [ ! -e $USB1_DIR ]; 
do
    sleep 1;
    k=$(($k+1))
    if [ $k -gt 30 ]; then break; fi
done;
#mount -t vfat -o iocharset=utf8,shortname=mixed /dev/sda1 /mnt/usb1/Drive1

# Reset ALL config to default is magic file on USB drive
if [ -e /mnt/usb1/Drive1/lgmod_reset_config ]; then
    cp -R $CFG_DIR /mnt/usb1/Drive1		
    rm -rf $CFG_DIR
    mv /mnt/usb1/Drive1/lgmod_reset_config /mnt/usb1/Drive1/lgmod_reset_config_used
    echo "Configuration copied to USB drive and deleted ! will be reset to default."
fi
# Create directory for LGMOD configuration files if not exist
if [ ! -e $CFG_DIR ]; then
    mkdir $CFG_DIR
fi
# Copy network configuration file from USB stick first partition if exist
if [ -e /mnt/usb1/Drive1/network ]; then
    cp /mnt/usb1/Drive1/network $NETCONFIG
    dos2unix $NETCONFIG
    mv /mnt/usb1/Drive1/network /mnt/usb1/Drive1/network_used
    echo "Copied network configuration file from USB Stick"
fi
# Create default mounting FS if not exist (empty)
if [ ! -e $FS_MNT ]; then
    cat /dev/null  > $FS_MNT
fi
# Copy web UI configuration file from USB stick first partition if exist
if [ -e /mnt/usb1/Drive1/httpd.conf ]; then
    cp /mnt/usb1/Drive1/httpd.conf $HTTPD_CONF
    dos2unix $HTTPD_CONF
    mv /mnt/usb1/Drive1/httpd.conf /mnt/usb1/Drive1/httpd.conf_used
    echo "Copied web UI configuration file from USB Stick"
fi
# create default webui config file with default user and password
if [ ! -e $HTTPD_CONF ]; then
    echo "A:*"  > $HTTPD_CONF
    echo "/cgi-bin:admin:lgadmin"  >> $HTTPD_CONF
fi
# Copy autostart script from USB stick first partition if exist
if [ -e /mnt/usb1/Drive1/auto_start.sh ]; then
    cp /mnt/usb1/Drive1/auto_start.sh $A_SH
    dos2unix $A_SH
    mv /mnt/usb1/Drive1/auto_start.sh /mnt/usb1/Drive1/auto_start.sh_used
    echo "Copied autostart script from USB Stick"
fi
# Create default autostart script
if [ ! -e $A_SH ]; then
    echo "#!/bin/sh" > $A_SH
    echo "# Autostart script launched at the end of lgmod boot" >> $A_SH
    echo "# at that time you have USB and network working normally" >> $A_SH
    echo "# as well as RELEASE running" >> $A_SH
    echo "" >> $A_SH
    echo "CFG_DIR="/mnt/lg/user/lgmod"" >> $A_SH
    echo "USB_ROOT="/mnt/usb1/Drive1"" >> $A_SH
    echo "" >> $A_SH
    echo "# Copying RELEASE to USB is as simple as" >> $A_SH
    echo "#cp /mnt/lg/lgapp/* \$USB_ROOT" >> $A_SH
    echo "" >> $A_SH
    echo "# Backup your firmware this way" >> $A_SH
    echo "#cd /dev" >> $A_SH
    echo "#for mtd in \`ls mtd[0-9]*\` do" >> $A_SH
    echo "#cat /dev/\$mtd > \$USB_ROOT/\$mtd" >> $A_SH
    echo "#done" >> $A_SH
    echo "" >> $A_SH
    echo "# Backup your nvram/eeprom this way" >> $A_SH
    echo "#cat /dev/eeprom > \$USB_ROOT/eeprom" >> $A_SH
    echo "" >> $A_SH
    echo "# Backup your lgmod configuration this way" >> $A_SH
    echo "#cp \$CFG_DIR/* \$USB_ROOT" >> $A_SH
    echo "" >> $A_SH
    echo "# Luca's hack to release caches every second" >> $A_SH
    echo "while true ; do echo 3 > /proc/sys/vm/drop_caches ; sleep 1 ; done &" >> $A_SH
    echo "" >> $A_SH
    chmod +x $A_SH
fi    
# Create default autostop script
if [ ! -e $S_SH ]; then
    echo "#!/bin/sh" >> $S_SH
    chmod +x $S_SH
fi    
# Copy patch script from USB stick first partition if exist
if [ -e /mnt/usb1/Drive1/patch.sh ]; then
    cp /mnt/usb1/Drive1/patch.sh $P_SH
    dos2unix $P_SH
    mv /mnt/usb1/Drive1/patch.sh /mnt/usb1/Drive1/patch.sh_used
    echo "Copied patch script from USB Stick, will be used at next boot"
fi
# Setting Network
echo "Setting network loopback"
ifconfig lo 127.0.0.1

echo "Setting eth0..."
# No network configuration file, using dhcp
if [ ! -e $NETCONFIG ]; then
    echo "...using DHCP"
    udhcpc
# Network config file exists using defined values
else
    echo "...using network configuration file"
    IP=`awk '{ print $1}' $NETCONFIG`
    MASK=`awk '{ print $2}' $NETCONFIG`
    GW=`awk '{ print $3}' $NETCONFIG`

    ifconfig eth0 $IP netmask $MASK
    route add default gw $GW eth0

    # Testing network
    ping -c 2 $GW
fi

# From here we have network so launch network features

# Mouting Shares
echo "Mounting shares"
cat $FS_MNT | while read ndrv; do

automount=`echo $ndrv | awk -F# '{print $1}'`
fs_type=`echo $ndrv | awk -F# '{print $2}'`
src=`echo $ndrv | awk -F# '{print $3}'`
dst=`echo $ndrv | awk -F# '{print $4}'`
opt=`echo $ndrv | awk -F# '{print $5}'`
uname=`echo $ndrv | awk -F# '{print $6}'`
pass=`echo $ndrv | awk -F# '{print $7}'`

if [ "$automount" = "1" ];  then
    mnt_opt="-o noatime";
    [ "$uname" ] && mnt_opt="${mnt_opt},user=$uname,pass=$pass"
    [ "$opt" ] && mnt_opt="${mnt_opt},${opt}"
    mount -t $fs_type $mnt_opt $src $dst &
fi
done

# Launch telnet if telnet file exist in configuration directory
[ -e /mnt/lg/user/lgmod/telnet ] && /usr/sbin/telnetd -l /etc/auth.sh

# launch UPNP
if [ -e $UPNPCFG ]; then
    upnpmnt=`cat $UPNPCFG`
    sleep 5; /usr/bin/djmount -o iocharset=utf8,kernel_cache $upnpmnt
fi

# To be launched at the end webui and auto_start script
# Launch Web UI
/usr/sbin/httpd -c $HTTPD_CONF -h /var/www

# Launch autostart script
$A_SH
