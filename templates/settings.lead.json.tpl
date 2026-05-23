{
  "permissions": {
    "defaultMode": "bypassPermissions",
    "allow": [
      "Read",
      "Write",
      "Bash(rm:*)",
      "Bash(rm -rf:*)",
      "Bash(jq:*)",
      "Bash(tmux:*)",
      "Bash(ls:*)",
      "Bash(cat:*)",
      "Bash(date:*)",
      "Bash(kill -0:*)",
      "Bash(printf:*)",
      "Bash(head:*)"
    ],
    "deny": [
      "Bash(git push --force:*)",
      "Bash(dd of=:*)",
      "Bash(sudo:*)",
      "Bash(curl * | sh)"
    ]
  }
}
