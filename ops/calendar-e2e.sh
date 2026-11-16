#!/bin/zsh
# 0106 "יומן" — end-to-end on a simulator against a LOCAL staging API + mail catcher
# (never production). Screenshots → docs/qa-2026-11-16/owner-feedback/calendar/.
#
#   server repo:  node ops/dev-mail-catcher.mjs --smtp 1025 --http 1080 --dir ~/invoiceproject-staging-cal/mail
#                 STAGING_PORT=3045 STAGING_DB=invoice_staging_cal STAGING_BASE=~/invoiceproject-staging-cal \
#                 STAGING_SMTP_PORT=1025 ops/run-staging-qa.sh
#   simulator:    xcrun simctl privacy <udid> grant calendar space.tevel.invoice
#   this script:  ops/calendar-e2e.sh <udid> setup   (app: settings, connect, private event, agenda)
#                 ops/calendar-e2e.sh <udid> host    (Calendar app, Safari public page, client books, mail)
#                 ops/calendar-e2e.sh <udid> after   (app: notch for the booking, written event, reminder)
set -u
U=$1
STEP=${2:-all}
API=${API:-http://127.0.0.1:3045}
MAIL=${MAIL:-http://127.0.0.1:1080}
MAILDIR=${MAILDIR:-$HOME/invoiceproject-staging-cal/mail}
ROOT=${0:A:h:h}
OUT=$ROOT/docs/qa-2026-11-16/owner-feedback/calendar
STATE=$HOME/invoiceproject-staging-cal/e2e.env
mkdir -p $OUT
cd $ROOT

snap() { xcrun simctl io $U screenshot --type=png "$OUT/$1.png" >/dev/null 2>&1 && print -r -- "saved $OUT/$1.png"; }

phase() {
  ~/flutter/bin/flutter test integration_test/calendar_e2e_test.dart -d $U \
    --dart-define=API_BASE=$API --dart-define=MAILDIR=$MAILDIR --dart-define=PHASE=$1 2>&1 |
    while IFS= read -r line; do
      print -r -- "$line"
      case $line in
        *SHOT:*) n=${line##*SHOT:}; n=${n#calendar/}; snap "app-$1-${n//\//-}" ;;
        *PUBLIC:*) print -r -- "PUBLIC=${line##*PUBLIC:}" >>$STATE ;;
        *BUSY:*) print -r -- "BUSY=${line##*BUSY:}" >>$STATE ;;
      esac
    done
}

json() { python3 -c "import json,sys; d=json.load(sys.stdin); print(eval(sys.argv[1]))" "$1"; }

host() {
  source $STATE
  local slug=${PUBLIC##*/}
  # 1. The owner's private event in the iOS Calendar app (calshow: seconds since 2001-01-01).
  local busy_epoch=$(date -j -u -f '%Y-%m-%dT%H:%M:%S' "${BUSY%%.*}" +%s)
  xcrun simctl openurl $U "calshow:$((busy_epoch - 978307200))"
  sleep 5; snap web-01-ios-calendar-private-event
  # 2. The public page in Safari: free times only.
  xcrun simctl openurl $U "$PUBLIC"
  sleep 6; snap web-02-public-free-slots
  # 3. The busy time itself → "no longer free" (no title, nothing about it).
  xcrun simctl openurl $U "$PUBLIC?start=$(python3 -c 'import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))' "$BUSY")"
  sleep 5; snap web-03-busy-time-refused
  curl -s -H 'Accept: application/json' "$PUBLIC" >$OUT/public-slots.json
  # 4. A free slot tomorrow at 12:00 (Israel): the form …
  local tomorrow=$(TZ=Asia/Jerusalem date -v+1d +%Y-%m-%d)
  local start=$(json "[s['start'] for s in d['slots'] if s['date']=='$tomorrow' and s['time']=='12:00'][0]" <$OUT/public-slots.json)
  local q=$(python3 -c 'import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))' "$start")
  xcrun simctl openurl $U "$API/book/$slug?start=$q"
  sleep 5; snap web-04-public-form
  # … submitted BY SAFARI (a prefilled copy of the same form: no typing automation on the simulator).
  local helper=$HOME/invoiceproject-staging-cal/www
  mkdir -p $helper
  cat >$helper/book.html <<HTML
<!doctype html><meta charset="utf-8"><body onload="document.forms[0].submit()">
<form method="post" action="$API/book/$slug">
<input name="start" value="$start"><input name="name" value="דנה כהן"><input name="phone" value="052-1234567">
<input name="email" value="dana.client@example.test"><input name="website" value="">
<textarea name="notes">ייעוץ לפתיחת עוסק מורשה — שאלות על מע״מ</textarea></form>
HTML
  (cd $helper && python3 -m http.server 1081 --bind 127.0.0.1 >/dev/null 2>&1 &) ; sleep 1
  xcrun simctl openurl $U "http://127.0.0.1:1081/book.html"
  sleep 6; snap web-05-public-confirmation
  pkill -f "http.server 1081" || true
  # 5. The invite in the mail catcher (+ the .ics), and the client's manage link.
  sleep 2
  xcrun simctl openurl $U "$MAIL/?to=dana.client@example.test"
  sleep 5; snap web-06-mail-invite-ics
  curl -s "$MAIL/api/messages" >$OUT/mail-messages.json
  local invite_ics=$(json "[i['file'] for m in d if 'dana.client' in m['to'] for i in m['ics']][0]" <$OUT/mail-messages.json)
  cp $MAILDIR/$invite_ics $OUT/invite.ics
  local manage=$(json "__import__('re').search(r'(http\S+/book/m/[A-Za-z0-9_-]{43})', [m['bodyText'] for m in d if 'dana.client' in m['to']][0]).group(1)" <$OUT/mail-messages.json)
  xcrun simctl openurl $U "$manage"
  sleep 5; snap web-07-client-manage-link
  xcrun simctl openurl $U "$MAIL/?to=mobile-owner@tevel.test"
  sleep 5; snap web-08-mail-owner-notice
  # 6. A second client takes a slot that starts soon (for the reminder in the "after" phase).
  local soon=$(json "[s['start'] for s in d['slots'] if __import__('datetime').datetime.fromisoformat(s['start'].replace('Z','+00:00')).timestamp() > __import__('time').time() + 16*60][0]" <$OUT/public-slots.json)
  curl -s -X POST "$API/book/$slug" -H 'Content-Type: application/json' \
    -d "{\"start\":\"$soon\",\"name\":\"רון לוי\",\"phone\":\"054-7654321\",\"email\":\"ron.client@example.test\",\"notes\":\"פגישת היכרות קצרה\"}" |
    python3 -c 'import json,sys; d=json.load(sys.stdin); print("SOON-BOOKED", d.get("status"), d.get("startsAt"))'
  # Back to the app's home screen for the next phase.
  xcrun simctl terminate $U com.apple.mobilesafari >/dev/null 2>&1 || true
  xcrun simctl terminate $U com.apple.mobilecal >/dev/null 2>&1 || true
}

after_host() {
  source $STATE
  # The booking written into the phone calendar by the app (tomorrow 12:00).
  local tomorrow_noon=$(TZ=Asia/Jerusalem date -v+1d -j -f '%H:%M:%S' '12:00:00' +%s)
  xcrun simctl openurl $U "calshow:$((tomorrow_noon - 978307200))"
  sleep 5; snap web-09-ios-calendar-booking-written
}

case $STEP in
  setup) rm -f $STATE; phase setup ;;
  host) host ;;
  after) phase after; after_host ;;
  all) rm -f $STATE; phase setup && host && phase after && after_host ;;
esac
