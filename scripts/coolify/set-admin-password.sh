#!/bin/bash
# Sets the password of an existing internal user. On a fresh production install the
# setup job seeds a workspace admin (glinda@emeraldcity.oz) without a usable password,
# and the server only provisions one in development, so run this once after the first
# deploy from a shell in the `server` container (Coolify: the app's Terminal tab):
#
#   bash /app/coolify/set-admin-password.sh [email]
#
# The password is read from the terminal (or stdin) and never echoed or logged.
set -euo pipefail

EMAIL="${1:-glinda@emeraldcity.oz}"

read -r -s -p "New password for ${EMAIL}: " PW; echo
read -r -s -p "Repeat password: " PW2; echo
[ "$PW" = "$PW2" ] || { echo "Passwords do not match." >&2; exit 1; }
[ "${#PW}" -ge 12 ] || { echo "Use at least 12 characters." >&2; exit 1; }

# Mirrors hashPassword() in packages/core/src/lib/encryption.ts: PBKDF2 over
# (nextauth_secret + random hex salt), stored as "salt:hash".
HASH=$(PW="$PW" node -e '
  const crypto = require("crypto");
  const fs = require("fs");
  // Trimmed like the filesystem secret provider; env wins when set, as in the read chain.
  const key = (process.env.NEXTAUTH_SECRET
    || (fs.existsSync("/run/secrets/nextauth_secret")
      ? fs.readFileSync("/run/secrets/nextauth_secret", "utf8")
      : "")).trim();
  if (!key) { console.error("nextauth_secret not found"); process.exit(1); }
  const saltBytes = Number(process.env.SALT_BYTES) || 12;
  const iterations = Number(process.env.ITERATIONS) || 10000;
  const keyLength = Number(process.env.KEY_LENGTH) || 64;
  const algo = (process.env.ALGORITHM || "sha512").toLowerCase().replace("-", "");
  const digest = algo === "sha256" ? "sha256" : "sha512";
  const salt = crypto.randomBytes(saltBytes).toString("hex");
  const hash = crypto.pbkdf2Sync(process.env.PW, key + salt, iterations, keyLength, digest).toString("hex");
  process.stdout.write(salt + ":" + hash);
')
unset PW PW2

UPDATED=$(PGPASSWORD="$(cat /run/secrets/db_password_server)" psql -X -q -t -A -v ON_ERROR_STOP=1 \
  -h "${DB_HOST:-pgbouncer}" -p "${DB_PORT:-6432}" \
  -U "${DB_USER_SERVER:-app_user}" -d "${DB_NAME_SERVER:-server}" \
  -v hash="$HASH" -v email="$EMAIL" <<'SQL'
UPDATE users SET hashed_password = :'hash'
WHERE lower(email) = lower(:'email') AND user_type = 'internal'
RETURNING username;
SQL
)

if [ -z "$UPDATED" ]; then
  echo "No internal user with email ${EMAIL} was found." >&2
  exit 1
fi
echo "Password updated for ${EMAIL} (username: ${UPDATED})."
