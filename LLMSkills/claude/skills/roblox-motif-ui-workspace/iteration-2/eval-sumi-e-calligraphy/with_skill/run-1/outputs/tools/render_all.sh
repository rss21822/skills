#!/usr/bin/env bash
# Render every preview view of the skinned menu (and the original for comparison).
# Usage: bash tools/render_all.sh   (from the outputs folder)
set -e
LUNE="C:/Users/ryufu/.rokit/tool-storage/lune-org/lune/0.10.5/lune.exe"
ORIG="C:/Users/ryufu/.claude/skills/roblox-motif-ui/evals/files/obby-rush"
mkdir -p tools/out previews
view() { # project name width height page
  "$LUNE" run tools/dump_menu.luau "$1" "$3" "$4" "$5" 0 "tools/out/$2.json" > /dev/null
  PYTHONIOENCODING=utf-8 python tools/render_preview.py "tools/out/$2.json" "previews/$2.html" --png "preview_$2.png" \
    --audit "tools/out/$2.audit.json" --title "$2"
}
view obby-rush home_1280x720 1280 720 -
view obby-rush shop_1280x720 1280 720 Shop
view obby-rush settings_1280x720 1280 720 Settings
view obby-rush inventory_1280x720 1280 720 Inventory
view obby-rush quests_1280x720 1280 720 Quests
view obby-rush home_828x369 828 369 -
view obby-rush shop_828x369 828 369 Shop
view obby-rush home_366x820 366 820 -
view obby-rush shop_366x820 366 820 Shop
view obby-rush settings_366x820 366 820 Settings
view "$ORIG" before_home_1280x720 1280 720 -
view "$ORIG" before_shop_1280x720 1280 720 Shop
