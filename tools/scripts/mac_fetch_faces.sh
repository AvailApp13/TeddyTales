#!/bin/bash
# Запускается НА МАКЕ. Скачивает из галереи Higgsfield (аккаунт Руслана) выражения
# лица утверждённого мишки и вырезает голову: кадр 2336×3504 -> 1320×1520 со
# смещением x=520, y=480 (координаты кадра сохраняются, Claude знает смещение).
#   bash mac_fetch_faces.sh            # -> ~/vitalii/faces/*.png
set -e
OUT="$HOME/vitalii/faces"; mkdir -p "$OUT"; cd "$OUT"
B=https://d8j0ntlcm91z4.cloudfront.net/user_3FAY04WOvA0q9Qv76xACjKJ08m7
while read -r name file; do
  curl -fsSL "$B/$file" -o "full_$name.png"
  sips --cropToHeightWidth 1520 1320 --cropOffset 480 520 "full_$name.png" --out "face_$name.png" >/dev/null
  rm "full_$name.png"; echo "ok $name"
done <<'LIST'
base hf_20260923_141502_54f40bd0-45bc-43f4-8fe2-17fac08fae57.png
blink_half hf_20260924_130015_ccec24c2-76d0-4955-b821-d1e8d5c0d560.png
eyes_closed hf_20260924_130016_69d4d738-75ba-4482-a49c-0184335c6cb5.png
laugh hf_20260924_130014_3200b29b-f90a-4a6a-a93d-db206b602843.png
smile hf_20260924_130014_3bfa6cf0-c642-4d41-a25a-9a98b9fbda80.png
surprised hf_20260924_130014_a0f671b6-b3ad-43b9-a6bb-f52fb7a8dcb1.png
sad hf_20260924_130014_f42d8839-217a-41cd-baa1-5cdf2e167912.png
upset hf_20260924_130013_49c53763-df87-4de0-a3d7-fca6e9a5de1c.png
chew hf_20260924_130015_ea8565d1-9c1a-4315-b5e2-8a58dc539f47.png
yawn hf_20260924_130015_a602c866-d2c0-456e-ab9e-cce7efdde046.png
love hf_20260924_130013_fe960fe4-e376-43c3-b9e1-f150dc0490d3.png
lick hf_20260924_130014_01bacfb3-99b6-4002-bb71-ab17b4a9214e.png
squint hf_20260924_130014_04ee9e8a-de2c-46e1-bc14-4bb3a2a623f3.png
LIST
ls -la "$OUT"; open "$OUT"
