#!/bin/bash
set -e

# Copy .env if missing
if [ ! -f .env ]; then
    echo "Creating .env from .env.example..."
    cp .env.example .env
fi

# Install dependencies if vendor is empty
if [ ! -f vendor/autoload.php ]; then
    echo "Installing Composer dependencies..."
    composer install --no-interaction --prefer-dist
fi

# Ensure APP_KEY exists
if ! grep -q "APP_KEY=base64:" .env; then
    echo "Generating Application Key..."
    php artisan key:generate --force
fi

# Wait for PostgreSQL
echo "Waiting for database connection on db:5432..."
until php -r "try { new PDO('pgsql:host=db;port=5432;dbname=fojem', 'fojem', 'fojem_local_dev'); exit(0); } catch (Exception \$e) { exit(1); }"; do
    sleep 1
done
echo "PostgreSQL is ready!"

# Run migrations and seed
echo "Running migrations..."
php artisan migrate --force

echo "Seeding database..."
php artisan db:seed --force || true

echo "Starting server..."
exec "$@"
