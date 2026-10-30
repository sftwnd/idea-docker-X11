#!/bin/bash
# Entry point of the IDEA container.
# Lock files left by a killed container make IDEA refuse to start, and nothing runs yet, so all of them are stale.
find ~/.config/JetBrains ~/.cache/JetBrains -name "*.lock" -type f -delete 2> /dev/null || true
exec /opt/idea/bin/idea.sh "$@"
