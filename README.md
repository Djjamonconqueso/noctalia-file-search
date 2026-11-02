# File Search for Noctalia

A plugin source repository for Noctalia. File Search provides a panel for searching and previewing files indexed locally by DigUp.

## Install from GitHub

Add this repository as a Git plugin source in Noctalia, then enable **File Search** in Settings → Plugins:

```sh
noctalia msg plugins source add file-search git https://github.com/Djjamonconqueso/noctalia-file-search.git
noctalia msg plugins enable yo/ollama-file-search
```

## Local development

Add the repository root as a `path` source. Do not select the `ollama-file-search` subdirectory: Noctalia reads `catalog.toml` from the source root and locates the plugin directory from its ID.

```text
~/src/noctalia-ollama-search
```

See [`ollama-file-search/README.md`](ollama-file-search/README.md) for DigUp installation, requirements, settings, and usage.
