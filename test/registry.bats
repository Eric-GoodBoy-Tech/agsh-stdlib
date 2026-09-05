#!/usr/bin/env bats
# registry.bats — unit tests for registry.zsh, the suite's one cross-component
# mechanism: a provider announces an id and named members, a caller asks
# _agsh_have before using a service and dispatches through _agsh_call without
# knowing who provides what. The file itself knows no id.
#
# Every probe runs in a throwaway environment (env -i, isolated HOME/TMPDIR,
# LANG fixed) so nothing here can touch the developer's shell or ~/.agshrc.

setup() {
  STDLIB="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  mkdir -p "$BATS_TEST_TMPDIR/home"
}

run_zsh() {
  local script="$BATS_TEST_TMPDIR/probe.zsh" errf="$BATS_TEST_TMPDIR/err"
  cat > "$script"
  OUT="$(env -i HOME="$BATS_TEST_TMPDIR/home" PATH="$PATH" TMPDIR="$BATS_TEST_TMPDIR" \
        STDLIB="$STDLIB" LANG="${PROBE_LANG:-en_US.UTF-8}" ${PROBE_EXTRA:-} \
        zsh -f "$script" 2>"$errf")"
  RC=$?
  ERR="$(cat "$errf")"
}

# ─── identity ────────────────────────────────────────────────────────────────

@test "registry is standalone and knows no id" {
  run_zsh <<'EOF'
source "$STDLIB/registry.zsh"
_agsh_have banner && print yes || print no
_agsh_have nope   && print yes || print no
_agsh_have ''     && print yes || print no
EOF
  [ "$RC" -eq 0 ]
  [ "$OUT" = $'no\nno\nno' ]
  [ -z "$ERR" ]
}

@test "_agsh_have stays false until a provider announces itself" {
  run_zsh <<'EOF'
source "$STDLIB/registry.zsh"
_agsh_have probe; print "before=$?"
_agsh_register probe
_agsh_have probe; print "after=$?"
print "table=${_agsh_plugins[probe]}"
EOF
  [ "$RC" -eq 0 ]
  [ "$OUT" = $'before=1\nafter=0\ntable=1' ]
  [ -z "$ERR" ]
}

# ─── members: register, dispatch, overwrite ──────────────────────────────────

@test "a registered member is dispatched with its arguments" {
  run_zsh <<'EOF'
source "$STDLIB/registry.zsh"
_probe_ping() { print -r -- "ping:$*" }
_agsh_register probe ping=_probe_ping
print "impl=${_agsh_api[probe.ping]}"
_agsh_call probe.ping hello world
EOF
  [ "$RC" -eq 0 ]
  [ "$OUT" = $'impl=_probe_ping\nping:hello world' ]
  [ -z "$ERR" ]
}

@test "an absent member is a no-op: _agsh_none, exit 0, no output" {
  run_zsh <<'EOF'
source "$STDLIB/registry.zsh"
_agsh_register probe
_agsh_call probe.gone a b c; print "rc=$?"
EOF
  [ "$RC" -eq 0 ]
  [ "$OUT" = "rc=0" ]
  [ -z "$ERR" ]
}

@test "re-registering is idempotent; a same-named member is overwritten" {
  run_zsh <<'EOF'
source "$STDLIB/registry.zsh"
_first()  { print -r -- one }
_second() { print -r -- two }
_agsh_register probe ping=_first
_agsh_register probe ping=_second
print "ids=${#_agsh_plugins} members=${#_agsh_api}"
_agsh_call probe.ping
EOF
  [ "$RC" -eq 0 ]
  [ "$OUT" = $'ids=1 members=1\ntwo' ]
  [ -z "$ERR" ]
}

@test "malformed input is ignored without noise" {
  run_zsh <<'EOF'
source "$STDLIB/registry.zsh"
print "empty=$( _agsh_register '' ping=_x; print $? )"
_agsh_register probe notapair ping=_impl
print "ids=${#_agsh_plugins} members=${#_agsh_api}"
print "impl=${_agsh_api[probe.ping]}"
EOF
  [ "$RC" -eq 0 ]
  [ "$OUT" = $'empty=1\nids=1 members=1\nimpl=_impl' ]
  [ -z "$ERR" ]
}

# ─── who registers what ──────────────────────────────────────────────────────

@test "core brings the registry, and the suite's providers announce through it" {
  run_zsh <<'EOF'
source "$STDLIB/i18n-core.zsh"
_agsh_have banner; print "core-banner=$?"
_agsh_have help;   print "core-help=$?"
source "$STDLIB/i18n.zsh"
_agsh_have banner; print "suite-banner=$?"
_agsh_have help;   print "suite-help=$?"
print "banner.add=${_agsh_api[banner.add]}"
print "help.render=${_agsh_api[help.render]}"
EOF
  [ "$RC" -eq 0 ]
  [ "$OUT" = $'core-banner=1\ncore-help=1\nsuite-banner=0\nsuite-help=0\nbanner.add=_agsh_banner_add\nhelp.render=_agsh_help_render' ]
  [ -z "$ERR" ]
}
