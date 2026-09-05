#!/usr/bin/env zsh
# Regenerates the legacy text fixtures from the PRE-migration working tree.
# DO NOT run after lang/zh.zsh has been rewritten — these files are the oracle.
set -e
ISO=/tmp/mig2-i18n-iso
rm -rf $ISO; mkdir -p $ISO/home $ISO/tmp $ISO/nodes
printf 'source /Users/zic/agent-demo/agsh-stdlib/i18n.zsh\n' > $ISO/home/.agshrc
FIX="${0:A:h}"
run() { env -u AGENT_NODES_PATH HOME=$ISO/home TMPDIR=$ISO/tmp \
        AGENT_ROOT=/Users/zic/agent-demo/agent-shell AGENT_NODES_PATH=$ISO/nodes \
        AGENT_API_KEY=dummy LANG="$1" \
        zsh -f -c "source /Users/zic/agent-demo/agent-shell/agent.zsh >/dev/null 2>&1; $2"; }
run en_US.UTF-8 '_agent_help_en'                                  > "$FIX/help.en.txt"
run zh_CN.UTF-8 '_agent_help_zh'                                  > "$FIX/help.zh.txt"
run en_US.UTF-8 'print -r -- "$_AGENT_BANNER_TEXT"'               > "$FIX/banner-base.en.txt"
run zh_CN.UTF-8 'print -r -- "$_AGENT_BANNER_TEXT"'               > "$FIX/banner-base.zh.txt"
run en_US.UTF-8 '_agent_credential_help_en'                       > "$FIX/cred-help.en.txt" 2>&1
run zh_CN.UTF-8 '_agent_credential_help_zh'                       > "$FIX/cred-help.zh.txt" 2>&1
run en_US.UTF-8 'CREDENTIAL=testid _agent_credential_status_en set'    > "$FIX/cred-set.en.txt" 2>&1
run zh_CN.UTF-8 'CREDENTIAL=testid _agent_credential_status_zh set'    > "$FIX/cred-set.zh.txt" 2>&1
run en_US.UTF-8 '_agent_credential_status_en cleared'             > "$FIX/cred-clear.en.txt" 2>&1
run zh_CN.UTF-8 '_agent_credential_status_zh cleared'             > "$FIX/cred-clear.zh.txt" 2>&1
