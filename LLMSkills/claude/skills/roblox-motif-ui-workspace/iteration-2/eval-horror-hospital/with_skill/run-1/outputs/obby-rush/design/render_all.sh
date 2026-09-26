#!/usr/bin/env bash
# Renders the preview set and audits it. Run from the project folder:
#   bash design/render_all.sh <output-folder>
set -u
OUTDIR="${1:-design/preview}"
mkdir -p "$OUTDIR"
LUNE="${LUNE:-lune}"
fail=0
for view in "home 1280 720 none" "home-phone-landscape 828 369 none" "home-phone-portrait 366 820 none" \
            "shop 1280 720 Shop" "settings 1280 720 Settings" "inventory 1280 720 Inventory" "quests 1280 720 Quests" \
            "shop-phone-portrait 366 820 Shop" "settings-phone-landscape 828 369 Settings"; do
	set -- $view
	json="$OUTDIR/preview-$1.json"
	"$LUNE" run design/dump_menu.luau "$2" "$3" "$4" "$json" || fail=1
	python design/render_preview.py "$json" --html "$OUTDIR/preview-$1.html" --png "$OUTDIR/preview-$1.png" --label "$1" || fail=1
	rm -f "$json"
done
exit $fail
