#! /bin/sh

set +e
${DEBUG:-false} && set -x || true
if  [ $# -eq 0 ]; then
	if [ -z "$HTTPCHILD" ]; then
		echo "try $0 start"
		exit 0
	fi
	######## http child ########

	default_content_type='text/plain; charset=utf-8'

	_out_resp_httpvers='HTTP/1.0'
	_out_resp_status='500'
	_out_resp_means='Internal Server Error'
	_out_resp_content_type=''
	_out_resp_length=''	;# the Content-Length http header
	_out_resp_headers=''	;# http headers reply buffer
	_out_resp_close=true	;# add the http header "Connection: closed"
	_out_resp_is_head=false	;# in case of HEAD request, skip the body response

	# Usage: set_content_type ""           ;# set the default content type
	# Usage: set_content_type "something"  ;# content type is set to "something"
	set_content_type() { _out_resp_content_type="${1:-$default_content_type}"; }

	# Usage: set_length 9999
	set_length() { _out_resp_length="${1:-}"; }

	# Usage: set_http_version httpversion
	set_http_version() { _out_resp_httpvers="${1:-HTTP/1.0}"; }

	# Usage:  http_reply_code code text
	set_status_code() { _out_resp_status="${1:-500}"; _out_resp_means="${2:-Internal Server Error}"; }

	# Usage: http_header_reply "header: value"
	http_header_reply() { _out_resp_headers="$_out_resp_headers$(printf -- '%s\r\n' "$@")"; }

	# Usage: http_header_reply_send
	http_header_reply_send() {
		printf -- '%s %s %s\n' "$_out_resp_httpvers" "$_out_resp_status" "$_out_resp_means"			# HTTP/1.0 200 OK
		[ -z "$_out_resp_content_type" ]	|| printf 'Content-Type: %s\r\n' "$_out_resp_content_type"	# Content-Type: text/html; charset=utf-8
		[ -z "$_out_resp_length" ]		|| printf 'Content-Length: %s\r\n' "$_out_resp_length"		# Content-Length: ...
		[ -z "$_out_resp_headers" ]		|| printf -- '%s' "$_out_resp_headers"
		if ${_out_resp_close:-true}; then
			printf 'Connection: %s\r\n' 'closed'
		fi
		printf '\r\n'
		_out_resp_headers='';
		set_content_type '';
		_out_resp_close=false;
	}

	http_header_reply_add_date() { http_header_reply "Date: $(date -u "$@" +'%a, %d %b %Y %H:%M:%S GMT')"; }

	# Usage: skip_body_check	;# skip the body in case of HEAD method
	head_request_stop_here() {
		if [ "$_method" = "HEAD" ]; then
			http_header_reply_send
			exit 0
		fi
	}
	is_head_req() { [ "$_method" = "HEAD" ]; }

	body_add() { printf -- "%s${2:-}" "${1:-}" >> "$TMPFILE"; }
	body_fromfile() { cat -- "$1" >> "$TMPFILE"; }
	body_dump() { cat -- "$TMPFILE"; }
	body_len() { stat -c '%s' "$TMPFILE"; }
	body_drop() { > "$TMPFILE"; }
	#file_len() { stat -L -c '%s' "$TMPFILE"; }

	# Usage: http_body_reply "any value"
	http_body_reply() { printf -- '%s\n' "$@"; }

	_du_h() {
		local s;s="$(stat -c %s -- "$1")";
		local n=-1
		local unit=''
		for n in 0 1 2 3 4; do
			[ $(( $s / 1024 )) -gt 0 ]] || break;
			s=$(( $s / 1024 ))
		done
		case "$n" in
			0) ;;
			1) unit=K;;
			2) unit=M;;
			3) unit=G;;
			*) unit=T;;
		esac
		printf '%s%s\n' "$s" "$unit"
	}

	auto_content_type() {
		local charset="$(file -k -L -b --mime-encoding "$1")"
		[ "$charset" != "us-ascii" ] || charset=''
		printf '%s; charset=%s' "$(HOME="${HOME:-/}" mimetype -b "$1")" "${charset:-utf-8}"
	}
	access_log() {
		# apache log sample:
		# 127.0.0.1 - - [01/Jan/2017:12:34:56 +0200] "GET /path/to/file HTTP/1.0" 200 2267 "-" "Useragent"
		echo >&2 "[$(date +%H:%M:%S)] $1: \"$firstline\" ${_out_resp_status} ${_out_resp_length:--} \"-\" \"$useragent\" content-type=$_out_resp_content_type"
	}
	error_log() {
		echo >&2 "[$(date +%H:%M:%S)] ERR: $1"
	}

	#########

	_echo() { printf -- '%s'"$2" "$1"; }
	noeol() { printf -- '%s' "$1" | tr -d '\r\n'; }

	handler_403() {
		#set_http_version 'HTTP/1.0'
		set_status_code '403' 'Forbidden'
		access_log "deny" #HEAD/GET
		head_request_stop_here

		set_content_type 'text/plain; charset=utf-8'
		#set_content_type 'text/html; charset=utf-8'
		http_header_reply 'Connection: closed'
		http_header_reply_send
		http_body_reply "HACK FAILED"
	}

	autoindex() {
		local absdir="$1";	# real absolute path = abs base + subpath
		local _path="$2";	# web base dir
		#_path="$(_echo "$_path" | sed -e 's,^/\+,,g')"
		local cdir="$(basename "$_path")"
		cdir="${cdir%/}"

		_echo '<!DOCTYPE html>' '\n'
		_echo '<html>' '\n'
		_echo ' <head>' '\n'
		_echo '  <title>Index of '"$_path"'</title>' '\n'
		_echo ' </head>' '\n'
		_echo ' <body>' '\n'
		_echo '<h1>Index of '"$_path"'</h1>' '\n'
		_echo '  <table>' '\n'
		_echo '   <tr><th valign="top"><img src="/icons/blank.gif" alt="[ICO]"></th><th>Name</th><th>Last modified</th><th>Size</th></tr>' '\n'
		_echo '   <tr><th colspan="4"><hr></th></tr>' '\n'
		_echo '<tr><td valign="top"><img src="/icons/unknown.gif" alt="[   ]"></td><td><a href="'\
".."\
'">Parent Directory</a></td><td>&nbsp;</td><td align="right">  - </td></tr>' '\n'
		(
			cd -- "$absdir" && \
			for f in *; do
				_echo '<tr><td valign="top"><img src="/icons/image2.gif" alt="[IMG]"></td><td><a href="'\
"${cdir:+$cdir/}$f"\
'">'\
"$f"\
'</a></td><td align="right">'\
"$(date -d "@$(stat -c '%Y' "$f")" +'%Y-%m-%d %H:%M')"\
'</td><td align="right">'\
"$(_du_h "$f")"\
'</td></tr>' '\n'
			done
		)
		_echo '   <tr><th colspan="4"><hr></th></tr>' '\n'
		_echo '</table>' '\n'
		_echo '</body></html>' '\n'
	}
	handler_dir() {
		local _path="$1"
		#### Directory index ####
		set_http_version 'HTTP/1.0'
		set_status_code '200' 'OK'
		access_log "dir" #HEAD
		head_request_stop_here

		#http_header_reply "Location: 

		body_drop
		#body_add "content of directory $_path ($abspath):" '\n'
		autoindex "$abspath" "$_path"| body_fromfile -

		set_content_type 'text/html; charset=utf-8'
		set_length $(body_len)
		access_log "dir" #GET
		http_header_reply_send
		body_dump
		body_drop
	}

	command -v mimetype >/dev/null 2>&1 || mimetype() {
		shift $(( $# -1 ))
		case "$(basename "$1" | tr 'A-Z' 'a-z')" in
			*.md) 		_echo 'text/markdown' ;;
			*.htm|*.html) 	_echo 'text/html' ;;
			*.js)		_echo 'application/javascript' ;;
			*.json)		_echo 'application/json' ;;
			*.css)		_echo 'text/css' ;;
			*)		_echo 'application/octet-stream' ;;
		esac
	}
		
	handler_file() {
		#< HTTP/1.1 200 OK
		set_http_version 'HTTP/1.1'
		set_status_code '200' 'OK'
		set_content_type "$(auto_content_type "$abspath")"
		if is_head_req; then
		access_log "file" #HEAD
			http_header_reply_send
			exit 0
		fi

		http_header_reply_add_date
		http_header_reply "Expires: -1"
		http_header_reply "Cache-Control: private, max-age=0"
		http_header_reply "Accept-Ranges: bytes"
		http_header_reply "Access-Control-Allow-Origin: *"

		http_header_reply "Server: gws"

		http_header_reply "X-XSS-Protection: 1; mode=block"
		http_header_reply "X-Frame-Options: SAMEORIGIN"

		#< Set-Cookie: FOO=blahblah; expires=xxxx; path=/; domain=.example.net; HttpOnly

		http_header_reply "Accept-Ranges: none"
		http_header_reply "Vary: Accept-Encoding"
		http_header_reply "Transfer-Encoding: chunked"

		body_drop
		body_fromfile "$abspath"
		set_length $(body_len)
		access_log "file" #GET
		http_header_reply_send
		body_dump
		body_drop
	}
	handler_404() {
		#set_http_version 'HTTP/1.0'
		set_status_code '404' 'Not Found'
		access_log "404" #HEAD/GET
		head_request_stop_here

		body_drop
		body_add "Page Not Found" '\r\n'
		set_length $(body_len)
		set_content_type 'text/html; charset=utf-8'
		http_header_reply_send

		body_dump
		body_drop
	}

	read -r firstline
	firstline="$(noeol	"$firstline")"
	_method="$(_echo	"$firstline" | cut -d\  -f1)"
	_path="$(_echo		"$firstline" | cut -d\  -f2)"
	_httpvers="$(_echo	"$firstline" | cut -d\  -f3)"
	_empty="$(_echo		"$firstline" | cut -d\  -f4-)"

	case "$_method" in
		(HEAD) ;;
		(GET) ;;
		(*)
			error_log "Unauthorized method $_method"
			exit 0
		;;
	esac
	case "$_httpvers" in
		('HTTP/1.0'|'HTTP/1.1') ;;
		(*)
			error_log "HTTP Version not supported:"
			printf -- '%s\n' "$_httpvers" | tr -d '\r' >&2
			exit 0
		;;
	esac
	if [ -n "$_empty" ]; then
		error_log "Invalid request ($_empty)"
		exit 0
	fi

	# read all the http headers
	while read -r line; do
		line="$(printf -- '%s' "$line" | tr -d '\r\n')"
		case "$(printf -- '%s' "$line" | tr 'A-Z' 'a-z')" in
			("") break ;;
			("user-agent: "*) useragent="${line%*: }";
				#echo >&2 "#get# useragent=$useragent"
			;;
			#(*) echo >&2 "#get# $line" ;;
		esac
	done

	#local abspath
	abspath="$ROOTDIR/$_path"
	if [ -e "$abspath" ]; then
		abspath="$(readlink -f "$abspath")"
		case "$abspath" in
			("$ROOTDIR"|"$ROOTDIR"/*) ;;
			(*)
				handler_403
				exit 0
			;;
		esac
	else
		handler_404
		exit 0
	fi

	if [ -d "$abspath" ]; then
		handler_dir "$_path"
	else
		handler_file
	fi
	exit 0
fi
set +x

LOCKFILE="httpd.lock"
TMPFILE="$(mktemp)"

case "$1" in
	(start)
		shift;
		if [ -e "$LOCKFILE" ]; then
			echo "Already running ($(cat -- "$LOCKFILE"))"
			exit 2
		fi
		echo "$$" > "$LOCKFILE"
		trap -- "rm -f -- $(readlink -f "$LOCKFILE") $TMPFILE" EXIT INT
		echo traping $(readlink -f "$LOCKFILE") $TMPFILE

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
#		if [ -z "$rootdir" ]; then
#			echo ERROR missing rootdir
#			exit 123
#		fi

		[ -n "$host" ] || host='127.0.0.1'
		[ -n "$port" ] || port=8080
		rootdir="$(readlink -f "$rootdir")"

		echo "# rootdir=$rootdir"
		echo "# at http://$host:$port/"
		echo "# Started"
		#set +e
		while true; do
			#env -i - ROOTDIR="$(rootdir)" HTTPCHILD=true nc -l -p 1500 -e "$0" || break
			nc -l ${host:+-s "$host"} -p $port -c "/usr/bin/env -i - ROOTDIR='$rootdir' TMPFILE='$TMPFILE' HTTPCHILD=true PATH='$PATH' '$0'"
			[ $? -eq 1 ] && break || true
		done
		#set -e
	;;
	(status)
		shift;
		if [ -e "$LOCKFILE" ]; then
			echo "Running ($(cat -- "$LOCKFILE"))"
		else
			echo "Stopped"
		fi
	;;
	(stop)
		shift
		if [ -e "$LOCKFILE" ]; then
			kill "$(cat -- "$LOCKFILE")"
			rm -f -- "$LOCKFILE"
		else
			echo "Not running"
		fi
	;;
	(help|*)
		shift;
		echo "Usage: $0 status|stop"
		echo "Usage: $0 start [<rootdir>] [-p <port>] [-H <host>]"
	;;
esac
exit 0
