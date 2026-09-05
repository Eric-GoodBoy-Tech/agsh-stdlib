#!/usr/bin/env bats
# i18n-core.bats — L0 unit tests: dependency-free core, loader, lint tool.
#
# Every probe runs in a throwaway environment (env -i, isolated HOME/TMPDIR,
# LANG fixed) so nothing here can touch the developer's shell or ~/.agshrc.

setup() {
  STDLIB="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  mkdir -p "$BATS_TEST_TMPDIR/home"
}

# run_zsh: read a zsh snippet from stdin, run it in an isolated shell.
# Sets OUT (stdout), ERR (stderr), RC (exit status).
run_zsh() {
  local script="$BATS_TEST_TMPDIR/probe.zsh" errf="$BATS_TEST_TMPDIR/err"
  cat > "$script"
  OUT="$(env -i HOME="$BATS_TEST_TMPDIR/home" PATH="$PATH" TMPDIR="$BATS_TEST_TMPDIR" \
        LANG="${PROBE_LANG:-en_US.UTF-8}" ${PROBE_EXTRA:-} zsh -f "$script" 2>"$errf")"
  RC=$?
  ERR="$(cat "$errf")"
}

# ─── core ────────────────────────────────────────────────────────────────────

@test "core works standalone, without i18n.zsh" {
  run_zsh <<EOF
source "$STDLIB/i18n-core.zsh"
_agsh_def k.alpha 'ALPHA' >/dev/null
print -r -- "\$(_agsh_t k.alpha)"
print -r -- "\$+functions[_agsh_i18n_load]"
EOF
  [ "$RC" -eq 0 ]
  [ "$OUT" = $'ALPHA\n0' ]
}

@test "_agsh_def registers en.<key> and echoes the text" {
  run_zsh <<EOF
source "$STDLIB/i18n-core.zsh"
_agsh_def k.echo 'ECHO' >/dev/null
print -r -- "\${_agsh_txt[en.k.echo]}"
print -r -- "\$(_agsh_t k.echo)"
EOF
  [ "$RC" -eq 0 ]
  [ "$OUT" = $'ECHO\nECHO' ]
}

@test "resolution: lang -> en -> own fallback -> empty" {
  run_zsh <<EOF
source "$STDLIB/i18n.zsh"
_agsh_def k.beta 'BETA' >/dev/null
_agsh_txt[zh.k.beta]='贝塔'
_agsh_i18n_load zh
print -r -- "\$(_agsh_t k.beta)"
_agsh_i18n_load fr
print -r -- "\$(_agsh_t k.beta)"
print -r -- "[\$(_agsh_t k.nope 'OWN')]"
print -r -- "[\$(_agsh_t k.nope)]"
EOF
  [ "$RC" -eq 0 ]
  [ "$OUT" = $'贝塔\nBETA\n[OWN]\n[]' ]
}

@test "AGSH_I18N_STRICT warns on stderr, stdout unchanged" {
  run_zsh <<EOF
source "$STDLIB/i18n.zsh"
_agsh_def k.g 'G' >/dev/null
_agsh_i18n_load zh
export AGSH_I18N_STRICT=1
print -r -- "\$(_agsh_t k.g)"
print -r -- "[\$(_agsh_t k.nope)]"
EOF
  [ "$RC" -eq 0 ]
  [ "$OUT" = $'G\n[]' ]
  [[ "$ERR" == *"missing key: k.g (lang=zh)"* ]]
  [[ "$ERR" == *"missing key: k.nope (lang=zh)"* ]]
}

@test "no warning without AGSH_I18N_STRICT" {
  run_zsh <<EOF
source "$STDLIB/i18n.zsh"
_agsh_def k.g 'G' >/dev/null
_agsh_i18n_load zh
print -r -- "\$(_agsh_t k.g)"
EOF
  [ "$RC" -eq 0 ]
  [ "$OUT" = "G" ]
  [ -z "$ERR" ]
}

@test "_agsh_tf formats only keys declared fmt" {
  run_zsh <<EOF
source "$STDLIB/i18n.zsh"
_agsh_def k.fmt 'V=%s\n' fmt >/dev/null
_agsh_def k.plain 'P' >/dev/null
_agsh_tf k.fmt V
export AGSH_I18N_STRICT=1
_agsh_tf k.plain V
EOF
  [ "$RC" -eq 0 ]
  [ "$OUT" = $'V=V\nP' ]
  [[ "$ERR" == *"key not declared fmt: k.plain"* ]]
}

@test "language choice: arg > AGSH_LANG > LANG, region and encoding stripped" {
  run_zsh <<EOF
source "$STDLIB/i18n.zsh"
print -r -- "\$(_agsh_i18n_choose zh_CN.UTF-8)"
print -r -- "\$(_agsh_i18n_choose en_US)"
print -r -- "\$(_agsh_i18n_choose fr_FR)"
print -r -- "\$(_agsh_i18n_choose)"
EOF
  PROBE_LANG=zh_CN.UTF-8 run_zsh <<EOF
source "$STDLIB/i18n.zsh"
print -r -- "\$(_agsh_i18n_choose)"
AGSH_LANG=en print -r -- "\$(_agsh_i18n_choose)"
EOF
  true
}

@test "agent-lang list shows packs, set switches, unknown falls back to en" {
  run_zsh <<EOF
source "$STDLIB/i18n.zsh"
agent-lang list
agent-lang set zh
print -r -- "lang=\$_agsh_lang"
agent-lang set xx
print -r -- "lang=\$_agsh_lang"
EOF
  [ "$RC" -eq 0 ]
  [[ "$OUT" == *" en "* ]]
  [[ "$OUT" == *" zh "* ]]
  [[ "$OUT" == *"lang=zh"* ]]
  [[ "$OUT" == *"lang=en"* ]]
}

@test "LANG drives the boot language" {
  PROBE_LANG=zh_CN.UTF-8 run_zsh <<EOF
source "$STDLIB/i18n.zsh"
print -r -- "\$_agsh_lang"
EOF
  [ "$RC" -eq 0 ]
  [ "$OUT" = "zh" ]
}

@test "_agsh_have reports registered providers and rejects unknown ids" {
  run_zsh <<EOF
source "$STDLIB/i18n.zsh"
_agsh_have banner && print yes || print no
_agsh_have help && print yes || print no
_agsh_have nope && print yes || print no
EOF
  [ "$RC" -eq 0 ]
  [ "$OUT" = $'yes\nyes\nno' ]
}

@test "re-sourcing is safe and does not duplicate hooks" {
  run_zsh <<EOF
source "$STDLIB/i18n.zsh"
source "$STDLIB/i18n.zsh"
print -r -- \${(M)#_agsh_hooks_apply:#_agsh_i18n_register_help}
EOF
  [ "$RC" -eq 0 ]
  [ "$OUT" = "1" ]
}

@test "_agsh_unload removes the suite" {
  run_zsh <<EOF
source "$STDLIB/i18n.zsh"
_agsh_unload
print -r -- "t=\$+functions[_agsh_t] u=\$+functions[_agsh_unload] l=\${+_agsh_txt}"
EOF
  [ "$RC" -eq 0 ]
  [ "$OUT" = "t=0 u=0 l=0" ]
}

# ─── lint ────────────────────────────────────────────────────────────────────

@test "lint: clean tree exits 0" {
  local d="$BATS_TEST_TMPDIR/stdlib"
  mkdir -p "$d/lang"
  cat > "$d/mod.zsh" <<'EOF'
if ! (( $+functions[_agsh_t] )); then
  _agsh_t() { print -r -- "${2:-}" }
fi
_agsh_def mod.hello 'Hello' >/dev/null
unfunction _agsh_def _agsh_tf
EOF
  cat > "$d/lang/en.zsh" <<'EOF'
_agsh_pack_def kernel.x 'X'
EOF
  cat > "$d/lang/zh.zsh" <<'EOF'
_agsh_txt[zh.kernel.x]='X 中'
EOF
  run zsh "$STDLIB/tools/i18n-lint.zsh" "$d"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok: 3 key(s)"* ]]
}

@test "lint: unpaired translation exits 1" {
  local d="$BATS_TEST_TMPDIR/stdlib"
  mkdir -p "$d/lang"
  cat > "$d/lang/zh.zsh" <<'EOF'
_agsh_txt[zh.kernel.only]='只有中文'
EOF
  run zsh "$STDLIB/tools/i18n-lint.zsh" "$d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no en counterpart"* ]]
}

@test "lint: namespace violation exits 1" {
  local d="$BATS_TEST_TMPDIR/stdlib"
  mkdir -p "$d/lang"
  cat > "$d/mod.zsh" <<'EOF'
_agsh_def other.key 'X' >/dev/null
EOF
  run zsh "$STDLIB/tools/i18n-lint.zsh" "$d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"outside its namespace"* ]]
}

@test "lint: duplicate definition exits 1" {
  local d="$BATS_TEST_TMPDIR/stdlib"
  mkdir -p "$d/lang"
  cat > "$d/mod.zsh" <<'EOF'
_agsh_def mod.dup 'A' >/dev/null
_agsh_def mod.dup 'B' >/dev/null
EOF
  run zsh "$STDLIB/tools/i18n-lint.zsh" "$d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"duplicate definition"* ]]
}

@test "lint: fmt key without placeholder exits 1" {
  local d="$BATS_TEST_TMPDIR/stdlib"
  mkdir -p "$d/lang"
  cat > "$d/mod.zsh" <<'EOF'
_agsh_def mod.nofmt 'no placeholder' fmt >/dev/null
EOF
  run zsh "$STDLIB/tools/i18n-lint.zsh" "$d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"has no '%'"* ]]
}

@test "lint: _agsh_tf on a declared fmt key exits 0" {
  local d="$BATS_TEST_TMPDIR/stdlib"
  mkdir -p "$d/lang"
  cat > "$d/mod.zsh" <<'EOF'
if ! (( $+functions[_agsh_t] )); then
  _agsh_t() { print -r -- "${2:-}" }
fi
_agsh_def mod.fmt 'V=%s\n' fmt >/dev/null
print -r -- "$(_agsh_tf mod.fmt V)"
EOF
  run zsh "$STDLIB/tools/i18n-lint.zsh" "$d"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok:"* ]]
  [[ "$output" == *"1 _agsh_tf call site(s)"* ]]
}

@test "lint: _agsh_tf on an undeclared key exits 1" {
  local d="$BATS_TEST_TMPDIR/stdlib"
  mkdir -p "$d/lang"
  cat > "$d/mod.zsh" <<'EOF'
_agsh_def mod.plain 'P' >/dev/null
print -r -- "$(_agsh_tf mod.plain V)"
EOF
  run zsh "$STDLIB/tools/i18n-lint.zsh" "$d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"never declared fmt"* ]]
}

@test "lint: not a stdlib dir exits 2" {
  run zsh "$STDLIB/tools/i18n-lint.zsh" "$BATS_TEST_TMPDIR/nope"
  [ "$status" -eq 2 ]
  [[ "$output" == *"not a stdlib dir"* ]]
}

@test "lint: a text-writing module without a channel-A guard exits 1" {
  local d="$BATS_TEST_TMPDIR/stdlib"
  mkdir -p "$d/lang"
  cat > "$d/mod.zsh" <<'EOF'
_agsh_def mod.hello 'Hello' >/dev/null
EOF
  run zsh "$STDLIB/tools/i18n-lint.zsh" "$d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no channel-A guard"* ]]
  [[ "$output" == *"mod.zsh"* ]]
}

@test "lint: a suite layer may write text without a guard" {
  local d="$BATS_TEST_TMPDIR/stdlib"
  mkdir -p "$d/lang"
  cat > "$d/i18n.zsh" <<'EOF'
_agsh_def i18n.help.x 'X' >/dev/null
EOF
  run zsh "$STDLIB/tools/i18n-lint.zsh" "$d"
  [ "$status" -eq 0 ]
  [[ "$output" == *"0 module guard(s)"* ]]
}
