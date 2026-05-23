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
            "command": "WORKER=\"{{ENTRY_NAME}}\" ENTRY_ROLE=\"{{ENTRY_ROLE}}\" PROJECT_ROOT=\"{{PROJECT_ROOT}}\" HARNESS_ROOT=\"{{HARNESS_ROOT}}\" bash \"{{HARNESS_ROOT}}/bin/permission-gate.sh\""
          }
        ]
      }
    ]
  }
}
