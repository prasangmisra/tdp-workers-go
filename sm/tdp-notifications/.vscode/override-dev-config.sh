#!/bin/bash

CONFIG_PATH="$1"
BACKUP_PATH="${CONFIG_PATH}.bak"

if [[ -z "$CONFIG_PATH" ]]; then
  echo "❌ Error: No config path provided."
  exit 1
fi

# Platform-safe sed command
if [[ "$OSTYPE" == "darwin"* ]]; then
  # macOS: sed -i with empty string and NO space
  SED_INLINE() {
    sed -i '' "$1" "$2"
  }
else
  # Linux, WSL, Git Bash
  SED_INLINE() {
    sed -i "$1" "$2"
  }
fi

if [[ "$2" == "restore" ]]; then
  if [[ -f "$BACKUP_PATH" ]]; then
    mv "$BACKUP_PATH" "$CONFIG_PATH"
    echo "✅ Restored original $CONFIG_PATH"
  else
    echo "⚠️ No backup found for $CONFIG_PATH"
  fi
  exit 0
fi

# Backup once
if [[ ! -f "$BACKUP_PATH" ]]; then
  cp "$CONFIG_PATH" "$BACKUP_PATH"
  echo "📦 Backup created: $BACKUP_PATH"
else
  echo "📦 Backup already exists, skipping re-creation."
fi

echo "🔧 Applying overrides to: $CONFIG_PATH"
chmod +w "$CONFIG_PATH"

# Now the scoped replacements
SED_INLINE '/rmq:/,/^[^[:space:]]/s/^\([[:space:]]*hostname:\)[[:space:]]*.*/\1 localhost/' "$CONFIG_PATH"
SED_INLINE '/subscriptiondb:/,/^[^[:space:]]/s/^\([[:space:]]*hostname:\)[[:space:]]*.*/\1 localhost/' "$CONFIG_PATH"
SED_INLINE '/subscriptiondb:/,/^[^[:space:]]/s/^\([[:space:]]*port:\)[[:space:]]*.*/\1 5434/' "$CONFIG_PATH"
SED_INLINE '/domainsdb:/,/^[^[:space:]]/s/^\([[:space:]]*hostname:\)[[:space:]]*.*/\1 localhost/' "$CONFIG_PATH"
SED_INLINE '/domainsdb:/,/^[^[:space:]]/s/^\([[:space:]]*port:\)[[:space:]]*.*/\1 5433/' "$CONFIG_PATH"

echo "✅ Overrides applied for $CONFIG_PATH"
