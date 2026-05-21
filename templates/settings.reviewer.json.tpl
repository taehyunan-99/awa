{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [{
          "type": "command",
          "command": "PERMISSION_EVENTS_LOG=\"{{PROJECT_ROOT}}/.agent-harness/permission-events.log\" WORKER=\"reviewer\" bash \"{{HARNESS_ROOT}}/bin/log-deny.sh\""
        }]
      }
    ]
  }
}
