#!/usr/bin/haserl
content-type: text/html

<html>
<? cat /var/www/cgi-bin/header.inc ?>
<body>

<hr>
<p class="largefont">LGMOD CONFIGURATION / NETWORK</p>
<div id="navbar"><a href="home.cgi">Home</a>&nbsp;&nbsp;&nbsp<a href="info.cgi">System Info</a>&nbsp;&nbsp;&nbsp;Network&nbsp;&nbsp;&nbsp;<a href="mount.cgi">Drives</a>&nbsp;&nbsp;&nbsp;<a href="tools.cgi">Tools</a></div>
<div class="pagebody">

<div class="post"><div class="posthead">Ethernet network configuration</div><div class="posttext">
<? ip=`awk '{print $1}' /mnt/lg/user/lgmod/network`
   mask=`awk '{print $2}' /mnt/lg/user/lgmod/network`
   gw=`awk '{print $3}' /mnt/lg/user/lgmod/network`
?>
<br>
<? echo "<form action="network.cgi" method="post"><b>Local IP Address: </b><input name="ip" type="text" id="ip" value="$ip">" ?>
<? echo "<b>Subnet Mask: </b><input name="mask" type="text" id="mask" value="$mask">" ?>
<? echo "<b>Gateway: </b><input name="gw" type="text" id="gw" value="$gw">" ?>
<input type="submit" name="ipconfig" value="Apply">
<input type="submit" name="use_dhcp" value="DHCP">
</div></div>

<div class="post"><div class="posthead">UPnP Client</div><div class="posttext">
Enable your TV as UPnP ControlPoint/Renderer:
<? if [ -e /mnt/lg/user/lgmod/upnp ]; then
echo '<input name="pnp" type="radio" value="yes" checked><b>Yes</b>'
echo '<input name="pnp" type="radio" value="no" ><b>No</b>'
cmntp=`awk '{print $1}' /mnt/lg/user/lgmod/upnp`
else
echo '<input name="pnp" type="radio" value="yes"><b>Yes</b>'
echo '<input name="pnp" type="radio" value="no" checked><b>No</b>'
cmntp=""
fi
echo "<br><b>Media mount point (/mnt/usb1/Drive1/upnp for upnp directory on USB stick first partition) :</b><input name="cmntp" type="text" id="cmntp" value="$cmntp">" ?>
<input type="submit" name="upnp" value="Apply">
</div></div>

Launch telnetd service at startup:
<? if [ -e /mnt/lg/user/lgmod/telnet ]; then
echo '<input name="tel" type="radio" value="yes" checked><b>Yes</b>'
echo '<input name="tel" type="radio" value="no" ><b>No</b>'
else
echo '<input name="tel" type="radio" value="yes"><b>Yes</b>'
echo '<input name="tel" type="radio" value="no" checked><b>No</b>'
fi
?>
<input type="submit" name="telnet" value="Apply">
</form>
<?
 if [ "$FORM_ipconfig" = "Apply" ]; then
 echo -n "$FORM_ip $FORM_mask $FORM_gw" > /mnt/lg/user/lgmod/network
 echo "<div class="ok"><p align=center><b>Restart your TV to apply changes</b></p></div>"
 fi
 if [ "$FORM_use_dhcp" = "DHCP" ]; then
 rm /mnt/lg/user/lgmod/network
 echo "<div class="ok"><p align=center><b>Restart your TV to apply changes</b></p></div>"
 fi
 if [ "$FORM_telnet" = "Apply" ]; then
	[ "$FORM_tel" = "yes" ] && echo -n > /mnt/lg/user/lgmod/telnet
	[ "$FORM_tel" = "no" ] && rm /mnt/lg/user/lgmod/telnet
 echo "<script language="javascript" type="text/javascript">location.href='network.cgi';</script>"
 fi
 if [ "$FORM_upnp" = "Apply" ]; then
	if [ "$FORM_pnp" = "yes" ]; then
		if [ $FORM_cmntp ]; then
		    echo -n $FORM_cmntp > /mnt/lg/user/lgmod/upnp
		else
		    echo -n "/mnt/usb1/Drive1/upnp" > /mnt/lg/user/lgmod/upnp
		fi
	fi
	[ "$FORM_pnp" = "no" ] && rm /mnt/lg/user/lgmod/upnp
 echo "<div class="ok"><p align=center><b>Restart your TV to apply changes</b></p></div>"
 fi

?>
</div></div>

</div>
<br>
<? cat /var/www/cgi-bin/footer.inc ?>
</body></html>
