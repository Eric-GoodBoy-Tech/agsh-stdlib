#!/usr/bin/env bats
# i18n-kernel.bats — L1 tests: full language packs, the banner assembler and
# the kernel text-slot dispatchers.
#
# Two runners, both isolated (env -i, throwaway HOME/TMPDIR/nodes):
#   run_zsh     — the suite alone, no kernel.
#   run_kernel  — the real agent.zsh with an .agshrc that sources only
#                 i18n.zsh. The probe is sourced as a file *after* agent.zsh,
#                 so the slot aliases expand exactly as they do in an
#                 interactive shell.
# Byte-exactness is asserted with cmp against test/fixtures/legacy/*, the
# oracle captured before the rewrite.

setup() {
  STDLIB="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  KERNEL="$(cd "$STDLIB/../agent-shell" 2>/dev/null && pwd || true)"
  FIX="$STDLIB/test/fixtures/legacy"
  mkdir -p "$BATS_TEST_TMPDIR/home"
  printf 'source %s/i18n.zsh\n' "$STDLIB" > "$BATS_TEST_TMPDIR/home/.agshrc"
}

run_zsh() {
  local script="$BATS_TEST_TMPDIR/probe.zsh" outf="$BATS_TEST_TMPDIR/out" errf="$BATS_TEST_TMPDIR/err"
  cat > "$script"
  env -i HOME="$BATS_TEST_TMPDIR/home" PATH="$PATH" TMPDIR="$BATS_TEST_TMPDIR" \
    LANG="${PROBE_LANG:-en_US.UTF-8}" ${PROBE_EXTRA:-} \
    zsh -f "$script" >"$outf" 2>"$errf"
  RC=$?
  OUT="$(cat "$outf")"; ERR="$(cat "$errf")"; OUT_FILE="$outf"; ERR_FILE="$errf"
}

run_kernel() {
  local script="$BATS_TEST_TMPDIR/probe.zsh" outf="$BATS_TEST_TMPDIR/out" errf="$BATS_TEST_TMPDIR/err"
  cat > "$script"
  env -i HOME="$BATS_TEST_TMPDIR/home" PATH="$PATH" TMPDIR="$BATS_TEST_TMPDIR" \
    LANG="${PROBE_LANG:-en_US.UTF-8}" AGENT_ROOT="$KERNEL" \
    AGENT_NODES_PATH="$BATS_TEST_TMPDIR/nodes" AGENT_API_KEY=dummy AGENT_HEADLESS=1 \
    zsh -f -c "source \"$KERNEL/agent.zsh\" >/dev/null 2>&1; source \"$script\"" >"$outf" 2>"$errf"
  RC=$?
  OUT="$(cat "$outf")"; ERR="$(cat "$errf")"; OUT_FILE="$outf"; ERR_FILE="$errf"
}

# ─── packs ───────────────────────────────────────────────────────────────────

@test "packs are silent at source time" {
  run_zsh <<EOF
source "$STDLIB/i18n.zsh"
source "$STDLIB/i18n.zsh"
print -r -- done
EOF
  [ "$RC" -eq 0 ]
  [ "$OUT" = "done" ]
  [ -z "$ERR" ]
}

@test "banner base is byte-identical to the legacy fixture (en, zh)" {
  PROBE_LANG=en_US.UTF-8 run_zsh <<EOF
source "$STDLIB/i18n.zsh"
print -r -- "\$_AGENT_BANNER_TEXT"
EOF
  [ "$RC" -eq 0 ]
  run cmp "$FIX/banner-base.en.txt" "$OUT_FILE"
  [ "$status" -eq 0 ]

  PROBE_LANG=zh_CN.UTF-8 run_zsh <<EOF
source "$STDLIB/i18n.zsh"
print -r -- "\$_AGENT_BANNER_TEXT"
EOF
  [ "$RC" -eq 0 ]
  run cmp "$FIX/banner-base.zh.txt" "$OUT_FILE"
  [ "$status" -eq 0 ]
}

@test "a missing translation falls back to English (pack overlay)" {
  PROBE_LANG=zh_CN.UTF-8 run_zsh <<EOF
source "$STDLIB/i18n.zsh"
unset "_agsh_txt[zh.kernel.banner.retry]"
print -r -- "\$(_agsh_t kernel.banner.retry)"
EOF
  [ "$RC" -eq 0 ]
  [ "$OUT" = "  Ctrl+T     - Retry API" ]
}

@test "agent-lang list reads pack metadata" {
  run_zsh <<EOF
source "$STDLIB/i18n.zsh"
agent-lang list
EOF
  [ "$RC" -eq 0 ]
  [[ "$OUT" == *"en"*"English"* ]]
  [[ "$OUT" == *"zh"*"简体中文"* ]]
}

# ─── kernel surfaces ─────────────────────────────────────────────────────────

@test "kernel help page matches the legacy fixture per language" {
  # Byte-exactness is asserted on the base rows (--base): module rows are
  # registered on top of them and are covered by test/i18n-help.bats.
  [ -f "$KERNEL/agent.zsh" ] || skip "kernel not found"
  PROBE_LANG=en_US.UTF-8 run_kernel <<'EOF'
_agsh_help_render --base
EOF
  [ "$RC" -eq 0 ]
  run cmp "$FIX/help.en.txt" "$OUT_FILE"
  [ "$status" -eq 0 ]

  PROBE_LANG=zh_CN.UTF-8 run_kernel <<'EOF'
_agsh_help_render --base
EOF
  [ "$RC" -eq 0 ]
  run cmp "$FIX/help.zh.txt" "$OUT_FILE"
  [ "$status" -eq 0 ]
}

@test "credential surfaces match the legacy fixture per language" {
  [ -f "$KERNEL/agent.zsh" ] || skip "kernel not found"
  local exp="$BATS_TEST_TMPDIR/expected"

  cat "$FIX/cred-help.en.txt" "$FIX/cred-set.en.txt" "$FIX/cred-clear.en.txt" > "$exp"
  PROBE_LANG=en_US.UTF-8 run_kernel <<'EOF'
{ _agsh_credential_help; CREDENTIAL=testid _agsh_credential_status set; _agsh_credential_status cleared } 2>&1
EOF
  [ "$RC" -eq 0 ]
  run cmp "$exp" "$OUT_FILE"
  [ "$status" -eq 0 ]

  cat "$FIX/cred-help.zh.txt" "$FIX/cred-set.zh.txt" "$FIX/cred-clear.zh.txt" > "$exp"
  PROBE_LANG=zh_CN.UTF-8 run_kernel <<'EOF'
{ _agsh_credential_help; CREDENTIAL=testid _agsh_credential_status set; _agsh_credential_status cleared } 2>&1
EOF
  [ "$RC" -eq 0 ]
  run cmp "$exp" "$OUT_FILE"
  [ "$status" -eq 0 ]
}

@test "language switches at runtime in the same shell" {
  [ -f "$KERNEL/agent.zsh" ] || skip "kernel not found"
  PROBE_LANG=en_US.UTF-8 run_kernel <<'EOF'
agent help | head -1
agent-lang set zh
agent help | head -1
print -r -- "$_AGENT_BANNER_TEXT" | head -1
agent-lang set en
agent help | head -1
EOF
  [ "$RC" -eq 0 ]
  [ "$OUT" = $'agent-shell - terminal-native AI agent\nagent-shell - 终端原生 AI Agent\n  credential - 申领/释放凭证\nagent-shell - terminal-native AI agent' ]
}

@test "selfcheck passes for both packs against the kernel originals" {
  [ -f "$KERNEL/agent.zsh" ] || skip "kernel not found"
  run_kernel <<'EOF'
_agsh_i18n_selfcheck en && print en-ok
_agsh_i18n_selfcheck zh && print zh-ok
print "lang=$_agsh_lang"
EOF
  [ "$RC" -eq 0 ]
  [ "$OUT" = $'en-ok\nzh-ok\nlang=en' ]
  [ -z "$ERR" ]
}

@test "selfcheck detects a corrupted pack on disk" {
  local d="$BATS_TEST_TMPDIR/stdlib" script="$BATS_TEST_TMPDIR/corrupt.zsh"
  cp -R "$STDLIB" "$d"
  printf "\n_agsh_txt[zh.kernel.credential_cleared]='[credential] WRONG'\n" >> "$d/lang/zh.zsh"
  cat > "$script" <<EOF
source "$d/i18n.zsh"
_agsh_i18n_selfcheck zh
EOF
  run env -i HOME="$BATS_TEST_TMPDIR/home" PATH="$PATH" TMPDIR="$BATS_TEST_TMPDIR" \
    LANG=zh_CN.UTF-8 zsh -f "$script"
  [ "$status" -eq 1 ]
  [[ "$output" == *"selfcheck mismatch"* ]]
  [[ "$output" == *"cred-clear.zh"* ]]
}

@test "unload restores the kernel banner and the kernel aliases" {
  [ -f "$KERNEL/agent.zsh" ] || skip "kernel not found"
  run_kernel <<'EOF'
default="$_AGENT_BANNER_TEXT"
agent-lang set zh
_agsh_unload
[[ "$_AGENT_BANNER_TEXT" == "$default" ]] && print banner-restored
print "alias=$(alias _agsh_help)"
print "lang-fn=$+functions[agent-lang]"
EOF
  [ "$RC" -eq 0 ]
  [ "$OUT" = $'banner-restored\nalias=_agsh_help=_agent_help_en\nlang-fn=0' ]
}

@test "not installed: the kernel originals stay in place" {
  [ -f "$KERNEL/agent.zsh" ] || skip "kernel not found"
  local bare="$BATS_TEST_TMPDIR/bare" script="$BATS_TEST_TMPDIR/bare.zsh"
  mkdir -p "$bare"
  cat > "$script" <<EOF
source "$KERNEL/agent.zsh" >/dev/null 2>&1
print "alias=\$(alias _agsh_help)"
print -r -- "\$_AGENT_BANNER_TEXT" | head -1
print "t=\$+functions[_agsh_t]"
EOF
  run env -i HOME="$bare" PATH="$PATH" TMPDIR="$BATS_TEST_TMPDIR" LANG=en_US.UTF-8 \
    AGENT_ROOT="$KERNEL" AGENT_NODES_PATH="$BATS_TEST_TMPDIR/bare-nodes" \
    AGENT_API_KEY=dummy AGENT_HEADLESS=1 zsh -f "$script"
  [ "$status" -eq 0 ]
  [ "$output" = $'alias=_agsh_help=_agent_help_en\n  credential - Claim/release a credential\nt=0' ]
}

# ─── banner assembler ────────────────────────────────────────────────────────

@test "banner assembler inserts at a position, is idempotent, and removes" {
  run_zsh <<EOF
source "$STDLIB/i18n.zsh"
_agsh_def test.line 'TEST-LINE' >/dev/null
_agsh_banner_add test test.line 1
print -r -- "\$_AGENT_BANNER_TEXT" | head -1
_agsh_banner_add test test.line 1
print -r -- "\$_AGENT_BANNER_TEXT" | grep -c TEST-LINE
_agsh_banner_remove test
print -r -- "\$_AGENT_BANNER_TEXT" | head -1
EOF
  [ "$RC" -eq 0 ]
  [ "$OUT" = $'TEST-LINE\n1\n  credential - Claim/release a credential' ]
}

@test "compose refuses to blank the banner when a base key is missing" {
  run_zsh <<EOF
source "$STDLIB/i18n.zsh"
before="\$_AGENT_BANNER_TEXT"
unset "_agsh_txt[en.kernel.banner.retry]"
_agsh_banner_compose
print "rc=\$?"
[[ "\$_AGENT_BANNER_TEXT" == "\$before" ]] && print unchanged
EOF
  [ "$RC" -eq 0 ]
  [ "$OUT" = $'rc=1\nunchanged' ]
}

# ─── lint ────────────────────────────────────────────────────────────────────

@test "lint: the stdlib tree is clean" {
  run zsh "$STDLIB/tools/i18n-lint.zsh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok:"* ]]
}
