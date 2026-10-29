#!/usr/bin/env bash
# Déploiement FOJEM (backend :8081, dashboard :8082) — à lancer avec sudo.
# Remplace l'ancien déploiement (sauvegardé dans /var/backups), base neuve.
# Relançable : chaque étape est idempotente.
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "À lancer avec sudo."; exit 1; }

OWNER=mbaye_dose
REL=/home/$OWNER/fojem_release
API=/var/www/fojem_backend
DASH=/var/www/fojem_dashboard
DB=fojem_app
STAMP=$(date +%Y%m%d-%H%M%S)
BK=/var/backups/fojem-old-$STAMP

[ -f "$REL/backend/.env" ] && [ -d "$REL/dashboard/dist" ] || { echo "Release introuvable dans $REL"; exit 1; }

echo "==> 1/6 Sauvegarde de l'ancien déploiement dans $BK"
mkdir -p "$BK"
for d in fojem_backend fojem_dashboard; do
  if [ -e "/var/www/$d" ] && [ ! -f "/var/www/$d/.fojem_v2" ]; then
    mv "/var/www/$d" "$BK/"
    echo "    /var/www/$d -> $BK/$d"
  fi
  [ -f "/etc/nginx/sites-available/$d" ] && cp -a "/etc/nginx/sites-available/$d" "$BK/nginx-$d"
done
if crontab -u paoussou -l 2>/dev/null | grep -q fojem; then
  echo "    ATTENTION : le compte paoussou a une tâche cron FOJEM (non modifiée) :"
  crontab -u paoussou -l | grep fojem | sed 's/^/      /'
fi

echo "==> 2/6 Base PostgreSQL $DB (+ PostGIS)"
DB_PASS=$(cat "$REL/db_password")
sudo -u postgres psql -v ON_ERROR_STOP=1 -q <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '$DB') THEN
    CREATE ROLE $DB LOGIN PASSWORD '$DB_PASS';
  ELSE
    ALTER ROLE $DB LOGIN PASSWORD '$DB_PASS';
  END IF;
END
\$\$;
SQL
if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname = '$DB'" | grep -q 1; then
  sudo -u postgres createdb -O "$DB" "$DB"
fi
sudo -u postgres psql -v ON_ERROR_STOP=1 -q -d "$DB" -c "CREATE EXTENSION IF NOT EXISTS postgis"

echo "==> 3/6 Installation du code"
usermod -aG www-data "$OWNER"
install -d -o "$OWNER" -g www-data -m 2775 "$API" "$DASH"
touch "$API/.fojem_v2"
rsync -a --delete --exclude storage/ --exclude .fojem_v2 "$REL/backend/" "$API/"
mkdir -p "$API/storage"
rsync -a --ignore-existing "$REL/backend/storage/" "$API/storage/"
rsync -a --delete "$REL/dashboard/dist/" "$DASH/dist/"
install -d -m 2775 "$API/storage/app/secrets"
install -m 640 "$REL/firebase-adminsdk.json" "$API/storage/app/secrets/firebase-adminsdk.json"
touch "$API/storage/logs/laravel.log"
chown -R "$OWNER":www-data "$API" "$DASH"
chmod 640 "$API/.env"
chmod -R g+rwX "$API/storage" "$API/bootstrap/cache"
find "$API/storage" "$API/bootstrap/cache" -type d -exec chmod g+s {} +

echo "==> 4/6 Migrations, comptes admin, caches"
cd "$API"
sudo -u "$OWNER" bash -c "umask 002
  php artisan config:clear >/dev/null
  php artisan migrate --force
  ADMIN_SEED_PASSWORD='$(cat "$REL/admin_password")' php artisan db:seed --force
  php artisan storage:link >/dev/null 2>&1 || true
  php artisan config:cache && php artisan route:cache && php artisan view:cache"

echo "==> 5/6 nginx (:8081 API, :8082 dashboard)"
cat > /etc/nginx/sites-available/fojem_backend <<'NGINX'
server {
    listen 8081;
    listen [::]:8081;
    server_name _;
    root /var/www/fojem_backend/public;
    index index.php;

    # Photos (4 Mo), documents, messages vocaux (5 Mo).
    client_max_body_size 12m;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_param PHP_VALUE "upload_max_filesize=10M
post_max_size=12M";
    }

    location ~ /\.(?!well-known) {
        deny all;
    }
}
NGINX
cat > /etc/nginx/sites-available/fojem_dashboard <<'NGINX'
server {
    listen 8082;
    listen [::]:8082;
    server_name _;
    root /var/www/fojem_dashboard/dist;
    index index.html;

    location /assets/ {
        expires 30d;
        add_header Cache-Control "public, immutable";
    }

    location / {
        try_files $uri /index.html;
    }
}
NGINX
ln -sf /etc/nginx/sites-available/fojem_backend /etc/nginx/sites-enabled/fojem_backend
ln -sf /etc/nginx/sites-available/fojem_dashboard /etc/nginx/sites-enabled/fojem_dashboard
if ! nginx -t; then
  echo "nginx -t a échoué : restauration des anciennes configurations."
  for d in fojem_backend fojem_dashboard; do
    [ -f "$BK/nginx-$d" ] && cp -a "$BK/nginx-$d" "/etc/nginx/sites-available/$d"
  done
  exit 1
fi
systemctl reload nginx
systemctl reload php8.3-fpm

echo "==> 6/6 Tâche planifiée (cycle de vie des trajets, chaque minute)"
CRON="* * * * * cd $API && umask 002 && php artisan schedule:run >> /dev/null 2>&1"
( crontab -u "$OWNER" -l 2>/dev/null | grep -v 'fojem_backend && umask' || true; echo "$CRON" ) | crontab -u "$OWNER" -

echo
echo "Déploiement terminé."
echo "  API       : http://169.58.156.95:8081/up"
echo "  Dashboard : http://169.58.156.95:8082"
echo "  Admin     : super_admin@fojem.sn — mot de passe : cat $REL/admin_password"
echo "  Ancien déploiement sauvegardé dans $BK (ancienne base de données laissée intacte)."
