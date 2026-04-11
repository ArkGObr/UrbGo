#!/bin/bash
# Build de produção Android — APK e App Bundle
# Uso: ./build_android.sh [apk|bundle|both]   (padrão: both)

set -e

TARGET="${1:-both}"
ENV_FILE=".env"

if [ ! -f "$ENV_FILE" ]; then
  echo "❌ Arquivo .env não encontrado."
  exit 1
fi

SUPABASE_URL=$(grep '^SUPABASE_URL=' "$ENV_FILE" | cut -d= -f2-)
SUPABASE_ANON_KEY=$(grep '^SUPABASE_ANON_KEY=' "$ENV_FILE" | cut -d= -f2-)
ORS_API_KEY=$(grep '^ORS_API_KEY=' "$ENV_FILE" | cut -d= -f2-)

DEFINES="--dart-define=SUPABASE_URL=$SUPABASE_URL \
         --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY \
         --dart-define=ORS_API_KEY=$ORS_API_KEY"

echo "🔍 Verificando análise estática..."
flutter analyze lib/

if [ "$TARGET" = "apk" ] || [ "$TARGET" = "both" ]; then
  echo "📦 Gerando APK release..."
  flutter build apk --release $DEFINES
  echo "✅ APK: build/app/outputs/flutter-apk/app-release.apk"
  ls -lh build/app/outputs/flutter-apk/app-release.apk 2>/dev/null || true
fi

if [ "$TARGET" = "bundle" ] || [ "$TARGET" = "both" ]; then
  echo "📦 Gerando App Bundle release..."
  flutter build appbundle --release $DEFINES
  echo "✅ Bundle: build/app/outputs/bundle/release/app-release.aab"
fi

echo ""
echo "🎉 Build concluído!"
