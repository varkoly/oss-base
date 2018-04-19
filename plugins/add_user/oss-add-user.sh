#!/bin/bash
#
# Copyright (c) 2017 Peter Varkoly Nürnberg, Germany.  All rights reserved.
#

if [ ! -e /etc/sysconfig/schoolserver ]; then
   echo "ERROR This ist not an OSS."
   exit 1
fi

. /etc/sysconfig/schoolserver

if [ -z "${SCHOOL_HOME_BASE}" ]; then
   echo "ERROR SCHOOL_HOME_BASE must be defined."
   exit 2
fi

if [ ! -d "${SCHOOL_HOME_BASE}" ]; then
   echo "ERROR SCHOOL_HOME_BASE must be a directory and must exist."
   exit 3
fi

abort() {
        TASK=$( uuidgen -t )
	mkdir -p /var/adm/oss/opentasks/
        echo "add_user" > /var/adm/oss/opentasks/$TASK
        echo "uid: $uid" >> /var/adm/oss/opentasks/$TASK
        echo "password: $password" >> /var/adm/oss/opentasks/$TASK
        echo "mpassword: $mpassword" >> /var/adm/oss/opentasks/$TASK
        echo "surName: $surName" >> /var/adm/oss/opentasks/$TASK
        echo "givenName: $givenName" >> /var/adm/oss/opentasks/$TASK
        echo "role: $role" >> /var/adm/oss/opentasks/$TASK
        echo "fsQuota: $fsQuota" >> /var/adm/oss/opentasks/$TASK
        echo "msQuota: $msQuota" >> /var/adm/oss/opentasks/$TASK
        exit 1
}

surName=''
givenName=''
role=''
uid=''
password=''
mpassword='no'
fsQuota=0
msQuota=0
groups=""


while read a
do
  b=${a/:*/}
  c=${a/$b: /}
  case $b in
    surName)
      surName="${c}"
    ;;
    givenName)
      givenName="${c}"
    ;;
    uid)
      uid="${c}"
    ;;
    role)
      role="${c}"
    ;;
    password)
      password="${c}"
    ;;
    mpassword)
      mpassword="${c}"
    ;;
    fsQuota)
      fsQuota="${c}"
    ;;
    msQuota)
      msQuota="${c}"
    ;;
  esac
done

skel="/etc/skel"

winprofile="\\\\${SCHOOL_NETBIOSNAME}\\profiles\\$uid"
winhome="\\\\${SCHOOL_NETBIOSNAME}\\$uid"

if [ $SCHOOL_SORT_HOMES = "yes" ]; then
        unixhome=${SCHOOL_HOME_BASE}/$role/$uid
else
        unixhome=${SCHOOL_HOME_BASE}/$uid
fi

if [ $mpassword != "no" ]; then
   ADDPARAM=" --must-change-at-next-login"
fi

if [ "$role" = "workstations"  -o "$role" = "guest" ]; then
    samba-tool domain passwordsettings set --complexity=off
fi

uidNumber=$( /usr/share/oss/tools/get_next_id )

samba-tool user create "$uid" "$password" \
				--use-username-as-cn \
				--username="$uid" \
				--uid="$uid" \
				--password="$password" \
				--surname="$surName" \
				--given-name="$givenName" \
				--home-drive="Z:" \
				--profile-path="$winprofile" \
				--script-path="$uid.bat" \
				--home-directory="$winhome" \
				--nis-domain="${SCHOOL_WORKGROUP}" \
				--unix-home="$unixhome" \
				--login-shell=/bin/bash \
				--uid-number=$uidNumber \
				--gid-number=100 \
				$ADDPARAM

if [ $? != 0 ]; then
   abort
fi
if [ "${SCHOOL_CHECK_PASSWORD_QUALITY}" = "yes" ]; then
   samba-tool domain passwordsettings set --complexity=on
fi

#create home diredtory copy template user homedirectory and set permission
mkdir -p $unixhome
/usr/sbin/oss_copy_template_home.sh $uid
if [ "$SCHOOL_TEACHER_OBSERV_HOME" = "yes" -a "$role" = "students" ]; then
	chown -R $uidNumber:TEACHERS "$unixhome"
	chmod 0770 "$unixhome"
else
	chown -R $uidNumber:100 "$unixhome"
	chmod 0700 "$unixhome"
fi
#Workaround
if [ $SCHOOL_SORT_HOMES = "yes" ]; then
        ln -s $unixhome ${SCHOOL_HOME_BASE}/${SCHOOL_WORKGROUP}/$uid
fi


#Samba has to recognize the ne user
sleep 3

#add user to groups
samba-tool group addmembers "$role" "$uid"

#Workstation users password should not expire
if [ "$role" = "workstations" ]; then
	tmpldif=$( mktemp /tmp/XXXXXXXX )
	/usr/sbin/oss_get_dn.sh $uid > $tmpldif
	echo "changetype: modify
add: userWorkstations
userWorkstations: $uid" >> $tmpldif
	ldbmodify  -H /var/lib/samba/private/sam.ldb $tmpldif
	samba-tool user setexpiry  --noexpiry $uid
	rm -f $tmpldif
	#pdbedit -u $uid -c "[X]"
fi

#Set default quota
if [ -z "$fsQuota" ]; then
        fsQuota=$SCHOOL_FILE_QUOTA
        if [ $role = "teachers" ]; then
                fsQuota=$SCHOOL_FILE_TEACHER_QUOTA
        fi
fi

/usr/sbin/oss_set_quota.sh $uid $fsQuota
