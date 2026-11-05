#!/bin/zsh
# INT: run the V2 sign-in smoke on a booted simulator against the local dev API
# and save screenshots into docs/screenshots/v2/<preset>-<step>.png.
#   ops/sim-screens-v2.sh <udid> <email>
set -u
UDID=$1; EMAIL=$2
ROOT=${0:A:h:h}
PRESET=${${EMAIL%%@*}#mobile-}
OUT=$ROOT/docs/screenshots/v2
mkdir -p $OUT
cd $ROOT
~/flutter/bin/flutter test integration_test/v2_login_smoke_test.dart -d $UDID \
  --dart-define=API_BASE=http://127.0.0.1:3031 \
  --dart-define=EMAIL=$EMAIL \
  --dart-define=MAILDIR=$HOME/invoiceproject-mobile-dev-storage/outgoing-emails 2>&1 |
while IFS= read -r line; do
  print -r -- "$line"
  if [[ $line == *SHOT:* ]]; then
    name=${line##*SHOT:}
    xcrun simctl io $UDID screenshot --type=png "$OUT/$PRESET-${name//[^a-z0-9]/}.png" >/dev/null 2>&1 &&
      print -r -- "saved $OUT/$PRESET-${name//[^a-z0-9]/}.png"
  fi
done
