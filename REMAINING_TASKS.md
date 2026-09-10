# Brisklance Self-Update — Remaining Tasks

Design: [`ARCHITECTURE_SPEC.md`](ARCHITECTURE_SPEC.md).

## Implementation status (branch `feat/self-update`)

All five phases are **code-complete**. What is left is verification that needs a
Godot editor, which is not available in the environment where the code was
written.

| Phase | Work | Status |
| --- | --- | --- |
| 1 | `BrisklanceSelfUpdater` version core + `tests/test_self_updater.gd` | Written |
| 2 | Release metadata fetch + `is_update_available` | Written |
| 3 | Download + stage + validate + swap (`apply_update`) | Written |
| 4 | Dock notice UI + `BrisklanceInterface` wiring (`brisklance.gd` / `.tscn`) | Written |
| 5 | Publish workflow, version bump to `1.2.0`, README section | Written |

Files touched:

- `addons/brisklance/manager/scripts/self_updater.gd` (new)
- `tests/test_self_updater.gd` (new)
- `addons/brisklance/manager/interface/brisklance/brisklance.gd`
- `addons/brisklance/manager/interface/brisklance/brisklance.tscn`
- `addons/brisklance/manager/plugin.cfg` (`1.1.0` → `1.2.0`)
- `.github/workflows/publish.yml`
- `README.md`

## Remaining — needs a Godot 4.6 editor / CLI

- [ ] **Run the unit test.** From the project root:
  ```bash
  godot --headless --import
  godot --headless --script res://tests/test_self_updater.gd
  ```
  Expect seven `ok:` lines then `All self-updater tests passed.`, exit 0.
  (If class-name resolution fails, run `godot --headless --editor --quit` once
  to build caches, then retry.)

- [ ] **Commit the generated `.gd.uid` files.** Godot writes
  `self_updater.gd.uid` and `test_self_updater.gd.uid` during `--import`; add
  them to the branch.

- [ ] **Open the project in the editor** and confirm:
  - No parse/Output errors for `brisklance.gd` / `brisklance.tscn` /
    `self_updater.gd`.
  - The Brisklance dock renders with all existing controls intact.
  - The update-notice row is hidden (no release newer than `1.2.0` exists yet).
  - Clicking **Refresh** raises no errors.

- [ ] **Manually verify `get_current_version()`** — temporarily print
  `BrisklanceSelfUpdater.new().get_current_version()`; expect `1.2.0`.

- [ ] **Manually verify the network path** — throwaway scene with a `Node` +
  child `HTTPRequest`:
  ```gdscript
  extends Node
  @export var node_http_request: HTTPRequest
  func _ready() -> void:
  	var updater := BrisklanceSelfUpdater.new()
  	print("latest: ", await updater.fetch_latest_version(node_http_request))
  	print("current: ", updater.get_current_version())
  	print("update available: '", await updater.is_update_available(node_http_request), "'")
  	get_tree().quit()
  ```
  Expect the newest `RechieKho/brisklance` tag, `current: 1.2.0`, and (until a
  `>1.2.0` release is published) `update available: ''`. Delete the scene after.

- [ ] **Manually verify `install_staged_update`** against a hand-made archive —
  see the detailed procedure in git history / the spec (point
  `MANAGER_DIRECTORY_PATH` at a throwaway `manager_swap_test/`, feed a zip whose
  root is `manager/` with `version="9.9.9"`, confirm the swap and the
  not-newer rejection, then revert the constant).

- [ ] **Verify the release archive layout** once CI runs (or locally with
  `zip`): `zip -r brisklance_manager.zip manager` from `addons/brisklance` must
  produce entries rooted at `manager/` (e.g. `manager/plugin.cfg`).

## Integration verification — after a `>= 1.2.0` release carrying `brisklance_manager.zip`

1. In a project on an older Brisklance, open the editor → dock shows
   "Brisklance update available: `vX.Y.Z`" with an **Update** button.
2. Click **Update** → confirm. Console prints download progress,
   `Brisklance update downloaded.`, `Brisklance update installed. Restart the
   editor to finish.`
3. Editor restarts. `manager/plugin.cfg` shows the new version;
   `.brisklance_manager_update/` is gone.
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
