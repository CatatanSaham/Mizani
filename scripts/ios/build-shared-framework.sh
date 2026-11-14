#!/bin/sh
set -eu

if [ "${OVERRIDE_KOTLIN_BUILD_IDE_SUPPORTED:-NO}" = "YES" ]; then
  echo "Skipping Gradle build task invocation because the Kotlin IDE integration already built the framework."
  exit 0
fi

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)

is_supported_java_home() {
  candidate_home=$1
  [ -x "$candidate_home/bin/java" ] || return 1

  candidate_version=$("$candidate_home/bin/java" -version 2>&1 | sed -n '1s/.*version "\([0-9][0-9]*\).*/\1/p')
  case "$candidate_version" in
    ''|*[!0-9]*) return 1 ;;
  esac

  [ "$candidate_version" -ge 17 ]
}

find_java_home() {
  for candidate in \
    "${JAVA_HOME:-}" \
    "${ANDROID_STUDIO_JDK:-}" \
    "/Applications/Android Studio.app/Contents/jbr/Contents/Home" \
    "$HOME/Applications/Android Studio.app/Contents/jbr/Contents/Home"; do
    if [ -n "$candidate" ] && is_supported_java_home "$candidate"; then
      JAVA_HOME=$candidate
      export JAVA_HOME
      return 0
    fi
  done

  if [ -x /usr/libexec/java_home ]; then
    candidate=$(/usr/libexec/java_home -v '17+' 2>/dev/null || true)
    if [ -n "$candidate" ] && is_supported_java_home "$candidate"; then
      JAVA_HOME=$candidate
      export JAVA_HOME
      return 0
    fi
  fi

  return 1
}

if ! find_java_home; then
  echo "Mizani needs a JDK 17 or newer to start Gradle from Xcode." >&2
  echo "Install Android Studio or a JDK, then set JAVA_HOME or ANDROID_STUDIO_JDK." >&2
  exit 1
fi

export PATH="$JAVA_HOME/bin:$PATH"
cd "$PROJECT_ROOT"
exec /bin/sh ./gradlew :shared:embedAndSignAppleFrameworkForXcode
