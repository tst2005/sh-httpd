#! /bin/sh

if [ -n "$HTTPCHILD" ] || [ $# -ne 0 ]; then

	read -r firstline <&3
	echo >&4 "you asked $firstline"

	echo >&4 "foo"
	printenv |grep SOCAT >&4
	echo >&4 "BYE"
	exit 0
fi



port=1500
bind="localhost"

self="$0"
case "$0" in
	(/*) self="$0" ;;
	(*) self="$(pwd)/$0";;
esac

SOCAT_VERSION='$SOCAT_VERSION'


#SOCAT_PID='$SOCAT_PID' SOCAT_PPID='$SOCAT_PPID'

script="/usr/bin/env -i - ROOTDIR='$rootdir' TMPFILE='$TMPFILE' \
HTTPCHILD=true PATH='$PATH' HOME=/ \
SOCAT_PEERADDR='\$SOCAT_PEERADDR' SOCAT_PEERPORT='\$SOCAT_PEERPORT' \
SOCAT_SOCKADDR='\$SOCAT_SOCKADDR' SOCAT_SOCKPORT='\$SOCAT_SOCKPORT' '$self'"

#script="/usr/bin/env - ROOTDIR='$rootdir' TMPFILE='$TMPFILE' HTTPCHILD=true PATH='$PATH' '$self'"
script="'$self' child"
# EXEC:"mail.sh target@domain.com",fdin=3,fdout=4

socat \
	TCP4-LISTEN:${port},bind=${bind},reuseaddr,fork,crlf,nodelay \
	EXEC:"${script}",pty,stderr,fdin=3,fdout=4

#stderr

#tcpwrap=sh-httpd
#crnl

#nodelay
#keepalive
#bind=myaddr1,reuseaddr
#max-children=<count>
#sighup, sigint, sigquit

#path=<string> overwrite PATH
#chroot=/home/sandbox,su-d=sandbox



# tcpwrap[=<name>]
# allow-table=/path/to/hosts.allow
# deny-table=/path/to/hosts.deny
# tcpwrap-etc=/path/to



