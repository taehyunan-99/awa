{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "EVENTS_LOG=\"__PROJECT_ROOT__/.agent-harness/events.log\" REPO_ROOT=\"__PROJECT_ROOT__\" bash \"__HARNESS_ROOT__/bin/log-event.sh\""
          }
        ]
      }
    ]
  }
}
