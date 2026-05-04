#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

MODE="${1:-}"
if [[ -n "$MODE" ]]; then
  shift
fi

JOBS="${CODEX_SAFE_JOBS:-2}"
MIN_FREE_GB="${CODEX_SAFE_MIN_FREE_GB:-10}"
DERIVED_DATA_PATH="${CODEX_SAFE_DERIVED_DATA_PATH:-DerivedData/CodexSafe}"
DESTINATION="${CODEX_SAFE_DESTINATION:-platform=iOS Simulator,name=iPhone 16,OS=18.6}"
DEFAULT_APP_TEST="${CODEX_SAFE_DEFAULT_APP_TEST:-MonoKnightAppTests/GameViewModelTests}"

usage() {
  cat <<'USAGE'
Usage:
  Scripts/codex-safe-validate.sh logic
  Scripts/codex-safe-validate.sh app-test [TestIdentifier ...]
  Scripts/codex-safe-validate.sh build

Environment overrides:
  CODEX_SAFE_JOBS=2
  CODEX_SAFE_MIN_FREE_GB=10
  CODEX_SAFE_DESTINATION="platform=iOS Simulator,name=iPhone 16,OS=18.6"
  CODEX_SAFE_DERIVED_DATA_PATH="DerivedData/CodexSafe"
  CODEX_SAFE_DEFAULT_APP_TEST="MonoKnightAppTests/GameViewModelTests"
USAGE
}

available_gb() {
  df -Pk "$ROOT_DIR" | awk 'NR == 2 { printf "%d", $4 / 1024 / 1024 }'
}

check_disk_for_heavy_validation() {
  local free_gb
  free_gb="$(available_gb)"
  if (( free_gb < MIN_FREE_GB )); then
    echo "Stop: free disk space is ${free_gb}GB, below the ${MIN_FREE_GB}GB safety threshold."
    echo "Skipping simulator/Xcode validation to keep the Mac stable."
    exit 2
  fi
}

run_logic_tests() {
  echo "Running low-resource package tests with ${JOBS} build jobs."
  swift test -j "$JOBS" --no-parallel
}

run_app_tests() {
  check_disk_for_heavy_validation

  local test_ids=("$@")
  if (( ${#test_ids[@]} == 0 )); then
    test_ids=("$DEFAULT_APP_TEST")
  fi

  local only_testing_args=()
  local test_id
  for test_id in "${test_ids[@]}"; do
    only_testing_args+=("-only-testing:${test_id}")
  done

  echo "Running limited app tests on ${DESTINATION}."
  xcodebuild test \
    -project MonoKnight.xcodeproj \
    -scheme MonoKnight \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -jobs "$JOBS" \
    -parallel-testing-enabled NO \
    -maximum-parallel-testing-workers 1 \
    -maximum-concurrent-test-simulator-destinations 1 \
    -collect-test-diagnostics never \
    "${only_testing_args[@]}" \
    COMPILER_INDEX_STORE_ENABLE=NO
}

run_simulator_build() {
  check_disk_for_heavy_validation

  echo "Running low-resource simulator build on ${DESTINATION}."
  xcodebuild \
    -project MonoKnight.xcodeproj \
    -scheme MonoKnight \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -jobs "$JOBS" \
    COMPILER_INDEX_STORE_ENABLE=NO \
    build
}

case "$MODE" in
  logic)
    run_logic_tests
    ;;
  app-test)
    run_app_tests "$@"
    ;;
  build)
    run_simulator_build
    ;;
  -h|--help|help|"")
    usage
    ;;
  *)
    echo "Unknown mode: ${MODE}"
    usage
    exit 64
    ;;
esac
