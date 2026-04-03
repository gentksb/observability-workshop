#!/bin/bash
# Prevent .claude directory files from being committed on translate/* branches
#
# Triggered by: PreToolUse hook with if="Bash(git commit *)"
# Only runs when Claude executes git commit commands.
#
# Exit behavior (PreToolUse):
#   - exit 0 with permissionDecision "deny": block the tool call
#   - exit 0 with no stdout: allow the tool call
set -e

# Check current branch
current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

# Only apply restriction on translate/* branches
if [[ ! "$current_branch" =~ ^translate/ ]]; then
  exit 0
fi

# Check if any .claude files are staged for commit
staged_claude_files=$(git diff --cached --name-only 2>/dev/null | grep '^\.claude/' || true)

if [[ -n "$staged_claude_files" ]]; then
  file_list=$(echo "$staged_claude_files" | sed 's/^/  - /')

  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Cannot commit .claude directory files on translate/* branches.\nStaged .claude files detected:\n${file_list}\n\nThe .claude directory should only be modified on the ja-translation-system branch.\nPlease unstage these files: git reset HEAD .claude/"
  }
}
EOF
  exit 0
fi

exit 0
