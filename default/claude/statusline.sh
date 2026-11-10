#!/usr/bin/env bash
# Claude Code status line: model, plan usage (5h/7d), context, session cost.
# Deployed to ~/.claude/statusline.sh by sandbox.sh; edit the repo copy instead.
set -u
export LC_NUMERIC=C

# Reset times use the system zone (/etc/localtime, bound into the sandbox by
# sandbox.sh); STATUSLINE_TZ overrides it.
if [ -n "${STATUSLINE_TZ:-}" ]; then
  export TZ="$STATUSLINE_TZ"
fi

IFS='|' read -r model ctx cost five five_reset week week_reset < <(
  jq -r '[
    (.model.display_name // "Claude"),
    (.context_window.used_percentage // ""),
    (.cost.total_cost_usd // ""),
    (.rate_limits.five_hour.used_percentage // ""),
    (.rate_limits.five_hour.resets_at // ""),
    (.rate_limits.seven_day.used_percentage // ""),
    (.rate_limits.seven_day.resets_at // "")
  ] | map(tostring) | join("|")'
)

dim=$'\033[2m'; green=$'\033[32m'; yellow=$'\033[33m'; red=$'\033[31m'; reset=$'\033[0m'

pct_color() {
  local p=${1%%.*}
  if   [ "${p:-0}" -ge 90 ]; then printf '%s' "$red"
  elif [ "${p:-0}" -ge 70 ]; then printf '%s' "$yellow"
  else printf '%s' "$green"; fi
}
fmt_reset() { [ -n "${1:-}" ] && date -d "@$1" "+$2" 2>/dev/null; }

out="${model:-Claude}"
if [ -n "$five" ]; then
  fr=$(fmt_reset "$five_reset" %H:%M)
  out+=" ${dim}│${reset} 5h $(pct_color "$five")$(printf '%.0f%%' "$five")${reset}"
  [ -n "$fr" ] && out+=" ${dim}↺${fr}${reset}"
fi
if [ -n "$week" ]; then
  fr=$(fmt_reset "$week_reset" "%a %H:%M")
  out+=" ${dim}│${reset} 7d $(pct_color "$week")$(printf '%.0f%%' "$week")${reset}"
  [ -n "$fr" ] && out+=" ${dim}↺${fr}${reset}"
fi
[ -n "$ctx" ]  && out+=" ${dim}│${reset} ctx $(printf '%.0f%%' "$ctx")"
[ -n "$cost" ] && out+=" ${dim}│${reset} \$$(printf '%.2f' "$cost")"

printf '%s\n' "$out"
