# Brisklance Self-Update — Architecture Specification

> Vendored from the original design spec so the knowledge lives in-repo.
> Companion document: [`REMAINING_TASKS.md`](REMAINING_TASKS.md) tracks the
> phased implementation.

## Problem

There is no easy way to update Brisklance itself. The manager lives at
`res://addons/brisklance/manager` and is only refreshed by manually downloading
`brisklance.zip` from the release page and re-extracting it over the install.

## Goal

On editor start, Brisklance checks its own repository for a newer release. When
one exists, the dock shows a non-blocking notice with an "Update" button. The
user clicks to apply; the manager directory is replaced in place and the editor
restarts. Nothing is applied without an explicit click.

## Scope

- **In:** version detection, release lookup, download + extract + swap of
  `res://addons/brisklance/manager`, dock notice UI, a dedicated
  `brisklance_manager.zip` release artifact, docs.
- **Out:** auto-apply without a click; staging the swap for the next launch;
  updating anything outside `manager/` (the user's `self/`, `plugins/`,
  `self/vendor/` are never touched by the updater); rollback tooling.

## Decisions

| Question | Decision |
| --- | --- |
| Trigger / apply | Auto-check on startup, manual apply (notice + button in the dock). |
| Update artifact | New dedicated `brisklance_manager.zip` release asset containing only `manager/`. |
| Version comparison | Semver compare; offer only when latest is strictly greater than current. |
| Apply strategy | Swap immediately on click (extract to staging, validate, delete + rename), then restart the editor. |
| Code structure | Standalone `BrisklanceSelfUpdater` (`RefCounted`) in `manager/scripts/`. |
| Source repository | Hardcoded constant `brisketty/brisklance`. |

## Components

### 1. `BrisklanceSelfUpdater` — `manager/scripts/self_updater.gd`

`class_name BrisklanceSelfUpdater`, `extends RefCounted`, `@tool`.

Constants:

- `REPOSITORY_NAME := "brisketty/brisklance"`
- `MANAGER_ZIP_FILE_NAME := "brisklance_manager.zip"`
- `MANAGER_DIRECTORY_PATH := "res://addons/brisklance/manager"`
- `STAGING_DIRECTORY_PATH := "res://addons/brisklance/.brisklance_manager_update"`
- `CONFIGURATION_FILE_NAME := "plugin.cfg"`
- `PLUGIN_SECTION_KEY := &"plugin"`, `VERSION_KEY := &"version"`
- `LATEST_RELEASE_URL_TEMPLATE := "https://api.github.com/repos/{repository_name}/releases/latest"`

Methods:

- `static normalize_version(p_version: String) -> PackedInt32Array`
  Length-3 array. Strips a single leading `v`/`V`, splits on `.`, parses each
  segment as `int`, missing segments are `0`.

- `static compare_versions(p_a: String, p_b: String) -> int`
  Compares normalized versions left to right. Returns `1` if `a` > `b`, `-1` if
  `a` < `b`, `0` if equal. Pure function, no engine state.

- `get_current_version() -> String`
  Loads `MANAGER_DIRECTORY_PATH/plugin.cfg` via `ConfigFile`, returns
  `[plugin] version` (or `""` on failure).

- `compute_request_headers(p_accept: String) -> PackedStringArray`
  Always `Accept: <p_accept>`, plus `Authorization: Bearer <key>` when
  `BrisklanceLocalDevelopmentStore.get_singleton().github_api_key` is non-empty.
  Mirrors `BrisklancePluginMirror.compute_download_mirror_request_headers`.

- `fetch_latest_release_metadata(p_http_request: HTTPRequest) -> Dictionary`
  `GET` the latest-release endpoint with `Accept: application/vnd.github+json`.
  On any failure (request error, non-`RESULT_SUCCESS`, non-200, unparseable
  body) logs via `printerr` in the codebase style and returns `{}`.

- `fetch_latest_version(p_http_request: HTTPRequest) -> String`
  Returns `tag_name` from the metadata, or `""`.

- `is_update_available(p_http_request: HTTPRequest) -> String`
  Returns the latest `tag_name` when
  `compare_versions(latest, get_current_version()) > 0`, else `""`.

- `resolve_manager_zip_url(p_http_request: HTTPRequest) -> String`
  From the metadata, the `url` of the asset whose `name` equals
  `MANAGER_ZIP_FILE_NAME` (same asset-lookup loop as
  `BrisklancePluginMirror.compute_download_mirror_request_url`). Missing asset →
  `printerr`, `""`.

- `install_staged_update(p_zip_file_path: String) -> bool`
  1. If `STAGING_DIRECTORY_PATH` exists, remove it first
     (`BrisklancePluginMirror.remove_directory_recursively`).
  2. `BrisklancePluginMirror.extract_zip_recursively_to_path(p_zip_file_path,
     STAGING_DIRECTORY_PATH)`. The archive is rooted at `manager/`, so this
     yields `STAGING_DIRECTORY_PATH/manager/...`.
  3. **Validate.** `STAGING_DIRECTORY_PATH/manager/plugin.cfg` must exist and its
     `[plugin] version` must compare strictly greater than
     `get_current_version()`. On failure: remove the staging directory,
     `printerr`, return `false`. Nothing destructive has happened yet.
  4. **Swap.**
     `BrisklancePluginMirror.remove_directory_recursively(MANAGER_DIRECTORY_PATH)`,
     then `DirAccess.rename_absolute(STAGING_DIRECTORY_PATH + "/manager",
     MANAGER_DIRECTORY_PATH)`. Remove the now-empty staging directory.
  5. Return `true`.

- `apply_update(p_http_request: HTTPRequest) -> bool`
  1. `resolve_manager_zip_url`; empty → `false`.
  2. Download to a temp file: `DirAccess.create_temp(...)` for the directory,
     set `p_http_request.download_file`, request with
     `Accept: application/octet-stream` + optional auth header. Attach
     `DownloadReporter.start_report(p_http_request)` for progress logging, as in
     `BrisklancePluginMirror.retreive_self`. Non-200 → `printerr`, `false`.
  3. `install_staged_update(zip_file_path)`.

The only genuinely dangerous window is a failure between the `manager/` delete
and the rename. Both paths are in the same project directory on one volume; the
error is logged; recovery is the manual `brisklance.zip` reinstall that exists
today. Accepted risk for an editor tool.

### 2. Dock UI

**Scene — `manager/interface/brisklance/brisklance.tscn`:**

- New `UpdateNotice` `HBoxContainer` inserted between `AddonsDisplay` and
  `Footer` in `MarginContainer/VBoxContainer`. Children:
  - `Label` (`size_flags_horizontal = 3`)
  - `UpdateTrigger` `Button`, `text = "Update"`
  - `UpdateNotice.visible = false` by default.
- New `ConfirmUpdateWindow` `ConfirmationDialog` as a sibling of
  `ConfirmDeleteWindow` / `ConfirmVendorWindow`. `ok_button_text = "Update"`,
  `dialog_text` explaining the editor will restart.
- New dedicated `UpdateHTTPRequest` `HTTPRequest` node so update traffic never
  contends with the existing install/commit `HTTPRequest`.
- The root node's `node_paths` `PackedStringArray` and the `node_*` NodePath
  assignments gain the new entries.

**Script — `manager/interface/brisklance/brisklance.gd`:**

- New exports in the existing `@export_group("Nodes", "node_")`:
  - `node_update_notice: HBoxContainer`
  - `node_update_notice_label: Label`
  - `node_update_trigger: BaseButton`
  - `node_confirm_update_window: ConfirmationDialog`
  - `node_update_http_request: HTTPRequest`
- New `@export_group("Update Notice", "update_notice_")`:
  - `@export_multiline var update_notice_text_prefix := "Brisklance update available: "`
- New members: `var self_updater := BrisklanceSelfUpdater.new()`,
  `var is_checking_for_update := false`
- New method `check_for_update() -> void`:
  - re-entrancy guarded by `is_checking_for_update`
  - `var latest := await self_updater.is_update_available(node_update_http_request)`
  - empty → `node_update_notice.hide()`, return
  - else → `node_update_notice_label.text = update_notice_text_prefix + latest`,
    `node_update_notice.show()`
- `_ready()` calls `check_for_update()` after `commit()`.
- The existing Refresh button handler also calls `check_for_update()`.
- New handler `handle_node_update_trigger_pressed()` →
  `node_confirm_update_window.show()`.
- New handler `handle_node_confirm_update_window_confirmed()`:
  - `var succeeded := await self_updater.apply_update(node_update_http_request)`
  - `succeeded` → `EditorInterface.restart_editor(true)`
  - else → leave the notice visible (error already printed)
- Both new handlers are connected via `.connect()` in `_ready()`.

**Convention note.** `CLAUDE.md` mandates `handle_`-prefixed handler methods
connected in `_ready()`. This file currently wires every signal as an inline
lambda. New code follows `CLAUDE.md` (named `handle_` methods); the existing
lambdas are left as-is.

**Deviation from the original design, intentional.** The design said the check
reuses `node_http_request`; the implementation adds a dedicated
`node_update_http_request` node instead, to avoid racing the un-awaited
`commit()` call in `_ready()`. Same UX, no shared-resource contention.

### 3. Publish workflow — `.github/workflows/publish.yml`

- Add a step before `Release`:

  ```yaml
  - name: Zip manager
    working-directory: ${{ github.workspace }}/addons/brisklance
    run: zip -r ${{ github.workspace }}/brisklance_manager.zip manager
  ```

- Add `${{ github.workspace }}/brisklance_manager.zip` to the release `files:`
  list.
- Rename the two existing steps (both currently "Zip module") to "Zip module"
  and "Zip suite" for clarity.

### 4. Version bump — `addons/brisklance/manager/plugin.cfg`

Bump `version` from `1.1.0` to `1.2.0` so the first release carrying the updater
is detected as newer by existing installs.

### 5. Docs — `README.md`

New subsection under "Setting up" titled "Updating Brisklance": on editor start
Brisklance checks its repository's latest release; a newer version surfaces a
notice in the dock; clicking "Update" replaces only
`res://addons/brisklance/manager` and restarts the editor. A GitHub API key set
in the dock's Github Setting raises the API rate limit but is not required for a
public repository.

## Data Flow

```
editor start
  -> BrisklanceInterface._ready()
     -> commit()                      (existing)
     -> check_for_update()
        -> self_updater.is_update_available(node_update_http_request)
           -> GET releases/latest
           -> compare_versions(tag_name, plugin.cfg version)
        -> update notice shown / hidden

user clicks "Update"
  -> ConfirmUpdateWindow
  -> handle_node_confirm_update_window_confirmed()
     -> self_updater.apply_update(node_update_http_request)
        -> GET releases/latest, resolve brisklance_manager.zip asset url
        -> download to temp
        -> extract to .brisklance_manager_update/
        -> validate .brisklance_manager_update/manager/plugin.cfg
        -> remove manager/, rename staged manager/ into place
     -> EditorInterface.restart_editor(true)
```

## Error Handling

- Every network / parse failure in `BrisklanceSelfUpdater` logs via `printerr`
  and returns an empty / falsy value; the dock silently shows no notice (check
  path) or leaves the notice visible (apply path).
- `apply_update` validates the staged archive before deleting anything.
- A staging directory left behind by an aborted run is removed at the start of
  the next `install_staged_update`.

## Testing

- `BrisklanceSelfUpdater.compare_versions` is a pure function — cover
  `1.2.0` vs `1.10.0`, `v1.2.0` vs `1.2.0`, `1.2` vs `1.2.0`, equal, and
  greater/less in each position. Add a minimal `SceneTree`-based check script
  under `/tests` (per `CLAUDE.md` directory rules) runnable with
  `godot --headless --script`.
- The network and filesystem paths are verified manually in-editor against a
  real pre-release: confirm the notice appears, "Update" swaps `manager/`, the
  editor restarts, and the new version no longer shows a notice.
- Verify `brisklance_manager.zip` layout from the workflow (`manager/` at the
  archive root).

## Risks

- Self-modifying code: `apply_update` deletes and rewrites scripts that are
  currently loaded. Mitigated by doing the swap only on an explicit click and
  restarting the editor immediately after; not fully eliminated.
- GitHub anonymous API rate limit (60/hr per IP). One `releases/latest` call per
  editor start. An API key raises the limit; a rate-limited check just shows no
  notice.
- A fork cannot self-update from its own repository without editing
  `REPOSITORY_NAME`. Acceptable; noted in the constant.
