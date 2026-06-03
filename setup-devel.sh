#!/bin/sh

if ! type git >/dev/null 2>&1
then
  echo "\`git\` is not installed! Cannot setup development environment." >&2
  exit 1
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1
then
  echo "Current working directory is not a git repository. Cannot setup development environment." >&2
  exit 1
fi

git_top_level="$(git rev-parse --show-toplevel)"

# Force copy in order to have the latest pre-commit hook
if ! cp -f "$git_top_level/hooks/pre-commit" "$(git rev-parse --git-common-dir)/hooks/"
then
  exit 1
fi

exit 0
