{
  "permissions": {
    "allow": [
      "Read",
      "Grep",
      "Glob",
      "Write({{PROJECT_ROOT}}/.agent-harness/review/**)",
      "Edit({{PROJECT_ROOT}}/.agent-harness/review/**)",
      "Write({{PROJECT_ROOT}}/.agent-harness/.review-cursor.*)",
      "Edit({{PROJECT_ROOT}}/.agent-harness/.review-cursor.*)"
    ],
    "deny": [
      "Skill(awa)"
    ]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash|Edit|Write|Agent|WebFetch",
        "hooks": [{
          "type": "command",
          "command": "WORKER=\"{{ENTRY_NAME}}\" ENTRY_ROLE=\"{{ENTRY_ROLE}}\" PROJECT_ROOT=\"{{PROJECT_ROOT}}\" HARNESS_PROJECT=\"{{PROJECT_ROOT}}\" HARNESS_ROOT=\"{{HARNESS_ROOT}}\" bash \"{{HARNESS_ROOT}}/bin/permission-gate.sh\""
        }]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [{
          "type": "command",
          "command": "EVENTS_LOG=\"{{PROJECT_ROOT}}/.agent-harness/events.log\" REPO_ROOT=\"{{PROJECT_ROOT}}\" bash \"{{HARNESS_ROOT}}/bin/log-event.sh\""
        }]
      }
    ]
  }
}
