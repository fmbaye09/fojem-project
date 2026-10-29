#!/usr/bin/env bash
# Mise à jour du dashboard, sans sudo : à lancer en mbaye_dose sur le serveur
# après avoir envoyé ~/fojem_release/dashboard.tar.gz, produit sur le poste par :
#   (cd fojem_dashboard && npm run build && tar -czf dashboard.tar.gz dist)
set -euo pipefail

REL=~/fojem_release
DASH=/var/www/fojem_dashboard

cd "$REL"
rm -rf dashboard && mkdir dashboard
tar -xzf dashboard.tar.gz -C dashboard
rsync -rlt --delete dashboard/dist/ "$DASH/dist/"

# Lisible par nginx (www-data), quels que soient les droits de l'archive.
find "$DASH" -user "$(id -un)" -print0 | xargs -0 chgrp -h www-data
find "$DASH" -type d -user "$(id -un)" -print0 | xargs -0 chmod 2775
find "$DASH" -type f -user "$(id -un)" -print0 | xargs -0 chmod 664
curl -fsS -o /dev/null -w "Dashboard : %{http_code}\n" http://127.0.0.1:8082/
