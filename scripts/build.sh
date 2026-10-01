#!/usr/bin/env bash
#
# Build every Meltorama artifact this host can build, and print one summary.
# The single local entry point; CI builds the same artifacts in
# .github/workflows/ci.yml and release.yml.
#
#   apk — Android APK via Gradle (needs a JDK and an Android SDK)
#   app — macOS Meltorama.app via scripts/build-macos.sh (needs macOS and
#         Xcode or the command line tools)
#
# Usage:
#   scripts/build.sh                 # every target this host can build
#   scripts/build.sh apk             # just this one (naming a target turns an
#                                    # infeasible target into an error, not a skip)
#   scripts/build.sh --debug         # debug builds instead of release
#   scripts/build.sh --clean         # wipe build output first
#   scripts/build.sh --run           # launch the built Mac app
#   scripts/build.sh --install       # build the Mac app and install it into
#                                    # /Applications, then reveal it
#   scripts/build.sh --check         # print resolved config; build nothing
#
# Produced artifacts land in dist/ — goo-v<version>-*.apk and
# meltorama-macos-<version>.zip plus Meltorama.app itself.
#
# The lkm-build engine (https://github.com/L-K-M/release-tool) has no Gradle
# kind, so this is a self-contained orchestrator in the family house style;
# the `app` target delegates to scripts/build-macos.sh.
set -uo pipefail

# Absolute self-path first: usage() re-opens the script, which a relative $0
# would no longer find after the cd below.
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

usage() { awk 'NR==1 && /^#!/ {next} /^#/ {sub(/^# ?/,""); print; next} {exit}' "$SELF"; exit "${1:-0}"; }

PROFILE="release"
CLEAN=false
INSTALL=false
RUN=false
CHECK=false
declare -a REQUESTED=()
EXPLICIT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage 0 ;;
    --debug) PROFILE="debug"; shift ;;
    --clean) CLEAN=true; shift ;;
    --install) INSTALL=true; shift ;;
    --run) RUN=true; shift ;;
    --check) CHECK=true; shift ;;
    apk|app) REQUESTED+=("$1"); EXPLICIT=1; shift ;;
    all) REQUESTED=(apk app); EXPLICIT=1; shift ;;
    *) echo "!! unknown argument: $1" >&2; usage 1 ;;
  esac
done

# --install and --run are about the Mac app: with no explicit targets they
# build just that, and with explicit targets they make sure `app` is among them.
if $INSTALL || $RUN; then
  if [[ ${#REQUESTED[@]} -eq 0 ]]; then
    REQUESTED=(app); EXPLICIT=1
  else
    found=0
    for t in "${REQUESTED[@]}"; do [[ "$t" == "app" ]] && found=1; done
    [[ $found -eq 0 ]] && REQUESTED+=(app)
  fi
fi

[[ ${#REQUESTED[@]} -eq 0 ]] && REQUESTED=(apk app)

case "$(uname -s)" in
  Darwin) HOST="macos" ;;
  Linux) HOST="linux" ;;
  MINGW*|MSYS*|CYGWIN*) HOST="windows" ;;
  *) HOST="unknown" ;;
esac

# The committed version, read from the same file release.yml's gate reads.
VERSION="$(sed -nE 's/^[[:space:]]*versionName[[:space:]]*=[[:space:]]*"([^"]*)".*$/\1/p' app/build.gradle.kts | head -n 1)"
[[ -n "$VERSION" ]] || VERSION="unknown"
# VERSION becomes part of staged artifact names; refuse anything that could
# escape dist/.
[[ "$VERSION" =~ ^[0-9A-Za-z.-]+$ || "$VERSION" == "unknown" ]] \
  || { echo "!! versionName '$VERSION' is not safe for artifact names" >&2; exit 1; }

echo "Meltorama build"
echo "  host:    $HOST ($(uname -s))"
echo "  profile: $PROFILE"
echo "  version: $VERSION"
echo "  targets: ${REQUESTED[*]}"
echo

have() { command -v "$1" >/dev/null 2>&1; }

declare -a RESULTS=()
record() { RESULTS+=("$1"); }

DIST="$ROOT/dist"
STAGED=0
stage() {
  local src="$1"
  local name="${2:-$(basename "$1")}"
  mkdir -p "$DIST" || return 1
  rm -rf "${DIST:?}/$name" || return 1
  cp -R "$src" "$DIST/$name" || return 1
  STAGED=$((STAGED + 1))
  echo "-- staged dist/$name"
}

was_named() {
  [[ $EXPLICIT -eq 1 ]] || return 1
  local t
  for t in "${REQUESTED[@]}"; do [[ "$t" == "$1" ]] && return 0; done
  return 1
}

# Skip a target: a soft skip on a default run, a hard error when named.
skip_or_fail() {
  local target="$1" reason="$2"
  if was_named "$target"; then
    echo "!! $target: cannot build on this host — $reason" >&2
    record "$target: FAILED ($reason)"
    return 1
  fi
  echo ".. $target: skipped — $reason"
  record "$target: skipped ($reason)"
  return 0
}

# What separates "can build the APK" from a long doomed Gradle run.
detect_android_sdk() {
  local c
  for c in "${ANDROID_SDK_ROOT:-}" "${ANDROID_HOME:-}" \
           "$HOME/Library/Android/sdk" "$HOME/Android/Sdk"; do
    [[ -n "$c" && -d "$c/platforms" ]] && { echo "$c"; return 0; }
  done
  # A committed-free local.properties is the other supported way to point
  # Gradle at an SDK, and it wins over the environment for the Gradle run.
  if [[ -f local.properties ]] && grep -q '^sdk\.dir=' local.properties; then
    sed -nE 's/^sdk\.dir=(.*)$/\1/p' local.properties | head -n 1
    return 0
  fi
  return 1
}

# ---------------------------------------------------------------------------
build_apk() {
  echo "== apk (Android) =="

  local task apk out
  if [[ "$PROFILE" == "release" ]]; then
    task="assembleRelease"
    apk="app/build/outputs/apk/release/app-release.apk"
    out="goo-v$VERSION-release.apk"
  else
    task="assembleDebug"
    apk="app/build/outputs/apk/debug/app-debug.apk"
    out="goo-v$VERSION-debug.apk"
  fi

  if $CHECK; then
    echo "-- would run: ./gradlew $task"
    echo "-- would stage: dist/$out"
    record "apk: checked (would build $task)"
    return 0
  fi

  if ! have java; then skip_or_fail apk "no JDK on PATH (java)"; return; fi
  local sdk
  if ! sdk="$(detect_android_sdk)"; then
    skip_or_fail apk "no Android SDK found (set ANDROID_HOME, or write local.properties)"; return
  fi
  echo "-- Android SDK: $sdk"

  if $CLEAN; then
    echo "-- gradlew clean"
    ./gradlew clean || { record "apk: FAILED (clean)"; return 1; }
  fi

  echo "-- gradlew $task"
  if ./gradlew "$task"; then
    if [[ -f "$apk" ]]; then
      if ! stage "$apk" "$out"; then
        echo "!! apk: failed to stage $apk as dist/$out" >&2
        record "apk: FAILED (staging)"; return 1
      fi
      record "apk: built ($PROFILE) -> dist/$out"
    else
      echo "!! apk: $task succeeded but $apk is missing" >&2
      record "apk: FAILED (artifact not found)"; return 1
    fi
  else
    echo "!! apk: ./gradlew $task failed" >&2
    record "apk: FAILED (gradle)"; return 1
  fi
}

# ---------------------------------------------------------------------------
build_app() {
  echo "== app (macOS) =="

  if $CHECK; then
    echo "-- would run: scripts/build-macos.sh${PROFILE:+ $([[ "$PROFILE" == debug ]] && echo --debug)}"
    echo "-- would stage: dist/Meltorama.app + dist/meltorama-macos-$VERSION.zip"
    $INSTALL && echo "-- would install: /Applications/Meltorama.app"
    record "app: checked (would build $PROFILE)"
    return 0
  fi

  if [[ "$HOST" != "macos" ]]; then
    skip_or_fail app "macOS is required (AppKit, OpenGL, AVFoundation)"; return
  fi
  if ! have swift; then
    skip_or_fail app "no Swift toolchain — install Xcode or the command line tools"; return
  fi

  if $CLEAN; then
    echo "-- removing macos/.build"
    rm -rf macos/.build
  fi

  local -a args=()
  [[ "$PROFILE" == "debug" ]] && args+=(--debug)
  $RUN && ! $INSTALL && args+=(--launch)

  echo "-- build-macos.sh ${args[*]:-}"
  # ${args[@]+...} avoids the bash 3.2 empty-array "unbound variable" under -u.
  if ! scripts/build-macos.sh ${args[@]+"${args[@]}"}; then
    echo "!! app: build-macos.sh failed" >&2
    record "app: FAILED (build)"; return 1
  fi
  record "app: built ($PROFILE) -> dist/Meltorama.app + dist/meltorama-macos-$VERSION.zip"
  STAGED=$((STAGED + 1))

  if $INSTALL; then
    echo "-- installing /Applications/Meltorama.app"
    rm -rf "/Applications/Meltorama.app"
    # ditto preserves the signature, resource forks and permissions.
    if ! ditto "$DIST/Meltorama.app" "/Applications/Meltorama.app"; then
      echo "!! app: could not copy into /Applications (needs write permission)" >&2
      record "app: FAILED (install)"; return 1
    fi
    record "app: installed -> /Applications/Meltorama.app"
    INSTALLED="/Applications/Meltorama.app"
    $RUN && open "/Applications/Meltorama.app"
  fi
}

# ---------------------------------------------------------------------------
FAILED=0
INSTALLED=""
for target in "${REQUESTED[@]}"; do
  case "$target" in
    apk) build_apk || FAILED=1 ;;
    app) build_app || FAILED=1 ;;
  esac
  echo
done

echo "Summary"
for line in "${RESULTS[@]}"; do echo "  $line"; done

if [[ -n "$INSTALLED" ]]; then
  echo "  installed: $INSTALLED"
  [[ "$(uname -s)" == "Darwin" ]] && ! $RUN && open -R "$INSTALLED"
elif [[ "$STAGED" -gt 0 && "$HOST" == "macos" ]]; then
  echo "  artifacts: $DIST"
  open "$DIST"
fi

exit "$FAILED"
