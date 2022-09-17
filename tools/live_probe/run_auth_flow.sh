#!/usr/bin/env bash
# run_auth_flow.sh — 临时 Root 的真实演练编排（R1 身份阶段，登录闭环取证）。
#
# 做什么：在系统临时目录里开两套完全独立的测试服务（各自的资料目录与专属
# 回环端口 127.0.0.1:5288 / 5289，绝不碰 5206 或真实 evernight-data），走真实
# CLI 的一次性 Root 初始化（口令只经 stdin，随机产生、永不回显），再把两台
# 服务交给 auth_flow_probe.dart 演练：初始化后登录、错误口令、限流冷却、
# 重开式会话恢复、跨服务器时旧凭据失效与切换后的再登录。
#
# 边界：只终止本脚本自己启动的进程；清理采用有限次数重试，失败只报告残留
# 路径，不扩大删除范围。跑完即弃，两份资料目录与口令档都不保留。
# 用法（Git Bash）：bash tools/live_probe/run_auth_flow.sh [后端仓库根目录]
# 退出码：探针的退出码；任何前置步骤失败立即中止并报告。
set -u

FRONTEND_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
BACKEND_DIR="${1:-$(cd "$FRONTEND_DIR/.." && pwd)}"
PORT_A=5288
PORT_B=5289
DART="${FLUTTER_ROOT:-}/bin/dart"

fail() { echo "[ABORT] $*" >&2; exit 1; }

command -v go >/dev/null 2>&1 || fail "找不到 go 命令"
[ -x "$DART" ] || [ -f "$DART" ] || fail "找不到 dart（检查 FLUTTER_ROOT）"
[ -f "$BACKEND_DIR/go.mod" ] || fail "后端仓库根不对：$BACKEND_DIR"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/er-r1013-XXXXXX")" || fail "临时目录创建失败"
echo "临时目录：$TMP"
mkdir -p "$TMP/data-a" "$TMP/data-b"

PIDS=()
cleanup_pids() {
  for pid in "${PIDS[@]:-}"; do
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null
      for _ in 1 2 3 4 5 6 7 8 9 10; do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.3
      done
      kill -0 "$pid" 2>/dev/null && echo "[WARN] 进程 $pid 未能退出" >&2
    fi
  done
}

cleanup_tmp() {
  # 有限重试删除：Windows 句柄释放有竞态，只重试可恢复的占用类错误。
  for _ in 1 2 3 4 5; do
    rm -rf "$TMP" 2>/dev/null && { echo "临时目录已清理。"; return 0; }
    sleep 1
  done
  echo "[WARN] 临时目录残留（请手工确认归属后删除）：$TMP" >&2
}

PWFILE="$TMP/pw"
trap 'cleanup_pids; rm -f "$PWFILE" 2>/dev/null; cleanup_tmp' EXIT

python -c "import secrets,string; print(secrets.token_urlsafe(18))" > "$PWFILE" \
  || fail "口令生成失败"
chmod 600 "$PWFILE" 2>/dev/null
PW="$(cat "$PWFILE")"
[ -n "$PW" ] || fail "口令为空"

SERVER="$TMP/evernight-server.exe"
echo "构建测试服务执行档（不进版本库）…"
(cd "$BACKEND_DIR" && go build -o "$SERVER" ./cmd/evernight-server) \
  || fail "go build 失败"

wait_ready() {
  local url="$1"
  for _ in $(seq 1 60); do
    if curl -sf --max-time 2 "$url/ready" >/dev/null 2>&1; then return 0; fi
    sleep 0.5
  done
  return 1
}

start_server() {
  local data_dir="$1" port="$2" tag="$3"
  ER_SERVER_LISTEN="127.0.0.1:$port" "$SERVER" --data-dir "$data_dir" \
    > "$TMP/server-$tag.log" 2>&1 &
  PIDS+=("$!")
}

stop_last() {
  local pid="${PIDS[-1]}"
  kill "$pid" 2>/dev/null
  for _ in $(seq 1 20); do kill -0 "$pid" 2>/dev/null || break; sleep 0.3; done
  kill -0 "$pid" 2>/dev/null && fail "服务进程 $pid 未能停止"
}

echo "== A 台：migrate 与真实一次性初始化（init-root 要求服务停著）"
"$SERVER" migrate --data-dir "$TMP/data-a" || fail "A migrate 失败"
start_server "$TMP/data-a" "$PORT_A" a
wait_ready "http://127.0.0.1:$PORT_A" || fail "A 台未就绪"
stop_last
printf '%s\n%s\n' "$PW" "$PW" | "$SERVER" init-root --password-stdin --data-dir "$TMP/data-a" \
  || fail "A init-root 失败"
start_server "$TMP/data-a" "$PORT_A" a
wait_ready "http://127.0.0.1:$PORT_A" || fail "A 台重启后未就绪"

echo "== B 台：另一份独立部署（先初始化后启动）"
"$SERVER" migrate --data-dir "$TMP/data-b" || fail "B migrate 失败"
printf '%s\n%s\n' "$PW" "$PW" | "$SERVER" init-root --password-stdin --data-dir "$TMP/data-b" \
  || fail "B init-root 失败"
start_server "$TMP/data-b" "$PORT_B" b
wait_ready "http://127.0.0.1:$PORT_B" || fail "B 台未就绪"

echo "== 登录闭环演练（口令经 stdin，不回显）"
(cd "$FRONTEND_DIR" && "$DART" run tools/live_probe/auth_flow_probe.dart \
  "http://127.0.0.1:$PORT_A" "http://127.0.0.1:$PORT_B" < "$PWFILE")
PROBE_RC=$?

echo "== 口令残留检查（两份资料目录与服务日志内不得出现本次口令）"
if grep -R -q -- "$PW" "$TMP/data-a" "$TMP/data-b" "$TMP/server-a.log" "$TMP/server-b.log" 2>/dev/null; then
  fail "演练资料中发现口令残留"
fi
echo "口令残留检查：未发现。"

exit "$PROBE_RC"
