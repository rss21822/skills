#!/usr/bin/env bash
# Renders the menu (real MainMenu.build under the test mock) for each scenario and screenshots it with
# headless Chrome.  usage: run_previews.sh <projectRoot> <prefix> [WxH ...]
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
LUNE=/c/Users/ryufu/.rokit/tool-storage/lune-org/lune/0.10.5/lune.exe
CHROME="/c/Program Files/Google/Chrome/Application/chrome.exe"
PROJECT="$1"; PREFIX="$2"; shift 2
SIZES="${@:-1280x720}"
MOCK="$HERE/../obby-rush/tests/mock.luau"
mkdir -p "$HERE/html"
for size in $SIZES; do
  W=${size%x*}; H=${size#*x}
  for scenario in main hover shop settings inventory; do
    out="$HERE/html/${PREFIX}_${scenario}_${W}x${H}"
    "$LUNE" run "$HERE/render_menu.luau" "$PROJECT" "$MOCK" "$W" "$H" "$scenario" "$out.html" > /dev/null
    "$CHROME" --headless=new --disable-gpu --disable-lcd-text --hide-scrollbars --force-device-scale-factor=1 --window-size=$W,$H \
      --screenshot="$(cygpath -w "$out.png")" "file:///$(cygpath -m "$out.html")" > /dev/null 2>&1
    echo "$out.png"
  done
done
