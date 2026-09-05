#!/usr/bin/env bats
# i18n-plugins.bats — L3 tests: the stdlib plugins on top of the suite.
#
# prompt.zsh is the first real consumer of the suite's services, so this file
# covers the whole chain end to end:
#   - the banner line is composed through the assembler (position 1) and
#     survives a runtime language switch, instead of being prepended to a
#     string the module does not own;
#   - the help row is registered through the structured registry;
#   - the text goes through _agsh_t / _agsh_tf (no English fallback argument
#     at the call site, no translation used as a format string);
#   - the module still works when the services are absent (degrade);
#   - _agsh_unload removes the function and both advertised surfaces.
#
# Five runners, all isolated (env -i, throwaway HOME/TMPDIR/nodes):
#   run_zsh         — the suite + prompt.zsh, no kernel.
#   run_kernel      — the real agent.zsh with an .agshrc that sources i18n.zsh
#                     then prompt.zsh (the production order).
#   run_bare        — the real agent.zsh + prompt.zsh only (no i18n.zsh): the
#                     banner/help services are absent, the core still works.
#   run_kernel_lite — the real agent.zsh with a *trimmed* suite copy that has
#                     no optional provider layers (help.zsh / kernel-slots.zsh):
#                     the providers are genuinely absent, prompt and i18n must
#                     still work and must not raise.
#   run_nocore      — a suite copy stripped of i18n-core.zsh *and* registry.zsh:
#                     nothing on disk can supply the core, so the module's own
#                     channel-A guard is the only thing that can keep it usable.

setup() {
  STDLIB="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  KERNEL="$(cd "$STDLIB/../agent-shell" 2>/dev/null && pwd || true)"
  FIX="$STDLIB/test/fixtures/legacy"
  mkdir -p "$BATS_TEST_TMPDIR/home" "$BATS_TEST_TMPDIR/bare" "$BATS_TEST_TMPDIR/pu"
  OUTDIR="$BATS_TEST_TMPDIR/pu"      # raw-capture dir for the post-unload probes
  printf 'source %s/i18n.zsh\nsource %s/prompt.zsh\n' "$STDLIB" "$STDLIB" \
    > "$BATS_TEST_TMPDIR/home/.agshrc"

  # A trimmed copy of the suite that keeps every file except the optional
  # provider layers (help.zsh / kernel-slots.zsh). Run against it, the entry
  # point loads no banner and no help provider, so _agsh_have banner|help is
  # false for a real reason -- this is the non-tautological "providers absent"
  # environment the old degraded probe could not reach.
  LITE="$BATS_TEST_TMPDIR/lite"
  mkdir -p "$LITE/lang" "$BATS_TEST_TMPDIR/lite-home"
  cp "$STDLIB/i18n.zsh" "$STDLIB/i18n-core.zsh" "$STDLIB/registry.zsh" "$LITE/"
  cp "$STDLIB/lang/en.zsh" "$STDLIB/lang/zh.zsh" "$LITE/lang/"
  printf 'source %s/i18n.zsh\nsource %s/prompt.zsh\n' "$LITE" "$STDLIB" \
    > "$BATS_TEST_TMPDIR/lite-home/.agshrc"
}

_run() {   # _run <out> <err> -- <env...> <command...>
  local outf="$BATS_TEST_TMPDIR/out" errf="$BATS_TEST_TMPDIR/err"
  shift 2
  "$@" >"$outf" 2>"$errf"
  RC=$?
  OUT="$(cat "$outf")"; ERR="$(cat "$errf")"; OUT_FILE="$outf"; ERR_FILE="$errf"
}

run_zsh() {
  local script="$BATS_TEST_TMPDIR/probe.zsh"
  cat > "$script"
  _run x x env -i HOME="$BATS_TEST_TMPDIR/home" PATH="$PATH" \
    TMPDIR="$BATS_TEST_TMPDIR" STDLIB="$STDLIB" FIX="$FIX" \
    AGENT_NODES_PATH="$BATS_TEST_TMPDIR/nodes" \
    LANG="${PROBE_LANG:-en_US.UTF-8}" ${PROBE_EXTRA:-} zsh -f "$script"
}

run_kernel() {
  local script="$BATS_TEST_TMPDIR/probe.zsh"
  cat > "$script"
  _run x x env -i HOME="$BATS_TEST_TMPDIR/home" PATH="$PATH" \
    TMPDIR="$BATS_TEST_TMPDIR" STDLIB="$STDLIB" FIX="$FIX" \
    LANG="${PROBE_LANG:-en_US.UTF-8}" AGENT_ROOT="$KERNEL" \
    AGENT_NODES_PATH="$BATS_TEST_TMPDIR/nodes" AGENT_API_KEY=dummy AGENT_HEADLESS=1 \
    OUTDIR="$BATS_TEST_TMPDIR/pu" \
    zsh -f -c "source \"$KERNEL/agent.zsh\" >/dev/null 2>&1; source \"$script\""
}

run_bare() {
  local script="$BATS_TEST_TMPDIR/probe.zsh"
  cat > "$script"
  _run x x env -i HOME="$BATS_TEST_TMPDIR/bare" PATH="$PATH" \
    TMPDIR="$BATS_TEST_TMPDIR" STDLIB="$STDLIB" FIX="$FIX" \
    LANG="${PROBE_LANG:-en_US.UTF-8}" AGENT_ROOT="$KERNEL" \
    AGENT_NODES_PATH="$BATS_TEST_TMPDIR/bare-nodes" AGENT_API_KEY=dummy AGENT_HEADLESS=1 \
    zsh -f -c "source \"$KERNEL/agent.zsh\" >/dev/null 2>&1; source \"$STDLIB/prompt.zsh\"; source \"$script\""
}

run_kernel_lite() {
  local script="$BATS_TEST_TMPDIR/probe.zsh"
  cat > "$script"
  _run x x env -i HOME="$BATS_TEST_TMPDIR/lite-home" PATH="$PATH" \
    TMPDIR="$BATS_TEST_TMPDIR" STDLIB="$STDLIB" LITE="$LITE" FIX="$FIX" \
    LANG="${PROBE_LANG:-en_US.UTF-8}" AGENT_ROOT="$KERNEL" \
    AGENT_NODES_PATH="$BATS_TEST_TMPDIR/lite-nodes" AGENT_API_KEY=dummy AGENT_HEADLESS=1 \
    zsh -f -c "source \"$KERNEL/agent.zsh\" >/dev/null 2>&1; source \"$script\""
}

# make_nocore <dir> [broken] — a trimmed suite copy with i18n-core.zsh and
# registry.zsh removed, so sourcing its prompt.zsh exercises the module's own
# channel-A guard. With the word "broken" it also strips the guard block (and
# the shared container) from prompt.zsh: the negative control.
make_nocore() {
  local dir="$1" broken="${2:-}"
  mkdir -p "$dir/lib/lang"
  cp "$STDLIB"/*.zsh "$dir/lib/"
  cp "$STDLIB"/lang/*.zsh "$dir/lib/lang/"
  rm -f "$dir/lib/i18n-core.zsh" "$dir/lib/registry.zsh"
  [ "$broken" = broken ] || return 0
  awk '
    index($0, "typeset -gA _agsh_txt") == 1 { next }
    index($0, "typeset -g  _agsh_lang") == 1 { next }
    index($0, "+functions[_agsh_t]") { skip = 1; next }
    skip && /^fi$/ { skip = 0; next }
    !skip { print }
  ' "$STDLIB/prompt.zsh" > "$dir/lib/prompt.zsh"
}

run_nocore() {
  local script="$BATS_TEST_TMPDIR/probe.zsh"
  cat > "$script"
  _run x x env -i HOME="$BATS_TEST_TMPDIR/nocore-home" PATH="$PATH" \
    TMPDIR="$BATS_TEST_TMPDIR" STDLIB="$STDLIB" NOCORE="$NOCORE" FIX="$FIX" \
    AGENT_NODES_PATH="$BATS_TEST_TMPDIR/nocore-nodes" \
    LANG="${PROBE_LANG:-en_US.UTF-8}" \
    zsh -f -c "source \"$NOCORE/lib/prompt.zsh\"; source \"$script\""
}

# ─── banner ──────────────────────────────────────────────────────────────────

@test "the prompt line is composed at position 1, byte-exact against the oracle" {
  run_zsh <<'EOF'
source "$STDLIB/i18n.zsh"
source "$STDLIB/prompt.zsh"
exp="  prompt     - Create a prompt node"$'\n'"$(_agsh_banner_base_text)"$'\n'
[[ "$_AGENT_BANNER_TEXT" == "$exp" ]] && print match
print "lines=$(print -r -- "$_AGENT_BANNER_TEXT" | grep -c .)"
EOF
  [ "$RC" -eq 0 ]
  [ "$OUT" = $'match\nlines=6' ]

  # composed banner == prompt line + the pre-migration base banner
  run_zsh <<'EOF'
source "$STDLIB/i18n.zsh"
source "$STDLIB/prompt.zsh"
print -r -- "$_AGENT_BANNER_TEXT"
EOF
  [ "$RC" -eq 0 ]
  { printf '  prompt     - Create a prompt node\n'; cat "$FIX/banner-base.en.txt"; } \
    > "$BATS_TEST_TMPDIR/exp"
  run cmp "$BATS_TEST_TMPDIR/exp" "$OUT_FILE"
  [ "$status" -eq 0 ]
}

@test "runtime language switch re-renders the prompt line in place" {
  [ -f "$KERNEL/agent.zsh" ] || skip "kernel not found"
  PROBE_LANG=en_US.UTF-8 run_kernel <<'EOF'
print "first=$(print -r -- "$_AGENT_BANNER_TEXT" | head -1)"
agent-lang set zh
print "zh=$(print -r -- "$_AGENT_BANNER_TEXT" | head -1)"
print "n=$(print -r -- "$_AGENT_BANNER_TEXT" | grep -c .)"
agent-lang set en
print "en=$(print -r -- "$_AGENT_BANNER_TEXT" | head -1)"
EOF
  [ "$RC" -eq 0 ]
  [ "$OUT" = $'first=  prompt     - Create a prompt node\nzh=  prompt     - 创建提示词节点\nn=6\nen=  prompt     - Create a prompt node' ]
}

@test "the prompt line survives a suite reload after the module" {
  run_zsh <<'EOF'
source "$STDLIB/prompt.zsh"      # module first: services absent, legacy path
print "banner0=$(print -r -- "$_AGENT_BANNER_TEXT" | grep -c '^  prompt ')"
source "$STDLIB/i18n.zsh"        # suite later: apply hooks must re-advertise
print "banner1=$(print -r -- "$_AGENT_BANNER_TEXT" | grep -c '^  prompt ')"
print "row1=$(print -r -- "$(_agsh_help_render)" | grep -c '^  prompt ')"
source "$STDLIB/i18n.zsh"
source "$STDLIB/prompt.zsh"
print "banner2=$(print -r -- "$_AGENT_BANNER_TEXT" | grep -c '^  prompt ')"
print "row2=$(print -r -- "$(_agsh_help_render)" | grep -c '^  prompt ')"
EOF
  [ "$RC" -eq 0 ]
  [ "$OUT" = $'banner0=1\nbanner1=1\nrow1=1\nbanner2=1\nrow2=1' ]
}

# ─── help ────────────────────────────────────────────────────────────────────

@test "the help row is registered, aligned, and hidden by --base" {
  run_zsh <<'EOF'
source "$STDLIB/i18n.zsh"
source "$STDLIB/prompt.zsh"
print "row=$(print -r -- "$(_agsh_help_render)" | grep '^  prompt ')"
print "base=$(print -r -- "$(_agsh_help_render --base)" | grep -c '^  prompt ')"
agent-lang set zh
print "zh=$(print -r -- "$(_agsh_help_render)" | grep '^  prompt ')"
EOF
  [ "$RC" -eq 0 ]
  [ "$OUT" = $'row=  prompt <id> <content> [parent]  Create a prompt node\nbase=0\nzh=  prompt <id> <content> [parent]  创建提示词节点' ]
}

# ─── text and behaviour ──────────────────────────────────────────────────────

@test "usage and created messages follow the language, no format-string hazard" {
  PROBE_LANG=zh_CN.UTF-8 run_zsh <<'EOF'
source "$STDLIB/i18n.zsh"
source "$STDLIB/prompt.zsh"
prompt; print "rc=$?"
prompt t1 "hello"; print "rc2=$?"
print "ctx=$(<"$AGENT_NODES_PATH/t1/context") parent=$(<"$AGENT_NODES_PATH/t1/parent")"
prompt t2 "x" custom; print "p2=$(<"$AGENT_NODES_PATH/t2/parent")"
EOF
  [ "$RC" -eq 0 ]
  [ "$OUT" = $'rc=1\nrc2=0\nctx=hello parent=root\np2=custom' ]
  [[ "$ERR" == *'用法: prompt <id> <content> [parent]'* ]]
  [[ "$ERR" == *"在 $BATS_TEST_TMPDIR/nodes/<id>/ 下创建一个提示词节点"* ]]
  [[ "$ERR" == *"[prompt] 已创建节点 't1' -> $BATS_TEST_TMPDIR/nodes/t1/"* ]]

  PROBE_LANG=en_US.UTF-8 run_zsh <<'EOF'
source "$STDLIB/i18n.zsh"
source "$STDLIB/prompt.zsh"
prompt; print "rc=$?"
EOF
  [ "$RC" -eq 0 ]
  [ "$OUT" = "rc=1" ]
  [[ "$ERR" == *'usage: prompt <id> <content> [parent]'* ]]
  [[ "$ERR" == *"Creates a prompt node under $BATS_TEST_TMPDIR/nodes/<id>/"* ]]
}

@test "degraded: prompt works without i18n.zsh (no banner/help services)" {
  [ -f "$KERNEL/agent.zsh" ] || skip "kernel not found"
  run_bare <<'EOF'
_agsh_have banner && print "banner=1" || print "banner=0"
_agsh_have help && print "help=1" || print "help=0"
print "first=$(print -r -- "$_AGENT_BANNER_TEXT" | head -1)"
prompt t1 "x"
print "ctx=$(<"$AGENT_NODES_PATH/t1/context") parent=$(<"$AGENT_NODES_PATH/t1/parent")"
prompt; print "rc=$?"
EOF
  [ "$RC" -eq 0 ]
  [ "$OUT" = $'banner=0\nhelp=0\nfirst=  prompt     - Create a prompt node\nctx=x parent=root\nrc=1' ]
  [[ "$ERR" == *"usage: prompt <id> <content> [parent]"* ]]
}

@test "providers genuinely absent: the suite loads, prompt works, nothing raises" {
  # Audit A4: the old degraded probe sourced prompt.zsh, which brings the core
  # (and the registry) along, so its verdict was partly tautological. Here the
  # provider layers are the ones missing: help.zsh and kernel-slots.zsh are not
  # in the trimmed copy, so neither banner nor help ever announces itself and
  # the service functions do not exist. The core, the pack and the module must
  # still work, in both languages, with no error on stderr.
  [ -f "$KERNEL/agent.zsh" ] || skip "kernel not found"

  PROBE_LANG=zh_CN.UTF-8 run_kernel_lite <<'EOF'
_agsh_have banner && print "banner=1" || print "banner=0"
_agsh_have help   && print "help=1"   || print "help=0"
print "core=$+functions[_agsh_t] banner_fn=$+functions[_agsh_banner_add] help_fn=$+functions[_agsh_help_add]"
print "lang=$_agsh_lang"
print "first=$(print -r -- "$_AGENT_BANNER_TEXT" | head -1)"
print "lines=$(print -r -- "$_AGENT_BANNER_TEXT" | grep -c .)"
prompt t1 "x"
print "ctx=$(<"$AGENT_NODES_PATH/t1/context") parent=$(<"$AGENT_NODES_PATH/t1/parent")"
prompt; print "rc=$?"
EOF
  [ "$RC" -eq 0 ]
  [ "$OUT" = $'banner=0\nhelp=0\ncore=1 banner_fn=0 help_fn=0\nlang=zh\nfirst=  prompt     - 创建提示词节点\nlines=6\nctx=x parent=root\nrc=1' ]
  [[ "$ERR" == *"用法: prompt <id> <content> [parent]"* ]]
  [[ "$ERR" != *"command not found"* ]]
  [[ "$ERR" != *"no such file"* ]]

  # English path (P4: the provider-absent branch must be complete and English).
  # Only the two surfaces that bubble to stderr are expected here.
  PROBE_LANG=en_US.UTF-8 run_kernel_lite <<'EOF'
_agsh_have banner; print "banner=$?"
print "lang=$_agsh_lang first=$(print -r -- "$_AGENT_BANNER_TEXT" | head -1)"
print "lines=$(print -r -- "$_AGENT_BANNER_TEXT" | grep -c .)"
prompt t2 "y"
print "ctx=$(<"$AGENT_NODES_PATH/t2/context") parent=$(<"$AGENT_NODES_PATH/t2/parent")"
EOF
  [ "$RC" -eq 0 ]
  [ "$OUT" = $'banner=1\nlang=en first=  prompt     - Create a prompt node\nlines=6\nctx=y parent=root' ]
  [[ "$ERR" == *"[prompt] created node 't2' -> $BATS_TEST_TMPDIR/lite-nodes/t2/"* ]]
  [[ "$ERR" != *"command not found"* ]]
}

@test "core genuinely absent: prompt stays self-sufficient, English, and silent" {
  # Audit A4 / V1. The trimmed suite has neither i18n-core.zsh nor registry.zsh,
  # so nothing on disk can supply the core -- the module's channel-A guard is
  # the whole story. It must define the text API itself, create nodes, speak
  # English and raise nothing. The old "without i18n.zsh" probe never proved
  # this: prompt.zsh used to source the core unconditionally, so it was always
  # there (partly tautological).
  NOCORE="$BATS_TEST_TMPDIR/nocore"
  make_nocore "$NOCORE"

  # sourcing the module alone is successful and silent (0 bytes on stderr)
  run env -i HOME="$BATS_TEST_TMPDIR/nocore-home" PATH="$PATH" TMPDIR="$BATS_TEST_TMPDIR" \
    AGENT_NODES_PATH="$BATS_TEST_TMPDIR/nocore-nodes" \
    zsh -f -c "source \"$NOCORE/lib/prompt.zsh\""
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  run_nocore <<'EOF'
print "t=$+functions[_agsh_t] have=$+functions[_agsh_have] prompt=$+functions[prompt]"
print "core=$([[ -f $NOCORE/lib/i18n-core.zsh ]] && print present || print absent)"
prompt t1 "hello"; print "rc=$?"
print "ctx=$(<"$AGENT_NODES_PATH/t1/context") parent=$(<"$AGENT_NODES_PATH/t1/parent")"
prompt t2 "x" custom; print "p2=$(<"$AGENT_NODES_PATH/t2/parent")"
prompt; print "rc_noarg=$?"
print "lang=$_agsh_lang"
EOF
  [ "$RC" -eq 0 ]
  [ "$OUT" = $'t=1 have=1 prompt=1\ncore=absent\nrc=0\nctx=hello parent=root\np2=custom\nrc_noarg=1\nlang=en' ]
  [[ "$ERR" == *"usage: prompt <id> <content> [parent]"* ]]
  [[ "$ERR" == *"Creates a prompt node under $BATS_TEST_TMPDIR/nocore-nodes/<id>/"* ]]
  [[ "$ERR" == *"[prompt] created node 't1' -> $BATS_TEST_TMPDIR/nocore-nodes/t1/"* ]]
  [[ "$ERR" != *"command not found"* ]]
  [[ "$ERR" != *"no such file"* ]]
  [[ "$ERR" != *"bad floating point"* ]]
}

@test "negative control: the channel-A guard is load-bearing (the test above is not tautological)" {
  # PD2: an invariant needs a case that can actually fail. Strip the guard from
  # the very same nocore copy and the identical steps go red: sourcing raises
  # "command not found: _agsh_def", the module never defines `prompt`, and the
  # English falls away. This is what the guard buys.
  NOCORE="$BATS_TEST_TMPDIR/nocore-broken"
  make_nocore "$NOCORE" broken

  run env -i HOME="$BATS_TEST_TMPDIR/nocore-home" PATH="$PATH" TMPDIR="$BATS_TEST_TMPDIR" \
    AGENT_NODES_PATH="$BATS_TEST_TMPDIR/nocore-broken-nodes" \
    zsh -f -c "source \"$NOCORE/lib/prompt.zsh\""
  [ "$status" -ne 0 ]
  [[ "$output" == *"command not found: _agsh_def"* ]]

  env -i HOME="$BATS_TEST_TMPDIR/nocore-home" PATH="$PATH" TMPDIR="$BATS_TEST_TMPDIR" \
    AGENT_NODES_PATH="$BATS_TEST_TMPDIR/nocore-broken-nodes" \
    zsh -f -c "source \"$NOCORE/lib/prompt.zsh\"; print \$+functions[prompt]" \
    >"$BATS_TEST_TMPDIR/broken.out" 2>"$BATS_TEST_TMPDIR/broken.err"
  [ "$(cat "$BATS_TEST_TMPDIR/broken.out")" = "0" ]
  run grep -q 'command not found: _agsh_def' "$BATS_TEST_TMPDIR/broken.err"
  [ "$status" -eq 0 ]
}

# ─── lifecycle ───────────────────────────────────────────────────────────────

@test "unload removes the function and both advertised surfaces, without noise" {
  run_zsh <<'EOF'
source "$STDLIB/i18n.zsh"
source "$STDLIB/prompt.zsh"
print "fn=$+functions[prompt] row=$(print -r -- "$(_agsh_help_render)" | grep -c '^  prompt ')"
_agsh_unload
print "fn=$+functions[prompt]"
print "banner=$(print -r -- "$_AGENT_BANNER_TEXT" | grep -c '^  prompt ')"
print "help=$+functions[_agsh_help_render] hooks=${+_agsh_hooks_unload}"
EOF
  [ "$RC" -eq 0 ]
  [ "$OUT" = $'fn=1 row=1\nfn=0\nbanner=0\nhelp=0 hooks=0' ]
  [ -z "$ERR" ]
}

@test "unload pops the hook stack: the kernel banner is restored under the production order" {
  # Regression: ~/.agshrc loads i18n.zsh then prompt.zsh, so the unload hook
  # order is help -> kernel -> prompt. Iterating forward let prompt's banner
  # removal recompose _AGENT_BANNER_TEXT in the active language *after* the
  # kernel hook had restored the captured default. Unload must pop the stack
  # in reverse so the kernel restore is last.
  [ -f "$KERNEL/agent.zsh" ] || skip "kernel not found"
  PROBE_LANG=zh_CN.UTF-8 run_kernel <<'EOF'
print "pre=$(print -r -- "$_AGENT_BANNER_TEXT" | grep -c '^  prompt ')"
saved="$_agsh_kernel_banner_default"
_agsh_unload
[[ "$_AGENT_BANNER_TEXT" == "$saved" ]] && print RESTORED || print MISMATCH
print "lines=$(print -r -- "$_AGENT_BANNER_TEXT" | grep -c .)"
print "first=$(print -r -- "$_AGENT_BANNER_TEXT" | head -1)"
print "prompt_fn=$+functions[prompt]"
print "row=$(agent help | grep -c '^  prompt ')"
print "alias=${aliases[_agsh_help]}"
print "help_fn=$+functions[_agsh_help_render]"
EOF
  [ "$RC" -eq 0 ]
  [ "$OUT" = $'pre=1\nRESTORED\nlines=5\nfirst=  credential - Claim/release a credential\nprompt_fn=0\nrow=0\nalias=_agent_help_en\nhelp_fn=0' ]
  [ -z "$ERR" ]
}

@test "post-unload: the dispatchers degrade silently without a kernel fallback" {
  run_zsh <<'EOF'
source "$STDLIB/i18n.zsh"
_agsh_unload
print -r -- "t=$+functions[_agsh_t] d=$+functions[_agsh_help_dispatch]"
_agsh_help_dispatch
_agsh_credential_help_dispatch
_agsh_credential_status_dispatch set
_agsh_credential_status_dispatch cleared
print "reached-end"
EOF
  [ "$RC" -eq 0 ]
  [ "$OUT" = $'t=0 d=1\nreached-end' ]
  [ -z "$ERR" ]
}

@test "post-unload: the kernel surfaces are silent and byte-identical to the originals" {
  # R-1 regression. agent()/credential() bound the dispatchers at parse time, so
  # _agsh_unload cannot redirect them by restoring the aliases; the dispatchers
  # themselves must fall through to the kernel's English originals *without*
  # touching the removed core (no "command not found" on stderr).
  [ -f "$KERNEL/agent.zsh" ] || skip "kernel not found"
  PROBE_LANG=zh_CN.UTF-8 run_kernel <<'EOF'
_agsh_unload
agent help      >"$OUTDIR/help.out"     2>"$OUTDIR/help.err"
credential help >"$OUTDIR/credhelp.out" 2>"$OUTDIR/credhelp.err"
credential drop >"$OUTDIR/creddrop.out" 2>"$OUTDIR/creddrop.err"
print -r -- "core=${+_agsh_txt} t=$+functions[_agsh_t]"
EOF
  [ "$RC" -eq 0 ]
  [ "$OUT" = 'core=0 t=0' ]
  [ -z "$ERR" ]                       # the probe itself said nothing
  # agent help is a stdout surface; the two credential surfaces are stderr
  # surfaces by kernel design (the fixtures were captured with 2>&1), so the
  # right assertion is "byte-exact where the kernel writes it, empty elsewhere".
  [ ! -s "$OUTDIR/help.err" ]
  [ ! -s "$OUTDIR/credhelp.out" ]
  [ ! -s "$OUTDIR/creddrop.out" ]
  run cmp "$OUTDIR/help.out"      "$FIX/help.en.txt";       [ "$status" -eq 0 ]
  run cmp "$OUTDIR/credhelp.err"  "$FIX/cred-help.en.txt";  [ "$status" -eq 0 ]
  run cmp "$OUTDIR/creddrop.err"  "$FIX/cred-clear.en.txt"; [ "$status" -eq 0 ]
  # no residual noise anywhere, in particular no "command not found"
  run grep -R 'command not found' "$OUTDIR"; [ "$status" -ne 0 ]
}

# ─── static checks ───────────────────────────────────────────────────────────

@test "the L3 files parse" {
  run zsh -n "$STDLIB/prompt.zsh" "$STDLIB/bootstrap.zsh" "$STDLIB/cleanup.zsh"
  [ "$status" -eq 0 ]
}

@test "lint: the stdlib tree is clean with the L3 keys and call sites" {
  run zsh "$STDLIB/tools/i18n-lint.zsh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok:"* ]]
}
