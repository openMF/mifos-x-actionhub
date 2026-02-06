#!/bin/bash
set -euo pipefail

# REQUIRED ENV VARS:
# GITHUB_TOKEN
# TARGET=repo|org
# OWNER
# REPO (required if TARGET=repo)
# SECRET_NAME
# SECRET_VALUE

API="https://api.github.com"
AUTH="Authorization: token $GITHUB_TOKEN"
ACCEPT="Accept: application/vnd.github+json"

echo "Checking secret: $SECRET_NAME"

if [[ "$TARGET" == "repo" ]]; then
  BASE="$API/repos/$OWNER/$REPO/actions/secrets"
elif [[ "$TARGET" == "org" ]]; then
  BASE="$API/orgs/$OWNER/actions/secrets"
else
  echo "TARGET must be 'repo' or 'org'"
  exit 1
fi

# Fetch public key
pk_response=$(curl -s -H "$AUTH" -H "$ACCEPT" "$BASE/public-key")
key_id=$(echo "$pk_response" | jq -r '.key_id')
public_key=$(echo "$pk_response" | jq -r '.key')

if [[ -z "$key_id" || -z "$public_key" || "$key_id" == "null" ]]; then
  echo "Failed to fetch public key"
  exit 1
fi

# Check if secret exists
status=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "$AUTH" "$BASE/$SECRET_NAME")

if [[ "$status" == "200" ]]; then
  echo "Secret '$SECRET_NAME' already exists"
  exit 0
fi

echo "Secret missing, creating..."

# Encrypt secret 
encrypted_value=$(python3 - <<EOF
import base64
from nacl import encoding, public

pk = public.PublicKey("$public_key".encode(), encoding.Base64Encoder())
sealed_box = public.SealedBox(pk)
encrypted = sealed_box.encrypt("$SECRET_VALUE".encode())
print(base64.b64encode(encrypted).decode())
EOF
)

#  Create secret
curl -s -X PUT \
  -H "$AUTH" \
  -H "$ACCEPT" \
  "$BASE/$SECRET_NAME" \
  -d "{\"encrypted_value\":\"$encrypted_value\",\"key_id\":\"$key_id\"}"

echo "Secret '$SECRET_NAME' added successfully"
