# File Search for Noctalia

A plugin source repository for Noctalia. File Search provides a panel for searching and previewing files indexed locally by DigUp.

## Install from GitHub

Add this repository as a Git plugin source in Noctalia, then enable **File Search** in Settings → Plugins:

```sh
noctalia msg plugins source add file-search git https://github.com/Djjamonconqueso/noctalia-file-search.git
noctalia msg plugins enable yo/ollama-file-search
```

## DigUp dependency

File Search does not include DigUp's CLI helper or model. Download DigUp from its [official GitHub releases](https://github.com/ARahim3/DigUp/releases): use the AppImage on Arch and most other Linux distributions, or the `.deb` package on Debian, Ubuntu, and Mint. Open DigUp, download its model, select folders, and let it index them.

The plugin uses DigUp's `digup` helper, not the `digup-shell` graphical launcher. It looks for the helper automatically in the `PATH`, the system `.deb` location, App Manager installs under `~/Applications/.installed` and `~/Applications/DigUp Portable`, and an open AppImage. If detection fails, set **DigUp CLI path** to the helper, usually `<DigUp install>/usr/lib/DigUp/helper/digup`. See the [plugin README](ollama-file-search/README.md) for setup details.

## Local development

Add the repository root as a `path` source. Do not select the `ollama-file-search` subdirectory: Noctalia reads `catalog.toml` from the source root and locates the plugin directory from its ID.

```text
~/src/noctalia-ollama-search
```

See [`ollama-file-search/README.md`](ollama-file-search/README.md) for DigUp installation, requirements, settings, and usage.
