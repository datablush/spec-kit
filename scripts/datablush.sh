#!/usr/bin/env bash
# Datablush from the command line: sends a spec's files to Datablush as they are on disk, so agents don't spend
# tokens repeating them. Plain bash and curl (no jq, Node or Python); bash 3.2 or later.
#
#   datablush.sh login                         connect this computer (once): shows a code to allow in Datablush
#   datablush.sh logout                        forget the connection
#   datablush.sh status                        exit 0 when connected, 2 when not
#   datablush.sh sync [options]                send the current Spec Kit feature (or --feature DIR)
#     --feature DIR                            the feature's folder (default: .specify/feature.json)
#     --constitution                           send .specify/memory/constitution.md instead
#     --command NAME                           the Spec Kit command that just ran (plan, tasks…)
#     --task KEY                               the task this feature is for (GEN-42), on its first sync
#     --brief                                  only print what needs doing next
#   datablush.sh gate                          sync, then exit 3 unless the feature's plan is approved
#
# Exit codes: 0 done · 1 failed · 2 not connected (run login) · 3 the plan isn't approved (gate).
#
# Settings (environment): DATABLUSH_API_URL (or DATABLUSH_MCP_URL, without /mcp), DATABLUSH_CONFIG_DIR,
# DATABLUSH_NO_BROWSER=1 to not open the browser on login. The same file ships in the Claude Code plugin and the
# Spec Kit extension.

set -u

API="${DATABLUSH_API_URL:-}"
[ -z "$API" ] && [ -n "${DATABLUSH_MCP_URL:-}" ] && API="${DATABLUSH_MCP_URL%/mcp}"
API="${API:-https://api-dev.datablush.com}"
API="${API%/}"
CONFIG_DIR="${DATABLUSH_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/datablush}"
HOST="$(printf '%s' "$API" | sed -E 's#^[a-z]+://##; s#[^A-Za-z0-9.-]+#_#g')"
CREDENTIALS="$CONFIG_DIR/$HOST.credentials"
EXTENSIONS='md markdown yaml yml json graphql gql proto txt'
MAX_FILE_BYTES=262144
MAX_FILES=60

say() { printf '%s\n' "$*"; }
fail() { printf 'Datablush: %s\n' "$*" >&2; exit 1; }

# A string field from a JSON object ("access_token"), without jq. Handles escaped quotes.
json_field() {
  printf '%s' "$1" | grep -oE "\"$2\"[[:space:]]*:[[:space:]]*\"(\\\\.|[^\"\\\\])*\"" | head -n1 \
    | sed -E 's/^"[^"]+"[[:space:]]*:[[:space:]]*"(.*)"$/\1/; s/\\"/"/g; s/\\\\/\\/g'
}
json_number() { printf '%s' "$1" | grep -oE "\"$2\"[[:space:]]*:[[:space:]]*[0-9]+" | head -n1 | grep -oE '[0-9]+$'; }

credential() { [ -f "$CREDENTIALS" ] && grep -E "^$1=" "$CREDENTIALS" | head -n1 | cut -d= -f2-; }
save_credentials() {
  mkdir -p "$CONFIG_DIR" && chmod 700 "$CONFIG_DIR"
  (umask 077 && printf 'ACCESS_TOKEN=%s\nREFRESH_TOKEN=%s\n' "$1" "$2" > "$CREDENTIALS")
}

# Tokens from a token response, saved; fails with the server's words otherwise.
take_tokens() {
  local access refresh
  access="$(json_field "$1" access_token)"
  refresh="$(json_field "$1" refresh_token)"
  [ -n "$access" ] && [ -n "$refresh" ] || return 1
  save_credentials "$access" "$refresh"
}

refresh_tokens() {
  local refresh response
  refresh="$(credential REFRESH_TOKEN)"
  [ -n "$refresh" ] || return 1
  response="$(curl -sS -X POST "$API/oauth/token" --data-urlencode grant_type=refresh_token --data-urlencode "refresh_token=$refresh" 2>/dev/null)" || return 1
  take_tokens "$response"
}

login() {
  local response device code page wait interval waited token error
  response="$(curl -sS -X POST "$API/oauth/device_authorization" --data-urlencode "client_name=${DATABLUSH_CLIENT_NAME:-Datablush CLI}")" || fail "couldn't reach $API"
  device="$(json_field "$response" device_code)"
  code="$(json_field "$response" user_code)"
  page="$(json_field "$response" verification_uri_complete)"
  interval="$(json_number "$response" interval)"
  wait="$(json_number "$response" expires_in)"
  [ -n "$device" ] && [ -n "$code" ] || fail "couldn't start signing in: $response"
  say "To connect this computer to Datablush, open $page"
  say "and allow it there. Check the code is $code."
  if [ -z "${DATABLUSH_NO_BROWSER:-}" ]; then
    if command -v open >/dev/null 2>&1; then open "$page" >/dev/null 2>&1; elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$page" >/dev/null 2>&1; fi
  fi
  say "Waiting…"
  interval="${interval:-5}"
  waited=0
  while [ "$waited" -lt "${wait:-600}" ]; do
    sleep "$interval"
    waited=$((waited + interval))
    token="$(curl -sS -X POST "$API/oauth/token" --data-urlencode "grant_type=urn:ietf:params:oauth:grant-type:device_code" --data-urlencode "device_code=$device" 2>/dev/null)" || continue
    if take_tokens "$token"; then
      say "Connected. Specs now sync from this computer."
      return 0
    fi
    error="$(json_field "$token" error)"
    case "$error" in
      authorization_pending) ;;
      slow_down) interval=$((interval + 5)) ;;
      access_denied) fail "not connected: it was cancelled in Datablush." ;;
      *) fail "not connected: $(json_field "$token" error_description)" ;;
    esac
  done
  fail "not connected: the code expired. Run login again."
}

# The feature folder Spec Kit is working on: SPECIFY_FEATURE_DIRECTORY, or .specify/feature.json.
current_feature() {
  if [ -n "${SPECIFY_FEATURE_DIRECTORY:-}" ]; then printf '%s' "${SPECIFY_FEATURE_DIRECTORY#./}"; return; fi
  [ -f .specify/feature.json ] && json_field "$(cat .specify/feature.json)" feature_directory | sed -E 's#^\./##; s#/+$##'
}

allowed() {
  local ext="${1##*.}" e
  ext="$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')"
  for e in $EXTENSIONS; do [ "$e" = "$ext" ] && return 0; done
  return 1
}

sync() {
  local feature="" constitution="" command="" task="" brief="" gate="" root repository branch commit
  while [ $# -gt 0 ]; do
    case "$1" in
      --feature) feature="${2:-}"; shift ;;
      --constitution) constitution=1 ;;
      --command) command="${2:-}"; shift ;;
      --task) task="${2:-}"; shift ;;
      --brief) brief=1 ;;
      --gate) gate=1 ;;
      *) fail "unknown option $1" ;;
    esac
    shift
  done

  root="$(git rev-parse --show-toplevel 2>/dev/null)" || fail "run this inside the repository"
  cd "$root" || exit 1
  repository="$(git remote get-url origin 2>/dev/null)"
  [ -n "$repository" ] || fail "this repository has no origin remote"
  [ -n "$(credential ACCESS_TOKEN)" ] || { say "Datablush isn't connected on this computer yet: run login (once)."; exit 2; }

  local folder files=() file rel size count=0 skipped=""
  if [ -n "$constitution" ]; then
    folder=".specify/memory"
    [ -f "$folder/constitution.md" ] || fail "there's no $folder/constitution.md"
    files=("constitution.md")
  else
    feature="${feature:-$(current_feature)}"
    feature="${feature#./}"
    feature="${feature%/}"
    case "$feature" in /*) feature="${feature#"$root"/}" ;; esac
    [ -n "$feature" ] || fail "no current Spec Kit feature (.specify/feature.json): pass --feature specs/003-…"
    [ -d "$feature" ] || fail "there's no folder $feature"
    folder="$feature"
    while IFS= read -r file; do
      rel="${file#"$folder"/}"
      if ! allowed "$rel"; then continue; fi
      size="$(wc -c < "$file" | tr -d ' ')"
      if [ "$size" -gt "$MAX_FILE_BYTES" ]; then skipped="$skipped $rel"; continue; fi
      [ "$count" -ge "$MAX_FILES" ] && { skipped="$skipped $rel"; continue; }
      files+=("$rel")
      count=$((count + 1))
    done < <(find "$folder" -type f ! -path '*/.*' | LC_ALL=C sort)
    [ "${#files[@]}" -gt 0 ] || fail "$folder has no files to send"
  fi

  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
  # The commit, only when the folder matches it.
  commit=""
  if git diff --quiet HEAD -- "$folder" 2>/dev/null && [ -z "$(git ls-files --others --exclude-standard -- "$folder" 2>/dev/null)" ]; then commit="$(git rev-parse HEAD 2>/dev/null)"; fi

  local args=(-F "repository=$repository" -F "path=$folder" -F "complete=true")
  [ -n "$command" ] && args+=(-F "command=$command")
  [ -n "$task" ] && args+=(-F "task=$task")
  [ -n "$branch" ] && [ "$branch" != "HEAD" ] && args+=(-F "branch=$branch")
  [ -n "$commit" ] && args+=(-F "commit=$commit")
  for rel in "${files[@]}"; do args+=(-F "file:$rel=@\"$folder/$rel\";type=text/plain"); done

  local format="text" headers body status plan attempt
  [ -n "$brief" ] && format="brief"
  headers="$(mktemp)"
  for attempt in 1 2; do
    body="$(curl -sS -D "$headers" -w '\n%{http_code}' -X POST "$API/specs/upload?format=$format" -H "Authorization: Bearer $(credential ACCESS_TOKEN)" "${args[@]}")" || { rm -f "$headers"; fail "couldn't reach $API"; }
    status="${body##*$'\n'}"
    body="${body%$'\n'*}"
    [ "$status" = "401" ] && [ "$attempt" = 1 ] && refresh_tokens && continue
    break
  done
  plan="$(grep -i '^datablush-plan:' "$headers" | tr -d '\r' | sed -E 's/^[^:]+:[[:space:]]*//')"
  rm -f "$headers"
  if [ "$status" = "401" ]; then say "Datablush's connection on this computer has ended: run login again."; exit 2; fi
  if [ "$status" != "200" ]; then
    local message
    message="$(json_field "$body" message)"
    fail "${message:-$body} ($status)"
  fi
  [ -n "$body" ] && say "$body"
  [ -n "$skipped" ] && say "Not sent (too big, or over $MAX_FILES files):$skipped"
  if [ -n "$gate" ] && [ "$plan" != "approved" ]; then exit 3; fi
  return 0
}

case "${1:-}" in
  login) login ;;
  status) if [ -n "$(credential ACCESS_TOKEN)" ]; then say "Connected to $API."; else say "Not connected to $API: run login."; exit 2; fi ;;
  logout) rm -f "$CREDENTIALS" && say "Disconnected this computer (the connection stays listed in Datablush until you remove it there)." ;;
  sync) shift; sync "$@" ;;
  gate) shift; sync --gate "$@" ;;
  *) sed -n '2,21p' "$0" | sed -E 's/^# ?//'; exit 1 ;;
esac
