#!/usr/bin/haserl --upload-limit=14096 --upload-dir=/mnt/lg/bt
content-type: text/html

<html>
<? cat /var/www/cgi-bin/header.inc ?>
<body>

<hr>
<p class="largefont">LGMOD CONFIGURATION / TOOLS</p>
<div id="navbar"><a href="home.cgi">Home</a>&nbsp;&nbsp <a href="info.cgi">System Info&nbsp;&nbsp;&nbsp;</a><a href="network.cgi">Network</a>&nbsp;&nbsp;&nbsp;<a href="mount.cgi">Drives</a>&nbsp;&nbsp;&nbsp;Tools</div>
<div class="pagebody">

<div class="post"><div class="posthead">Security</div><div class="posttext">
<form action="tools.cgi" method="post">
<? pass=`awk -F: '/cgi-bin/ {print $3}' /mnt/lg/user/lgmod/httpd.conf`; echo "WebUI access password: <input name="passwd" type="password" id="passwd" size=10 value="$pass">" ?>
<input type="submit" name="change" value="Change">
</form>
</div></div>
<? 
 if [ "$FORM_change" = "Change" ]; then
	cp /mnt/lg/user/lgmod/httpd.conf /mnt/lg/user/lgmod/httpd.conf.tmp
	old_pw=`awk -F: '/cgi-bin/ {print $3}' /mnt/lg/user/lgmod/httpd.conf`
	sed "s/$old_pw/$FORM_passwd/" /mnt/lg/user/lgmod/httpd.conf.tmp > /mnt/lg/user/lgmod/httpd.conf
	echo "<div class="ok"><p align=center><b>Restart your TV to apply changes</b></p></div>"
  fi 
?>

<div class="post"><div class="posthead">Execute shell command</div><div class="posttext">
<form action="tools.cgi" method="post">
<input name="shell" type="text" size=48>
<input type="submit" name="run" value="Run">
</form>
<?
 if [ "$FORM_run" = "Run" ]; then
    echo -n "$FORM_shell" > /tmp/shell_command.sh
    dos2unix /tmp/shell_command.sh
    chmod +x /tmp/shell_command.sh
    /tmp/shell_command.sh &> /tmp/shell_command.out   
    sync
    echo "<pre>"
    cat /tmp/shell_command.out
    echo "</pre>"
 fi
?>
</div></div>

<div class="post"><div class="posthead">Upload the firmware on the flash drive into a folder LG_DTV. If the folder "LG_DTV" does not exist - download the file twice.</div><div class="posttext">
<form action="tools.cgi" method="post" enctype="multipart/form-data" >
    <input type=file name=uploadfile>
    <input type=submit value=Upload>
    <br>
     <? if [ -n "$HASERL_uploadfile_path" ]; then 
          if [ ! -e /mnt/usb1/Drive1/LG_DTV ]; then
             mkdir /mnt/usb1/Drive1/LG_DTV 
          fi
        echo "You uploaded a file named <b>"
        echo -n $FORM_uploadfile_name
        echo "</b>, and it was stored on the TV as <i>"
        echo $HASERL_uploadfile_path
        echo "</i>"
        cat $HASERL_uploadfile_path | wc -c
        echo "bytes)."
        mv /mnt/lg/bt/$FORM_uploadfile_name /mnt/usb1/Drive1/LG_DTV
        rm /mnt/lg/bt/$FORM_uploadfile_name
     else
        echo "You haven't uploaded a file yet."
     fi ?>
</form>
</div></div>

<div class="post"><div class="posthead">Autostart script (to be executed after lgmod (network available) and RELEASE running (USB available))</div><div class="posttext">
<form action="tools.cgi" method="post">
<? txt=`cat /mnt/lg/user/lgmod/auto_start.sh`; echo "<textarea name="script1" rows="10" cols="80">$txt</textarea>" ?>
<br>
<input type="submit" name="save1" value="Save">
<input type="submit" name="execute1" value="Execute">
</form>
<? 
    if [ "$FORM_save1" = "Save" ]; then
       echo -n "$FORM_script1" > /mnt/lg/user/lgmod/auto_start.sh
       dos2unix /mnt/lg/user/lgmod/auto_start.sh
       sync
       echo "<script language="javascript" type="text/javascript">location.href='tools.cgi';</script>"
    fi
    if [ "$FORM_execute1" = "Execute" ]; then
       /mnt/lg/user/lgmod/auto_start.sh
    fi
?>
</div></div>

<div class="post"><div class="posthead">Autostop script</div><div class="posttext">
<form action="tools.cgi" method="post">
<? txt=`cat /mnt/lg/user/lgmod/auto_stop.sh`; echo "<textarea name="script11" rows="10" cols="80">$txt</textarea>" ?>
<br>
<input type="submit" name="save11" value="Save">
<input type="submit" name="execute11" value="Execute">
</form>
<? 
    if [ "$FORM_save11" = "Save" ]; then
       echo -n "$FORM_script11" > /mnt/lg/user/lgmod/auto_stop.sh
       dos2unix /mnt/lg/user/lgmod/auto_stop.sh
       sync
       echo "<script language="javascript" type="text/javascript">location.href='tools.cgi';</script>"
    fi
    if [ "$FORM_execute11" = "Execute" ]; then
       /mnt/lg/user/lgmod/auto_stop.sh
    fi
?>
</div></div>

<div class="post"><div class="posthead">Modules configuration script (you can comment/uncomment/add modules to fit your needs)</div><div class="posttext">
<form action="tools.cgi" method="post">
<? txt=`cat /mnt/lg/user/lgmod/modules.sh`; echo "<textarea name="script2" rows="10" cols="80">$txt</textarea>" ?>
<br>
<input type="submit" name="save2" value="Save">
</form>
<? if [ "$FORM_save2" = "Save" ]; then
    echo -n "$FORM_script2" > /mnt/lg/user/lgmod/modules.sh
    dos2unix /mnt/lg/user/lgmod/modules.sh
    sync
    echo "<script language="javascript" type="text/javascript">location.href='tools.cgi';</script>"
fi ?>
</div></div>

<div class="post"><div class="posthead">Patch script (executed BEFORE RELEASE and lgmod)</div><div class="posttext">
<form action="tools.cgi" method="post">
<? txt=`cat /mnt/lg/user/lgmod/patch.sh`; echo "<textarea name="script3" rows="10" cols="80">$txt</textarea>" ?>
<br>
<input type="submit" name="save3" value="Save">
</form>
<? if [ "$FORM_save3" = "Save" ]; then
    echo -n "$FORM_script3" > /mnt/lg/user/lgmod/patch.sh
    dos2unix /mnt/lg/user/lgmod/patch.sh
    sync
    echo "<script language="javascript" type="text/javascript">location.href='tools.cgi';</script>"
fi ?>
</div></div>

<div class="post"><div class="posthead">Debug</div><div class="posttext">
<form action="tools.cgi" method="post">
<div class="post"><div class="posthead">Reboot without RELEASE launched</div><div class="posttext">
<input type="submit" name="relen" value="Reboot">
</form>
</div></div>
<?
 if [ "$FORM_relen" = "Reboot" ]; then
    echo -n "1" > /mnt/lg/user/lgmod/debug
    reboot
 fi
?>
</div></div>

</div></div>
</div>
<br>
<? cat /var/www/cgi-bin/footer.inc ?>
</body></html>
