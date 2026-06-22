#!/bin/bash
# ChipCraft Lab — Sync encrypted files to GitHub repo
#
# Usage:
#   bash sync_labs.sh <source-folder> <destination-folder>
#
# Examples:
#   bash sync_labs.sh ~/labs/ ~/chipcraft-lab-files/
#   bash sync_labs.sh /home/user/labs/ /home/user/chipcraft-lab-files/

if [[ -z "${1:-}" || -z "${2:-}" ]]; then
    echo ""
    echo "Usage  : bash sync_labs.sh <source-folder> <destination-folder>"
    echo ""
    echo "Example: bash sync_labs.sh ~/labs/ ~/chipcraft-lab-files/"
    echo ""
    exit 1
fi

SOURCE="$1"
DEST="$2"

if [[ ! -d "$SOURCE" ]]; then
    echo "ERROR: Source folder not found: $SOURCE"
    exit 1
fi

if [[ ! -d "$DEST" ]]; then
    echo "ERROR: Destination folder not found: $DEST"
    echo "Run  : git clone https://github.com/narrave/chipcraft-lab-files.git $DEST"
    exit 1
fi

echo ""
echo "========================================"
echo "  ChipCraft Lab — Sync .enc Files"
echo "========================================"
echo "  From : $SOURCE"
echo "  To   : $DEST"
echo ""

rsync -av --delete \
    --include="*/" \
    --include="*.enc" \
    --exclude="*" \
    "$SOURCE/" \
    "$DEST/"

echo ""
echo "========================================"
echo "  Sync done! Now push to GitHub:"
echo "  cd $DEST"
echo "  git add ."
echo "  git commit -m 'Update lab files'"
echo "  git push"
echo "========================================"
echo ""
