# Brisklance Self-Update — Remaining Tasks

Design: [`ARCHITECTURE_SPEC.md`](ARCHITECTURE_SPEC.md).

## Post-release bug — swap gutted `manager/` (fixed in `1.2.3`)

**Reported on a `v1.2.2` install:** update downloaded, then "stopped"; after a
reload `manager/` was empty except `singletons/local_development_store/`.

**Cause:** `BrisklancePluginMirror.remove_directory_recursively` listed directory
contents with `DirAccess` defaults, which **exclude hidden files**. The dotfile
`singletons/local_development_store/.gitignore` was never deleted, so that
directory (and therefore `manager/`) could not be emptied, so
`DirAccess.remove_absolute` silently failed and left `manager/` non-empty. The
follow-up `rename_absolute(staged, manager)` then failed because the target still
existed — leaving a half-deleted, unrecoverable `manager/` and no editor restart.

**Fix (`1.2.3`):**

- `remove_directory_recursively` sets `include_hidden = true` (+ null guard).
  Regression test added.
- `install_staged_update` no longer deletes the live `manager/`. It renames it to
  `.brisklance_manager_backup`, renames the staged tree into place, and only then
  removes the backup. Either rename failing rolls back to the working install.
- `cleanup_stale_update_directories()` (run from the dock's `_ready()`) clears a
  leftover `.brisklance_manager_update` / `.brisklance_manager_backup`.

**Because the buggy swap runs from the *installed* version**, a `v1.2.2` (or
earlier) install cannot self-heal by updating — its own `install_staged_update`
is the broken one. Anyone on `<= 1.2.2` must **install `v1.2.3` manually once**
(extract `brisklance.zip` / `brisklance_manager.zip` over
`res://addons/brisklance`). Self-update works normally from `1.2.3` onward.

**Recovering the broken project:** delete the gutted
`res://addons/brisklance/manager` (including the leftover
`singletons/local_development_store/.gitignore`); if
`res://addons/brisklance/.brisklance_manager_update/manager` exists, rename it to
`.../manager`; otherwise re-extract the release zip. Restart the editor.

## Implementation status

All five phases are **implemented and verified** against Godot 4.7-stable
(`Godot_v4.7-stable_win64_console.exe`).

| Phase | Work | Status |
| --- | --- | --- |
| 1 | `BrisklanceSelfUpdater` version core + `tests/test_self_updater.gd` | Done · unit test green |
| 2 | Release metadata fetch + `is_update_available` | Done · live GitHub API verified |
| 3 | Download + stage + validate + swap (`apply_update`) | Done · `install_staged_update` swap + not-newer rejection verified |
| 4 | Dock notice UI + `BrisklanceInterface` wiring (`brisklance.gd` / `.tscn`) | Done · project imports clean, classes register |
| 5 | Publish workflow, version bump to `1.2.3`, README section | Done · workflow YAML valid |
| 6 | Hidden-file swap bug fix + backup/rollback swap | Done · regression test + live swap test green |

Files changed (committed on the branch):

- `addons/brisklance/manager/scripts/self_updater.gd` (+ `.uid`) — new
- `tests/test_self_updater.gd` (+ `.uid`) — new
- `addons/brisklance/manager/interface/brisklance/brisklance.gd`
- `addons/brisklance/manager/interface/brisklance/brisklance.tscn`
- `addons/brisklance/manager/plugin.cfg` (`1.1.0` → `1.2.3`)
- `addons/brisklance/manager/scripts/plugin_mirror.gd` (`remove_directory_recursively` hidden-file fix)
- `.github/workflows/publish.yml`
- `README.md`

### Verification performed

```
Godot_v4.7-stable_win64_console.exe --headless --import          # clean, BrisklanceSelfUpdater registers
Godot_v4.7-stable_win64_console.exe --headless --script res://tests/test_self_updater.gd
  -> 7/7 "ok:" then "All self-updater tests passed.", exit 0
```

Live-network scratch check (`SceneTree` + `HTTPRequest`):

```
latest: v1.2.0            # fetch_latest_release_metadata + fetch_latest_version
current: 1.2.0            # get_current_version reads manager/plugin.cfg (was 1.2.0 at test time; now 1.2.1)
update available: ''      # compare_versions: v1.2.0 is not > 1.2.0
manager zip url: ''       # resolve_manager_zip_url: existing v1.2.0 release has no
                          # brisklance_manager.zip asset -> printerr + "" (as designed)
```

Swap scratch check (`install_staged_update` against a hand-built zip rooted at
`manager/` with `version="9.9.9"`):

```
run 1 -> true            # extract to staging, validate newer, delete + rename
target version now: 9.9.9
run 2 -> false           # 9.9.9 is not newer than 9.9.9 -> abort, staging cleaned
```

## Remaining

- [x] **Merge `feat/self-update` into `main`.** (`main` @ `e284dd3`, pushed)

- [x] **Source repository is `brisketty/brisklance`** — `REPOSITORY_NAME` and the
  README release link corrected (`e284dd3`).

- [x] **Shipping version: `1.2.3`.** (`plugin.cfg` == release tag from here on.)
  - `v1.2.0` predates this feature (ships `plugin.cfg` `1.1.0`, no
    `brisklance_manager.zip`).
  - `v1.2.1` — published early, before the `brisketty/brisklance` fix; its
    `brisklance_manager.zip` has the wrong `REPOSITORY_NAME`. 0 downloads.
  - `v1.2.2` — published; correct repo, **but** ships the hidden-file swap bug
    above. Do not rely on updating *from* it (the swap runs from the installed
    version). Consider marking `v1.2.1` and `v1.2.2` as pre-releases / adding a
    "superseded — install v1.2.3 manually" note.
  - `v1.2.3` — first release that is both correct and safe.

- [ ] **(you) Publish `v1.2.3`** — push a `v1.2.3` tag on `main` (at or after the
  fix commit). `.github/workflows/publish.yml` triggers on `v*.*.*` and attaches
  `brisklance.zip` / `brisklance_manager.zip` (rooted at `manager/`) /
  `brisklance_module.zip`.

- [ ] **Install `v1.2.3` manually** in any project currently on `<= 1.2.2`
  (extract the release zip over `res://addons/brisklance`) — those installs
  cannot self-update past the bug.

- [ ] **End-to-end check from a `v1.2.3` install** — bump its `plugin.cfg` down a
  patch, reload, then:
  1. Open the editor → dock shows "Brisklance update available: `vX.Y.Z`" with
     an **Update** button (above the Github Setting row).
  2. Click **Update** → confirm. Console prints download progress,
     `Brisklance update downloaded.`, `Brisklance update installed. Restart the
     editor to finish.`
  3. Editor restarts. `manager/plugin.cfg` shows the new version;
     `res://addons/brisklance/.brisklance_manager_update/` is gone.
  4. `self/`, `plugins/`, `self/vendor/` unchanged.
  5. On restart the notice no longer appears.

## Notes / deviations from the spec

- **Dedicated `node_update_http_request`** node instead of reusing
  `node_http_request`, so the startup check never races the un-awaited
  `commit()` in `_ready()`. Same UX.
- New handlers follow `CLAUDE.md` (`handle_`-prefixed, connected in `_ready()`);
  the file's existing inline-lambda signal wiring is left as-is.
- `ConfirmUpdateWindow` carries `oversampling_override = 1.0` to match its
  sibling dialogs.
- The staging directory is `.brisklance_manager_update` (dot-prefixed) so Godot's
  filesystem scanner ignores it during an in-progress update.
