{
  "permissions": {
    "allow": [
      "Read",
      "Grep",
      "Glob",
      "Bash(ls:*)",
      "Bash(cat:*)",
      "Bash(grep:*)",
      "Bash(rg:*)",
      "Bash(find:*)",
      "Bash(head:*)",
      "Bash(tail:*)",
      "Bash(wc:*)",
      "Bash(jq:*)",
      "Bash(date:*)",
      "Bash(tmux:*)",
      "Bash(mkdir:*)",
      "Bash(mv:*)"
    ],
    "deny": [
      "Write",
      "Edit",
      "NotebookEdit",
      "Bash(sudo:*)",
      "Bash(dd:*)",
      "Bash(git push --force:*)",
      "Bash(chmod 777:*)"
    ]
  }
}
