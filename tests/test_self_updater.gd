extends SceneTree

const SelfUpdater := preload("res://addons/brisklance/manager/scripts/self_updater.gd")
const PluginMirror := preload("res://addons/brisklance/manager/scripts/plugin_mirror.gd")


func _initialize() -> void:
	var failure_count := 0
	failure_count += expect("equal versions", SelfUpdater.compare_versions("1.2.0", "1.2.0"), 0)
	failure_count += expect("leading v ignored", SelfUpdater.compare_versions("v1.2.0", "1.2.0"), 0)
	failure_count += expect("missing patch is zero", SelfUpdater.compare_versions("1.2", "1.2.0"), 0)
	failure_count += expect("minor compared numerically", SelfUpdater.compare_versions("1.10.0", "1.2.0"), 1)
	failure_count += expect("older major", SelfUpdater.compare_versions("1.9.9", "2.0.0"), -1)
	failure_count += expect("newer patch", SelfUpdater.compare_versions("1.2.3", "1.2.2"), 1)
	failure_count += expect("older patch", SelfUpdater.compare_versions("1.2.1", "1.2.2"), -1)

	failure_count += expect("remove_directory_recursively deletes a tree with hidden files", int(remove_hidden_tree_left_behind()), 0)

	if failure_count > 0:
		push_error("%d self-updater test(s) failed." % failure_count)
		quit(1)
		return
	print("All self-updater tests passed.")
	quit(0)


# Returns true (i.e. a failure) if anything is left on disk after the recursive
# remove. Regression guard for the `.gitignore` bug that gutted `manager/`.
func remove_hidden_tree_left_behind() -> bool:
	var temp_directory := DirAccess.create_temp("brisklance_remove_test")
	var root_path := temp_directory.get_current_dir().path_join("tree")
	DirAccess.make_dir_recursive_absolute(root_path.path_join("nested"))
	FileAccess.open(root_path.path_join("visible.txt"), FileAccess.WRITE).store_string("x")
	FileAccess.open(root_path.path_join(".hidden"), FileAccess.WRITE).store_string("x")
	FileAccess.open(root_path.path_join("nested").path_join(".gitignore"), FileAccess.WRITE).store_string("*")

	PluginMirror.remove_directory_recursively(root_path)
	return DirAccess.dir_exists_absolute(root_path)


func expect(p_label: String, p_actual: int, p_expected: int) -> int:
	if p_actual == p_expected:
		print("  ok: %s" % p_label)
		return 0
	push_error("  FAIL: %s (expected %d, got %d)" % [p_label, p_expected, p_actual])
	return 1
