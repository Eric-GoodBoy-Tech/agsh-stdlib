#!/usr/bin/env zsh
# help-readme.zsh — render the structured help registry as a markdown table.
#
# Usage: zsh tools/help-readme.zsh [lang]
# Exit:  0 ok, 2 not a stdlib dir
#
# One source, two outputs: `agent help` and the README table both come from the
# registry in help.zsh plus the pack texts, so documentation cannot drift from
# the interface. mig2-docs pastes this output into README.md / README.zh.md.
emulate -L zsh
local dir="${0:A:h:h}"
if [[ ! -f "$dir/i18n.zsh" ]]; then
  print -r -- "[help-readme] not a stdlib dir: $dir" >&2
  exit 2
fi
source "$dir/i18n.zsh"
_agsh_help_readme "${1:-}"
