# File Search

Search the local index maintained by DigUp from a Noctalia panel. Browse semantic results, preview files, and open the selected result without sending file contents to a remote service.

## Plugin

| Field | Value |
| --- | --- |
| ID | `yo/ollama-file-search` |
| Entries | Panel: `search` |

## Requirements

- Install DigUp separately from its [official GitHub releases](https://github.com/ARahim3/DigUp/releases). Use its AppImage on Arch and other distributions, or its `.deb` package on Debian, Ubuntu, and Mint. Open DigUp, download its model, choose folders, and let it index them.
- The plugin calls the `digup` CLI helper. It tries the `PATH`, the system `.deb` location, App Manager installations under `~/Applications/.installed` and `~/Applications/DigUp Portable`, and an open AppImage. If automatic detection fails, set **DigUp CLI path** to the helper's full path. The App Manager helper is usually at `~/Applications/.installed/DigUp/usr/lib/DigUp/helper/digup`; the AppImage must remain open for automatic detection.
- External commands: `digup`, `find`, `sh`, `pgrep`, `readlink`, and `xdg-open`.
- Optional preview commands: `ffmpeg` for video thumbnails and `pdftoppm` (Poppler) for PDF previews.
- Noctalia Shell 5.4.0 or later (plugin API 43).

## Usage

Enable **File Search** in Settings → Plugins. Add folders and wait for indexing in DigUp. Open the panel and enter a query. Use the filter buttons or Left/Right to switch between all files, images, text, and videos. Up/Down changes the selected result; Enter opens it with `xdg-open`.

Open the panel from a compositor keybind with:

```sh
noctalia msg panel-toggle yo/ollama-file-search:search
```

Ctrl+K clears the query and focuses the search field. By default, **Keep preview always visible** opens the first result's preview and keeps it updated while navigating. Turn the setting off to toggle previews with Space.

## Settings

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `digup_cli` | `string` | `""` | Optional path to DigUp's `digup` helper. Leave blank for automatic detection. |
| `max_results` | `int` | `8` | Maximum results shown (1–30). |
| `keep_preview_open` | `bool` | `true` | Automatically preview the first result and keep its preview visible while navigating. |

## Notes

- DigUp, its model, and its index are separate from this plugin and are not bundled or downloaded by it. Install DigUp from its official releases; this plugin only invokes its local CLI and reads the selected file for previews.
- Searches use DigUp's local index. File previews are read locally. Opening a result runs `xdg-open` for that path.
- Video and PDF previews need the optional commands listed above. Other unsupported formats still show file metadata and can be opened externally.
- DigUp code search is available when configured in DigUp; prefix a query with `code:`.
