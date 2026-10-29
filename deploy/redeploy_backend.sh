#!/usr/bin/env bash
# Mise à jour du backend, sans sudo : à lancer en mbaye_dose sur le serveur
# après avoir envoyé ~/fojem_release/backend.tar.gz, produit sur le poste par :
#   git archive --format=tar.gz -o backend.tar.gz HEAD fojem_backend ':!fojem_backend/tests'
# Conserve .env, storage/ (uploads, clé Firebase, logs) et le lien public/storage.
set -euo pipefail

REL=~/fojem_release
API=/var/www/fojem_backend

cd "$REL"
rm -rf next && mkdir next
tar -xzf backend.tar.gz -C next
cp backend/.env next/fojem_backend/.env
(cd next/fojem_backend && composer install --no-dev --optimize-autoloader --no-interaction --no-progress)
rm -rf backend && mv next/fojem_backend backend && rmdir next

# -rlt sans -p ni -g : les fichiers prennent le groupe www-data du dossier
# (setgid) et des droits lisibles par nginx / PHP-FPM.
rsync -rlt --delete --chmod=D2775,F664 \
  --exclude storage/ --exclude .fojem_v2 --exclude public/storage \
  backend/ "$API/"
chmod 640 "$API/.env"

cd "$API"
umask 002
php artisan down --retry=15 >/dev/null || true
php artisan migrate --force
php artisan config:cache >/dev/null
php artisan route:cache >/dev/null
php artisan view:cache >/dev/null
php artisan up
curl -fsS -o /dev/null -w "API /up : %{http_code}\n" http://127.0.0.1:8081/up
