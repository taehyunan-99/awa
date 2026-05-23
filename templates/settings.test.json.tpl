{
  "permissions": {
    "deny": [
      "Bash(rm *)",
      "Bash(/usr/bin/rm *)",
      "Bash(/bin/rm *)"
    ]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash|Edit|Write|Agent|WebFetch",
        "hooks": [{
          "type": "command",
          "command": "WORKER=\"{{ENTRY_NAME}}\" ENTRY_ROLE=\"{{ENTRY_ROLE}}\" PROJECT_ROOT=\"{{PROJECT_ROOT}}\" HARNESS_ROOT=\"{{HARNESS_ROOT}}\" bash \"{{HARNESS_ROOT}}/bin/permission-gate.sh\""
        }]
      }
    ]
  }
}
