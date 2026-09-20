#!/bin/bash
# Compile les deux variantes d'OpenProfalux et produit les quatre binaires d'une release,
# dans le conteneur ESP-IDF officiel. Reproductible : rien ne depend du poste.
#
#   bash scripts/release.sh            # -> dist/openprofalux-{atom,devkit}-{ota,full}.bin
#
# - atom   : M5Stack ATOM Lite (CONFIG_OPENPROFALUX_TARGET_M5STACK, celui de sdkconfig.defaults)
# - devkit : ESP32 DevKit + CC1101 externe (CONFIG_OPENPROFALUX_TARGET_EXTERNAL)
# - *-ota.bin  : l'application seule, pour l'onglet OTA et l'entite update de HA
# - *-full.bin : bootloader + table de partitions + ota_data + application, fusionnes a 0x0
#                pour une carte neuve (esptool write_flash 0x0)
# La version vient de PROJECT_VER dans firmware/CMakeLists.txt, seule declaration.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE="${IDF_IMAGE:-espressif/idf:v5.2.7}"
cd "$ROOT/firmware"
VER=$(sed -n 's/^set(PROJECT_VER "\(.*\)")/\1/p' CMakeLists.txt)
[ -n "$VER" ] || { echo "PROJECT_VER introuvable"; exit 1; }
mkdir -p "$ROOT/dist"
run() { docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -v "$ROOT/firmware":/w -w /w "$IMAGE" bash -c "$*"; }
for variant in atom devkit; do
  B="build-$variant"
  if [ "$variant" = atom ]; then D="sdkconfig.defaults"; else
    # meme base, la variante EXTERNAL remplace M5STACK (choix Kconfig)
    sed 's/^CONFIG_OPENPROFALUX_TARGET_M5STACK=y/CONFIG_OPENPROFALUX_TARGET_EXTERNAL=y/' sdkconfig.defaults > sdkconfig.devkit
    D="sdkconfig.devkit"
  fi
  echo "== $variant ($VER, $IMAGE)"
  run "idf.py -B $B -DSDKCONFIG=$B/sdkconfig -DSDKCONFIG_DEFAULTS=$D -DIDF_TARGET=esp32 build" | tail -n 3
  [ "$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['project_version'])" "$B/project_description.json")" = "$VER" ] || { echo "version compilee != $VER"; exit 1; }
  cp "$B/openprofalux.bin" "$ROOT/dist/openprofalux-$variant-ota.bin"
  run "cd $B && esptool.py --chip esp32 merge_bin -o ../../w/$B/full.bin @flash_args" >/dev/null
  cp "$B/full.bin" "$ROOT/dist/openprofalux-$variant-full.bin"
done
rm -f sdkconfig.devkit
ls -la "$ROOT/dist"/*.bin
