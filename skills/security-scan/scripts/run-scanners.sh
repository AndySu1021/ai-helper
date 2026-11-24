#!/usr/bin/env bash
# 依 .pipeline/config.yaml 執行安全掃描工具，結果輸出至 tmp/.security-raw/

set -euo pipefail

CONFIG=".pipeline/config.yaml"
OUTPUT_DIR="tmp/.security-raw"
mkdir -p "$OUTPUT_DIR"

# 從 config.yaml 讀取設定（若無則使用預設值）
LANGUAGE=$(grep -E "^\s+language:" "$CONFIG" 2>/dev/null | awk '{print $2}' | tr -d '"' || echo "go")
GITLEAKS_ENABLED=$(grep -E "^\s+gitleaks:" "$CONFIG" 2>/dev/null | awk '{print $2}' || echo "true")
SEMGREP_RULES=$(grep -E "^\s+semgrep_rules:" "$CONFIG" 2>/dev/null | awk '{print $2}' | tr -d '"' || echo "")
BASE_BRANCH=$(grep -E "^\s+base_branch:" "$CONFIG" 2>/dev/null | awk '{print $2}' | tr -d '"' || echo "main")

# DEP_SCAN_CMD 從 config 讀取，但不直接 eval — 只允許白名單指令
DEP_SCAN_RAW=$(grep -E "^\s+dependency_scan:" "$CONFIG" 2>/dev/null | sed 's/.*dependency_scan:[[:space:]]*//' | tr -d '"' || echo "")

echo "=== Security Scanner ==="
echo "Language: $LANGUAGE"
echo "Output: $OUTPUT_DIR"
echo ""

# 路徑存在驗證（防止後續步驟靜默讀取到空目錄）
if [ ! -d "$OUTPUT_DIR" ]; then
  echo "❌ 無法建立輸出目錄 $OUTPUT_DIR，中止掃描。" >&2
  exit 1
fi

# ——— gitleaks ———
if [ "$GITLEAKS_ENABLED" = "true" ]; then
  if command -v gitleaks &>/dev/null; then
    echo "[gitleaks] 執行工作目錄掃描..."
    # 區分「工具有發現問題（exit 1）」和「工具本身崩潰（exit 2+）」
    set +e
    gitleaks detect --source . --report-format json \
      --report-path "$OUTPUT_DIR/gitleaks.json" 2>"$OUTPUT_DIR/gitleaks-stderr.txt"
    GITLEAKS_EXIT=$?
    set -e
    if [ $GITLEAKS_EXIT -eq 0 ]; then
      echo "[gitleaks] 未發現問題"
    elif [ $GITLEAKS_EXIT -eq 1 ]; then
      echo "[gitleaks] 發現敏感資訊，詳見 gitleaks.json"
    else
      echo "[gitleaks] 工具執行失敗（exit $GITLEAKS_EXIT）" | tee "$OUTPUT_DIR/gitleaks-error.txt"
      cat "$OUTPUT_DIR/gitleaks-stderr.txt" >> "$OUTPUT_DIR/gitleaks-error.txt" 2>/dev/null || true
    fi

    echo "[gitleaks] 執行 git history 掃描（origin/${BASE_BRANCH}..HEAD）..."
    set +e
    gitleaks detect --source . \
      --log-opts="origin/${BASE_BRANCH}..HEAD" \
      --report-format json \
      --report-path "$OUTPUT_DIR/gitleaks-history.json" 2>"$OUTPUT_DIR/gitleaks-history-stderr.txt"
    GITLEAKS_HIST_EXIT=$?
    set -e
    if [ $GITLEAKS_HIST_EXIT -eq 0 ]; then
      echo "[gitleaks history] 未發現問題"
    elif [ $GITLEAKS_HIST_EXIT -eq 1 ]; then
      echo "[gitleaks history] ⚠️  git history 中發現敏感資訊，詳見 gitleaks-history.json"
    else
      echo "[gitleaks history] 工具執行失敗（exit $GITLEAKS_HIST_EXIT）" | tee "$OUTPUT_DIR/gitleaks-history-error.txt"
    fi
  else
    echo "[gitleaks] 未安裝，略過" | tee "$OUTPUT_DIR/gitleaks-skipped.txt"
  fi
fi

# ——— semgrep ———
if command -v semgrep &>/dev/null; then
  echo "[semgrep] 執行中..."
  if [ -z "$SEMGREP_RULES" ]; then
    # 依語言選擇預設規則集（包含安全規則）
    case "$LANGUAGE" in
      go)         SEMGREP_RULES="p/golang,p/security-audit" ;;
      python)     SEMGREP_RULES="p/python,p/security-audit" ;;
      typescript) SEMGREP_RULES="p/typescript,p/security-audit" ;;
      javascript) SEMGREP_RULES="p/javascript,p/security-audit" ;;
      *)          SEMGREP_RULES="p/security-audit" ;;
    esac
  fi
  set +e
  semgrep --config "$SEMGREP_RULES" --json \
    --output "$OUTPUT_DIR/semgrep.json" . 2>"$OUTPUT_DIR/semgrep-stderr.txt"
  SEMGREP_EXIT=$?
  set -e
  if [ $SEMGREP_EXIT -eq 0 ] || [ $SEMGREP_EXIT -eq 1 ]; then
    echo "[semgrep] 完成（exit $SEMGREP_EXIT）"
  else
    echo "[semgrep] 工具執行失敗（exit $SEMGREP_EXIT）" | tee "$OUTPUT_DIR/semgrep-error.txt"
    cat "$OUTPUT_DIR/semgrep-stderr.txt" >> "$OUTPUT_DIR/semgrep-error.txt" 2>/dev/null || true
  fi
else
  echo "[semgrep] 未安裝，略過" | tee "$OUTPUT_DIR/semgrep-skipped.txt"
fi

# ——— 依賴漏洞掃描 ———
# 使用白名單比對，不使用 eval，防止 command injection
run_dep_scan() {
  local cmd="$1"
  local outfile="$2"
  set +e
  case "$cmd" in
    "govulncheck ./..."*)
      govulncheck ./... > "$outfile" 2>&1
      ;;
    "npm audit"*)
      npm audit --json > "$outfile" 2>&1
      ;;
    "pip-audit"*)
      pip-audit --format json > "$outfile" 2>&1
      ;;
    "pip-audit --format json"*)
      pip-audit --format json > "$outfile" 2>&1
      ;;
    *)
      echo "不支援的依賴掃描指令：$cmd（白名單：govulncheck、npm audit、pip-audit）" | tee "${outfile%.txt}-unsupported.txt"
      set -e
      return
      ;;
  esac
  DEP_EXIT=$?
  set -e
  if [ $DEP_EXIT -gt 1 ]; then
    echo "[dependency] 工具執行失敗（exit $DEP_EXIT）" | tee "${outfile%.txt}-error.txt"
  fi
}

if [ -n "$DEP_SCAN_RAW" ]; then
  echo "[dependency] 執行設定中的指令: $DEP_SCAN_RAW"
  run_dep_scan "$DEP_SCAN_RAW" "$OUTPUT_DIR/dependency.txt"
  echo "[dependency] 完成"
else
  # 依語言選擇預設工具
  case "$LANGUAGE" in
    go)
      if command -v govulncheck &>/dev/null; then
        echo "[govulncheck] 執行中..."
        run_dep_scan "govulncheck ./..." "$OUTPUT_DIR/govulncheck.txt"
        echo "[govulncheck] 完成"
      else
        echo "[govulncheck] 未安裝，略過" | tee "$OUTPUT_DIR/govulncheck-skipped.txt"
      fi
      ;;
    typescript|javascript)
      if command -v npm &>/dev/null && [ -f "package.json" ]; then
        echo "[npm audit] 執行中..."
        run_dep_scan "npm audit" "$OUTPUT_DIR/npm-audit.json"
        echo "[npm audit] 完成"
      else
        echo "[npm audit] 未可用，略過" | tee "$OUTPUT_DIR/npm-audit-skipped.txt"
      fi
      ;;
    python)
      if command -v pip-audit &>/dev/null; then
        echo "[pip-audit] 執行中..."
        run_dep_scan "pip-audit --format json" "$OUTPUT_DIR/pip-audit.json"
        echo "[pip-audit] 完成"
      else
        echo "[pip-audit] 未安裝，略過" | tee "$OUTPUT_DIR/pip-audit-skipped.txt"
      fi
      ;;
  esac
fi

# ——— 彙整執行狀態 ———
echo ""
echo "=== 掃描完成，結果存於 $OUTPUT_DIR ==="

# 若有任何 error 檔案，輸出警告供 security-scan SKILL 判斷
ERROR_FILES=$(find "$OUTPUT_DIR" -name "*-error.txt" 2>/dev/null | wc -l | tr -d ' ')
if [ "$ERROR_FILES" -gt 0 ]; then
  echo "⚠️  有 $ERROR_FILES 個工具執行失敗，部分結果可能不完整："
  find "$OUTPUT_DIR" -name "*-error.txt" | while IFS= read -r f; do echo "  - $f"; done
  # 寫入統一標記供 SKILL.md 判讀
  echo "scan_error: true" > "$OUTPUT_DIR/scan-status.txt"
  echo "failed_tools: $ERROR_FILES" >> "$OUTPUT_DIR/scan-status.txt"
else
  echo "scan_error: false" > "$OUTPUT_DIR/scan-status.txt"
fi
