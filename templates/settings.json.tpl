{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "EVENTS_LOG=\"{{PROJECT_ROOT}}/.agent-harness/events.log\" REPO_ROOT=\"{{PROJECT_ROOT}}\" bash \"{{HARNESS_ROOT}}/bin/log-event.sh\""
          }
        ]
      }
    ]
  }
}
