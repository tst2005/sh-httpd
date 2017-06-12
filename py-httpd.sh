#!/bin/sh

rootdir=''
host=''
port=''
while [ $# -gt 0 ]; do
	case "$1" in
		(-d) rootdir="$2"; shift ;;
		(-s) host="$2"; shift ;;
		(-p) port="$2"; shift ;;
		(--) shift; break ;;
		(-*) echo ERROR; exit 123 ;;
		(*) break
	esac
	shift
done
if [ $# -gt 0 ]; then
	if [ $# -eq 1 ] && [ -z "$rootdir" ]; then
		rootdir="$1"; shift;
	else
		echo ERROR
		exit 123
	fi
fi
[ -n "$rootdir" ] || rootdir="$(pwd)"
[ -n "$host" ] || host='localhost'
[ -n "$port" ] || port=8080
rootdir="$(readlink -f "$rootdir")"
echo "# rootdir=$rootdir"
echo "# at http://$host:$port/"
(
cd -- "$rootdir" || exit 1
{
cat<<EOF
import sys
import SimpleHTTPServer
import SocketServer

port = $port
host = "$host"

#if sys.argv[1:]:
#    port = int(sys.argv[1])
#else:
#    port = 8080
#host = "localhost"

Handler = SimpleHTTPServer.SimpleHTTPRequestHandler
httpd = SocketServer.TCPServer((host, port), Handler)
#print "Serving HTTP on" , host, "port", port, "..."

httpd.serve_forever()
EOF
} | python
)
