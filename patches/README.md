This patches were generated using roughly the following command:

```sh
# Run it from root repo directory
{
  echo "From: John Doe <john.d@example.com>"
  echo "Date: $(date -R)"
  echo "Subject: [PATCH] ..."
  # Additional patch comments...
  echo ""
  git diff --no-index --no-prefix a b
} > patches/...
```

Where `a` is the directory that contains the original files and structure, and `b` is the modified version. These directories are just for patch-generation purposes, and were generated temporarily in my machine, they don't really exists in the repository.
