{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "EVENTS_LOG=\"__REPO__/workspace/events.log\" REPO_ROOT=\"__REPO__\" bash \"__REPO__/bin/log-event.sh\""
          }
        ]
      }
    ]
  }
}
