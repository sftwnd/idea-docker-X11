#!/bin/bash
# Entry point of the IDEA container.
# Lock files left by a killed container make IDEA refuse to start, and nothing runs yet, so all of them are stale.
find ~/.config/JetBrains ~/.cache/JetBrains -name "*.lock" -type f -delete 2> /dev/null || true
# The host git configuration is mounted as ~/.gitconfig-host. Its credential helpers are host programs such as
# osxkeychain, so the container configuration includes it and replaces them with the git credential cache.
if [ -f ~/.gitconfig-host ] && [ ! -e ~/.gitconfig ]; then
  printf '[include]\n\tpath = .gitconfig-host\n[credential]\n\thelper =\n\thelper = cache --timeout=86400\n' > ~/.gitconfig
fi
exec /opt/idea/bin/idea.sh "$@"
