#!/usr/bin/env bats
# i18n-help.bats — L2 tests: the structured help registry and its renderer.
#
# Two runners, both isolated (env -i, throwaway HOME/TMPDIR/nodes):
#   run_zsh     — the suite alone, no kernel.
#   run_kernel  — the real agent.zsh with an .agshrc that sources only
#                 i18n.zsh.
# Byte-exactness is asserted against test/fixtures/legacy/help.*, the oracle
# captured before the rewrite. Module rows (prompt, agent-lang) are filtered
# out for that comparison — `_agsh_help_render --base` is the same filter
# implemented by the renderer itself.

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

# Rows contributed by modules, i.e. not part of the kernel page.
strip_module_rows() { grep -vE '^  (prompt |agent-lang )' "$1"; }

# ─── renderer ────────────────────────────────────────────────────────────────

@test "base page is byte-identical to the legacy fixture (en, zh)" {
  PROBE_LANG=en_US.UTF-8 run_zsh <<EOF
source "$STDLIB/i18n.zsh"
_agsh_help_render --base
EOF
  [ "$RC" -eq 0 ]
  run cmp "$FIX/help.en.txt" "$OUT_FILE"
  [ "$status" -eq 0 ]

  PROBE_LANG=zh_CN.UTF-8 run_zsh <<EOF
source "$STDLIB/i18n.zsh"
_agsh_help_render --base
EOF
  [ "$RC" -eq 0 ]
  run cmp "$FIX/help.zh.txt" "$OUT_FILE"
  [ "$status" -eq 0 ]
}

@test "agent help keeps the legacy layout and gains the module rows" {
  [ -f "$KERNEL/agent.zsh" ] || skip "kernel not found"
  local lang
  for lang in en zh; do
    if [ "$lang" = en ]; then PROBE_LANG=en_US.UTF-8; else PROBE_LANG=zh_CN.UTF-8; fi
    run_kernel <<'EOF'
agent help
EOF
    [ "$RC" -eq 0 ]
    strip_module_rows "$OUT_FILE" > "$BATS_TEST_TMPDIR/stripped.$lang"
    run cmp "$FIX/help.$lang.txt" "$BATS_TEST_TMPDIR/stripped.$lang"
    [ "$status" -eq 0 ]
    run grep -q '^  agent-lang list|set <id>' "$OUT_FILE"
    [ "$status" -eq 0 ]
  done
}

@test "a module row lands at the end of its section, aligned" {
  run_zsh <<EOF
source "$STDLIB/i18n.zsh"
_agsh_def prompt.help.prompt 'Create a prompt node' >/dev/null
_agsh_help_add Commands 'prompt <id> <content> [parent]' prompt.help.prompt
page="\$(_agsh_help_render)"
sec="\$(print -r -- "\$page" | sed -n '/^Commands:/,/^\$/p')"
print "last=\${sec##*\$'\n'}"
row="\$(grep '^  agent-lang ' <<<\"\$page\")"
print "col=\$(( \${#\${row%%List*}} + 1 ))"
EOF
  [ "$RC" -eq 0 ]
  [ "$OUT" = $'last=  prompt <id> <content> [parent]  Create a prompt node\ncol=35' ]
}

@test "add is idempotent, remove drops the row" {
  run_zsh <<EOF
source "$STDLIB/i18n.zsh"
_agsh_def t.help 'text' >/dev/null
_agsh_help_add Commands 't cmd' t.help
_agsh_help_add Commands 't cmd' t.help
print "count=\$(grep -c '^  t cmd' <<<"\$(_agsh_help_render)")"
_agsh_help_remove 't cmd'
print "after=\$(grep -c '^  t cmd' <<<"\$(_agsh_help_render)")"
EOF
  [ "$RC" -eq 0 ]
  [ "$OUT" = $'count=1\nafter=0' ]
}

@test "--base hides module rows, the default render shows them" {
  run_zsh <<EOF
source "$STDLIB/i18n.zsh"
print "base=\$(grep -c '^  agent-lang' <<<"\$(_agsh_help_render --base)")"
print "full=\$(grep -c '^  agent-lang' <<<"\$(_agsh_help_render)")"
EOF
  [ "$RC" -eq 0 ]
  [ "$OUT" = $'base=0\nfull=1' ]
}

@test "the page follows the language at runtime, in the same shell" {
  [ -f "$KERNEL/agent.zsh" ] || skip "kernel not found"
  PROBE_LANG=en_US.UTF-8 run_kernel <<'EOF'
agent help | head -1
agent-lang set zh
agent help | head -1
agent help | grep '^  agent-lang' 
agent-lang set en
agent help | head -1
EOF
  [ "$RC" -eq 0 ]
  [ "$OUT" = $'agent-shell - terminal-native AI agent\nagent-shell - 终端原生 AI Agent\n  agent-lang list|set <id>        列出或切换界面语言\nagent-shell - terminal-native AI agent' ]
}

# ─── readme table ────────────────────────────────────────────────────────────

@test "readme table has one row per registry entry, pipes escaped" {
  run_zsh <<EOF
source "$STDLIB/i18n.zsh"
_agsh_help_readme
EOF
  [ "$RC" -eq 0 ]
  [[ "${OUT%%$'\n'*}" == '| Section | Command | Description |' ]]
  [[ "$OUT" == *'| Commands | `credential claim <id>` |'* ]]
  [[ "$OUT" == *'| Commands | `agent-lang list\|set <id>` |'* ]]
  [ "$(grep -c '^| ' <<<"$OUT")" = "20" ]   # header + separator + 17 base rows + 1 module row
}

@test "tools/help-readme.zsh renders the same table" {
  run zsh "$STDLIB/tools/help-readme.zsh" en
  [ "$status" -eq 0 ]
  local tool_out="$output"
  PROBE_LANG=en_US.UTF-8 run_zsh <<EOF
source "$STDLIB/i18n.zsh"
_agsh_help_readme
EOF
  [ "$RC" -eq 0 ]
  [ "$OUT" = "$tool_out" ]
  [[ "$tool_out" == *'`agent-lang list\|set <id>`'* ]]
}

# ─── lifecycle ───────────────────────────────────────────────────────────────

@test "unload removes the help API and the registry" {
  run_zsh <<EOF
source "$STDLIB/i18n.zsh"
print "before=\$+functions[_agsh_help_render]/\${+_agsh_help_items}"
_agsh_unload
print "after=\$+functions[_agsh_help_render]/\${+_agsh_help_items}"
EOF
  [ "$RC" -eq 0 ]
  [ "$OUT" = $'before=1/1\nafter=0/0' ]
}

@test "re-sourcing keeps one row per command" {
  run_zsh <<EOF
source "$STDLIB/i18n.zsh"
_agsh_def t.help 'text' >/dev/null
_agsh_help_add Commands 't cmd' t.help
source "$STDLIB/i18n.zsh"
print "count=\$(grep -c '^  t cmd' <<<"\$(_agsh_help_render)")"
print "base=\$(grep -c '^  agent-lang' <<<"\$(_agsh_help_render --base)")"
EOF
  [ "$RC" -eq 0 ]
  [ "$OUT" = $'count=1\nbase=0' ]
}

@test "help keys are paired: lint stays clean with the item keys" {
  run zsh "$STDLIB/tools/i18n-lint.zsh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok:"* ]]
}
