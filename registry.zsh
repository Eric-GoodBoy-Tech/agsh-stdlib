# registry.zsh — dependency-free plugin registry (identity + soft dependency)
#
# Role: let one extension announce a name (an "id") and a handful of named
# members, and let a caller ask for a member without knowing who provides it.
# This is the suite's single cross-component dispatch mechanism.
#
#   typeset -gA _agsh_api       "<id>.<member>" -> implementation (function name)
#   typeset -gA _agsh_plugins   "<id>"          -> 1
#
#   _agsh_register <id> [member=impl ...]  announce identity + members; idempotent,
#                                          re-registering a member overwrites it
#   _agsh_have <id>                        soft dependency probe: 0 = registered,
#                                          1 = absent
#   _agsh_call <id.member> [args...]       dispatch to "${_agsh_api[<k>]:-_agsh_none}"
#                                          with the args; a missing member is a no-op
#   _agsh_none                             neutral default: present -> call, absent
#                                          -> nothing happens
#
# Contract: this file knows no id. It never mentions "banner", "help" or "i18n";
# every plugin name and member name comes from the plugin itself. Zero
# dependencies, idempotent (sourcing it twice is safe). i18n-core.zsh sources
# it, so any module that already sources the core gets the registry too.

typeset -gA _agsh_api
typeset -gA _agsh_plugins

_agsh_register() {
  local id="${1:-}"; shift
  [[ -n "$id" ]] || return 1
  _agsh_plugins[$id]=1
  local pair member impl
  for pair in "$@"; do
    [[ "$pair" == *=* ]] || continue
    member="${pair%%=*}"; impl="${pair#*=}"
    [[ -n "$member" && -n "$impl" ]] || continue
    _agsh_api[$id.$member]="$impl"
  done
  return 0
}

_agsh_have() {
  [[ -n "${1:-}" && -n "${_agsh_plugins[${1}]:-}" ]]
}

_agsh_call() {
  local k="${1:-}"; shift
  "${_agsh_api[$k]:-_agsh_none}" "$@"
}

_agsh_none() { return 0 }
