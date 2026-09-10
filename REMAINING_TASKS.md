# Brisklance Self-Update — Remaining Tasks

Design: [`ARCHITECTURE_SPEC.md`](ARCHITECTURE_SPEC.md).

## Implementation status (branch `feat/self-update`)

All five phases are **implemented and verified** against Godot 4.7-stable
(`Godot_v4.7-stable_win64_console.exe`).

| Phase | Work | Status |
| --- | --- | --- |
| 1 | `BrisklanceSelfUpdater` version core + `tests/test_self_updater.gd` | Done · unit test green |
| 2 | Release metadata fetch + `is_update_available` | Done · live GitHub API verified |
| 3 | Download + stage + validate + swap (`apply_update`) | Done · `install_staged_update` swap + not-newer rejection verified |
| 4 | Dock notice UI + `BrisklanceInterface` wiring (`brisklance.gd` / `.tscn`) | Done · project imports clean, classes register |
| 5 | Publish workflow, version bump to `1.2.0`, README section | Done · workflow YAML valid |

Files changed (committed on the branch):

- `addons/brisklance/manager/scripts/self_updater.gd` (+ `.uid`) — new
- `tests/test_self_updater.gd` (+ `.uid`) — new
- `addons/brisklance/manager/interface/brisklance/brisklance.gd`
- `addons/brisklance/manager/interface/brisklance/brisklance.tscn`
- `addons/brisklance/manager/plugin.cfg` (`1.1.0` → `1.2.0`)
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
current: 1.2.0            # get_current_version reads manager/plugin.cfg
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

- [ ] **Merge `feat/self-update` into `main`.**

- [ ] **Decide the shipping version.** A `v1.2.0` git tag / GitHub release
  *already exists* (it predates this feature and carries no
  `brisklance_manager.zip`). Because `manager/plugin.cfg` is now also `1.2.0`,
  existing installs will **not** see an update until a release tagged
  **`v1.2.1` or higher** is published with the new workflow. Either bump
  `manager/plugin.cfg` to `1.2.1` now, or simply cut the first real release as
  `v1.2.1`.

- [ ] **Publish a release** with the updated `.github/workflows/publish.yml` so
  a `brisklance_manager.zip` asset (entries rooted at `manager/`) exists.

- [ ] **End-to-end check after that release** — in a project on an older
  Brisklance:
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
