#!/usr/bin/env bash
# Sends one message (HTML) to the ops chat, the same one Alertmanager writes to (docs/workflow.md, "Уведомления").
# Used by GitHub Actions: release PR ready, release rolled out or failed, security auto-release, rollback PR.
# Needs TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID (org secret/variable, set once by `just telegram`); without them it
# only prints a warning, so nothing else fails before the bot exists.
set -euo pipefail
text=${1:?usage: telegram.sh <html text>}
if [ -z "${TELEGRAM_BOT_TOKEN:-}" ] || [ -z "${TELEGRAM_CHAT_ID:-}" ]; then
  echo "::warning::Telegram is not configured (just telegram); not sent: ${text//$'\n'/ }"
  exit 0
fi
curl -fsS "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -d chat_id="$TELEGRAM_CHAT_ID" -d parse_mode=HTML -d disable_web_page_preview=true \
  --data-urlencode text="$text" >/dev/null
echo "sent to Telegram"
