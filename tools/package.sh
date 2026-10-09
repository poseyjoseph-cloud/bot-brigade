#!/bin/sh
# Builds dist/BotBrigade.zip containing only the add-on folder, ready to unzip into Interface/AddOns.
set -e
cd "$(dirname "$0")/.."
rm -rf dist
mkdir -p dist
zip -r -X -q dist/BotBrigade.zip BotBrigade -x "*.DS_Store"
echo "Built dist/BotBrigade.zip"
unzip -l dist/BotBrigade.zip
