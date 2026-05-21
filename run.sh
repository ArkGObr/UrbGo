#!/bin/bash
# Script de desenvolvimento — carrega variáveis do .env

set -e

ENV_FILE=".env"

if [ ! -f "$ENV_FILE" ]; then
  echo "❌ Arquivo .env não encontrado. Crie-o com base em .env.example"
  exit 1
fi

SUPABASE_URL=$(grep '^SUPABASE_URL=' "$ENV_FILE" | cut -d= -f2-)
SUPABASE_ANON_KEY=$(grep '^SUPABASE_ANON_KEY=' "$ENV_FILE" | cut -d= -f2-)
ORS_API_KEY=$(grep '^ORS_API_KEY=' "$ENV_FILE" | cut -d= -f2-)

echo "🚀 Iniciando ArkGo em modo desenvolvimento..."

flutter run \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  --dart-define=ORS_API_KEY="$ORS_API_KEY" \
  "$@"
