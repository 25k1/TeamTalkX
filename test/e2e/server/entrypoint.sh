#!/bin/sh
set -eu

base=/srv/teamtalk
rm -rf "${base:?}/plain" "${base:?}/pro"
mkdir -p "${base}/plain/files"
cp "${base}/tt5srv.xml" "${base}/plain/tt5srv.xml"

tt5srv -nd -verbose -wd "${base}/plain" -c "${base}/plain/tt5srv.xml" &
plain=$!
stunnel4 "${base}/stunnel.conf" &
tls=$!
pids="$plain $tls"

id="${TT_PRO_BEARWARE_ID:-}"
token="${TT_PRO_BEARWARE_TOKEN:-}"
if [ -n "$id" ] && [ -n "$token" ]; then
  case "${id}${token}" in
    *[!A-Za-z0-9@._+-]*)
      echo "TT_PRO_BEARWARE_ID/TOKEN contain unexpected characters." >&2
      exit 1
      ;;
  esac
  mkdir -p "${base}/pro/files"
  conf="${base}/pro/tt5srv.xml"
  (umask 077 && sed \
    -e "s#<general>#<general>\n        <certificate-file>${base}/ttservercert.pem</certificate-file>\n        <privatekey-file>${base}/ttserverkey.pem</privatekey-file>#" \
    -e "s#<tcpport>10333</tcpport>#<tcpport>10543</tcpport>#" \
    -e "s#<udpport>10333</udpport>#<udpport>10543</udpport>#" \
    -e "s#</teamtalk>#    <bearware-weblogin>\n        <bearwareid>${id}</bearwareid>\n        <bearwaretoken>${token}</bearwaretoken>\n    </bearware-weblogin>\n</teamtalk>#" \
    "${base}/tt5srv.xml" > "$conf")
  tt5prosrv -nd -verbose -wd "${base}/pro" -c "$conf" < /dev/null &
  pids="$pids $!"
  echo "Started the Pro server on 10543." >&2
else
  echo "No BearWare.dk token: the Pro server (10543) is not started." >&2
fi

trap 'kill $pids 2>/dev/null || true' INT TERM

while kill -0 "$plain" 2>/dev/null && kill -0 "$tls" 2>/dev/null; do
  sleep 1
done
kill $pids 2>/dev/null || true
echo "The TeamTalk server or stunnel stopped; exiting." >&2
exit 1
