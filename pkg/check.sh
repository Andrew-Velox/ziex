#!/bin/bash
set -euo pipefail

# Smoke-tests @ziex/cli and ziex packages by publishing to a local
# Verdaccio registry and verifying that the CLI binary works.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/.."
VERDACCIO_DIR="$SCRIPT_DIR/@ziex"
REGISTRY="http://localhost:4873"
VERSION="${1:-}"
IS_WINDOWS=false
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) IS_WINDOWS=true ;; esac

RESULTS_DIR=$(mktemp -d)

publish_idempotent() {
  local pkg="$1"; shift
  local out
  if out=$(npm publish --access public --tag dev --registry "$REGISTRY" "$@" 2>&1); then
    echo "$out"
    return 0
  fi
  echo "$out"
  if echo "$out" | grep -qiE 'E409|already present|cannot publish over'; then
    echo "==> $pkg already present at this version; ensuring dist-tag and continuing"
    # Best-effort: keep the 'dev' dist-tag pointed at this version. Don't fail
    # the smoke test if even this is a no-op.
    npm dist-tag add "${pkg}@${VERSION}" dev --registry "$REGISTRY" 2>&1 || true
    return 0
  fi
  echo "==> Publish failed for $pkg (not a conflict)" >&2
  return 1
}

cleanup() {
  if [ -n "${VERDACCIO_PID:-}" ]; then
    kill "$VERDACCIO_PID" 2>/dev/null || true
    wait "$VERDACCIO_PID" 2>/dev/null || true
  fi
  rm -rf "$SCRIPT_DIR/_check_tmp" "$SCRIPT_DIR/_check_npmrc" "$RESULTS_DIR"
}
trap cleanup EXIT

# Resolve expected version
if [ -z "$VERSION" ]; then
  VERSION=$(sed -n 's/.*\.version *= *"\([^"]*\)".*/\1/p' "$ROOT_DIR/build.zig.zon")
fi
echo "==> Checking packages at version $VERSION"

# Use a clean .npmrc scoped to this script so CI's global auth config
# (written by setup-node) doesn't interfere with local Verdaccio.
export npm_config_userconfig="$SCRIPT_DIR/_check_npmrc"
cat > "$npm_config_userconfig" <<EOF
registry=$REGISTRY
//localhost:4873/:_authToken=local-dev-token
EOF

# Start Verdaccio only if not running in CI
if [ -z "${CI:-}" ]; then
  echo "==> Starting local registry..."
  rm -rf "$VERDACCIO_DIR/.verdaccio-storage"
  npx --yes verdaccio --config "$VERDACCIO_DIR/verdaccio.yaml" --listen 4873 &
  VERDACCIO_PID=$!

  for i in $(seq 1 120); do
    if curl -sf "$REGISTRY/-/ping" > /dev/null 2>&1; then break; fi
    sleep 0.5
  done
else
  echo "==> Skipping Verdaccio startup in CI"
fi

# Publish @ziex/cli* packages to local registry.
# --workspaces publishes all @ziex/cli* at once; if some are already present
# (E409 on re-run), that's fine for a smoke test — tolerate it and continue.
echo "==> Publishing @ziex/cli* to local registry..."
cd "$VERDACCIO_DIR"
cli_out=$(npm publish --workspaces --access public --tag dev --registry "$REGISTRY" 2>&1) || true
echo "$cli_out"
# Fail only on an npm error code that is NOT 409 (already present). This way a
# real error still fails even if other packages in the batch merely conflicted.
if echo "$cli_out" | grep -oiE 'E[0-9]{3}' | grep -qvi 'E409'; then
  echo "==> @ziex/cli* publish failed with a non-conflict error" >&2
  exit 1
fi

# Build and publish ziex to local registry (skip on Windows - bun build crashes)
if [ "$IS_WINDOWS" = false ]; then
  echo "==> Building and publishing ziex to local registry..."
  cd "$SCRIPT_DIR/ziex"
  rm -f bun.lock
  BUN_CONFIG_REGISTRY="$REGISTRY" bun install --registry "$REGISTRY" 2>&1
  bun run build
  cd dist
  publish_idempotent ziex
else
  echo "==> Skipping ziex build on Windows (bun build not supported)"
fi

# Create temp directory for testing
# Use a fresh temp dir to avoid npx/bunx cache interference
rm -rf "$SCRIPT_DIR/_check_tmp"
mkdir -p "$SCRIPT_DIR/_check_tmp"
cd "$SCRIPT_DIR/_check_tmp"
export npm_config_cache="$SCRIPT_DIR/_check_tmp/.npm-cache"

# Test runner - writes PASS/FAIL to $RESULTS_DIR so tests can run in parallel
check() {
  local name="$1" cmd="$2" expected="$3"
  local safe_name="${name//[\/[:space:]]/_}"
  local output
  output=$(eval "$cmd" 2>&1) || true
  if echo "$output" | grep -q "$expected"; then
    echo "PASS" > "$RESULTS_DIR/$safe_name"
    echo "  PASS: $name"
  else
    echo "FAIL" > "$RESULTS_DIR/$safe_name"
    echo "  FAIL: $name - expected '$expected', got: $output"
  fi
}

# --- Tests (run in parallel) ---

echo ""
echo "Running checks..."
echo ""

pids=()

# @ziex/cli via npx
check "npx @ziex/cli version" \
  "npx --yes --registry '$REGISTRY' @ziex/cli@dev version" \
  "$VERSION" &
pids+=($!)

# ziex via npx (skip on Windows - not built)
if [ "$IS_WINDOWS" = false ]; then
  check "npx ziex version" \
    "npx --yes --registry '$REGISTRY' ziex@dev version" \
    "$VERSION" &
  pids+=($!)

  check "npx ziex --help" \
    "npx --yes --registry '$REGISTRY' ziex@dev --help" \
    "." &
  pids+=($!)
fi

# bunx compatibility
if command -v bunx &> /dev/null; then
  check "bunx @ziex/cli version" \
    "env BUN_CONFIG_REGISTRY='$REGISTRY' BUN_CONFIG_IGNORE_SCRIPTS=true bunx --verbose @ziex/cli@dev version" \
    "$VERSION" &
  pids+=($!)

  if [ "$IS_WINDOWS" = false ]; then
    check "bunx ziex version" \
      "env BUN_CONFIG_REGISTRY='$REGISTRY' BUN_CONFIG_IGNORE_SCRIPTS=true bunx --verbose ziex@dev version" \
      "$VERSION" &
    pids+=($!)
  fi
fi

for pid in "${pids[@]}"; do wait "$pid" || true; done

# --- Summary ---

PASSED=$( (grep -rl "PASS" "$RESULTS_DIR" 2>/dev/null || true) | wc -l | tr -d ' ')
FAILED=$( (grep -rl "FAIL" "$RESULTS_DIR" 2>/dev/null || true) | wc -l | tr -d ' ')

echo ""
echo "  Results: $PASSED passed, $FAILED failed"

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
