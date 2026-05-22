{
  "permissions": {
    "allow": [
      "Read", "Glob", "Grep",
      "Bash(ls:*)", "Bash(cat:*)", "Bash(grep:*)", "Bash(rg:*)", "Bash(find:*)",
      "Bash(head:*)", "Bash(tail:*)", "Bash(wc:*)"
    ],
    "deny": [
      "Bash(rm -rf /:*)",
      "Bash(rm -rf /*:*)",
      "Bash(sudo:*)",
      "Bash(dd:*)",
      "Bash(git push --force:*)",
      "Bash(git push --force-with-lease:*)",
      "Bash(chmod 777:*)"
    ]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "PERMISSION_EVENTS_LOG=\"{{PROJECT_ROOT}}/.agent-harness/permission-events.log\" WORKER=\"{{ENTRY_NAME}}\" bash \"{{HARNESS_ROOT}}/bin/log-deny.sh\""
          }
        ]
      }
    ]
  }
}
