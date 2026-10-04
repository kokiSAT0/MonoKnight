#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

MODE="${1:-}"
if [[ -n "$MODE" ]]; then
  shift
fi

JOBS="${CODEX_SAFE_JOBS:-2}"
MIN_FREE_GB="${CODEX_SAFE_MIN_FREE_GB:-3}"
DERIVED_DATA_PATH="${CODEX_SAFE_DERIVED_DATA_PATH:-DerivedData/CodexSafe}"
DEFAULT_DESTINATION="platform=iOS Simulator,name=iPhone 16,OS=18.6"
DESTINATION="${CODEX_SAFE_DESTINATION:-$DEFAULT_DESTINATION}"
DEFAULT_APP_TEST="${CODEX_SAFE_DEFAULT_APP_TEST:-MonoKnightAppTests/PauseMenuViewTests}"
SIMULATOR_SET_ARGS=()
if [[ -n "${CODEX_SAFE_SIMULATOR_SET_PATH:-}" ]]; then
  SIMULATOR_SET_ARGS+=("-DVTSimulatorSetLocation=$CODEX_SAFE_SIMULATOR_SET_PATH")
fi

usage() {
  cat <<'USAGE'
使い方:
  Scripts/codex-safe-validate.sh logic
  Scripts/codex-safe-validate.sh app-test [TestIdentifier ...]
  Scripts/codex-safe-validate.sh build

環境変数による指定:
  CODEX_SAFE_JOBS=2
  CODEX_SAFE_MIN_FREE_GB=3
  CODEX_SAFE_DESTINATION="platform=iOS Simulator,name=iPhone 16,OS=18.6"
  CODEX_SAFE_DERIVED_DATA_PATH="DerivedData/CodexSafe"
  CODEX_SAFE_DEFAULT_APP_TEST="MonoKnightAppTests/PauseMenuViewTests"
  CODEX_SAFE_SIMULATOR_SET_PATH="/private/tmp/monoknight-simulators"

既定のシミュレーター:
  platform=iOS Simulator,name=iPhone 16,OS=18.6

注意:
  このMacではOS=latestを使わないでください。最新ランタイムにiPhone 16がない場合があります。
USAGE
}

available_gb() {
  df -Pk "$ROOT_DIR" | awk 'NR == 2 { printf "%d", $4 / 1024 / 1024 }'
}

check_disk_for_heavy_validation() {
  local free_gb
  free_gb="$(available_gb)"
  if (( free_gb < MIN_FREE_GB )); then
    echo "中止: 空き容量${free_gb}GBが必要容量${MIN_FREE_GB}GBを下回っています。"
    echo "Macの安定性を保つため、シミュレーター/Xcodeの確認を省略します。"
    exit 2
  fi
}

run_logic_tests() {
  echo "並列ビルド数${JOBS}でパッケージテストを実行します。"
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

  echo "${DESTINATION}で指定したアプリテストを実行します。"
  xcodebuild test \
    "${SIMULATOR_SET_ARGS[@]}" \
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

  echo "${DESTINATION}でシミュレーター用ビルドを実行します。"
  xcodebuild \
    "${SIMULATOR_SET_ARGS[@]}" \
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
    echo "指定されたモードがありません: ${MODE}"
    usage
    exit 64
    ;;
esac
