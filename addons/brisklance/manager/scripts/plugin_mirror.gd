@tool
extends RefCounted
class_name BrisklancePluginMirror

const ZIP_FILE_NAME := "brisklance_module.zip"
const PLUGINS_DIRECTORY_NAME := "plugins"
const VENDOR_DIRECTORY_NAME := "vendor"

var repository_name : String
var repository_tag : String
var dependencies : Array
var nested_dependencies : Array

static func remove_directory_recursively(p_directory_path: String) -> void:
	var directory := DirAccess.open(p_directory_path)
	
	for child_file_name in directory.get_files():
		var child_file_path := p_directory_path.path_join(child_file_name)
		DirAccess.remove_absolute(child_file_path)
	
	for child_directory_name in directory.get_directories():
		var child_directory_path := p_directory_path.path_join(child_directory_name)
		remove_directory_recursively(child_directory_path)
	
	DirAccess.remove_absolute(p_directory_path)

static func extract_zip_recursively_to_path(p_zip_file_path: String, p_target_directory_path: String) -> bool:
	var zip_reader := ZIPReader.new()
	var zip_reader_status := zip_reader.open(p_zip_file_path)
	if zip_reader_status != OK:
		printerr("Fail to unzip '{0}' (Error: {1}).".format([p_zip_file_path, error_string(zip_reader_status)]))
		return false
	DirAccess.make_dir_recursive_absolute(p_target_directory_path)
	var target_directory := DirAccess.open(p_target_directory_path)
	
	var file_subpaths = zip_reader.get_files()
	for file_subpath in file_subpaths:
		if file_subpath.ends_with("/"):
			target_directory.make_dir_recursive(file_subpath)
			continue
		var target_file_path := target_directory.get_current_dir().path_join(file_subpath)
		if target_file_path.ends_with(".zip"):
			var child_zip_file_name := target_file_path.get_file()
			var temp_directory := DirAccess.create_temp(str(hash(target_file_path)))
			var child_zip_file_path := temp_directory.get_current_dir().path_join(child_zip_file_name)
			var child_zip_file = FileAccess.open(child_zip_file_path, FileAccess.WRITE)
			var child_zip_file_content := zip_reader.read_file(file_subpath)
			child_zip_file.store_buffer(child_zip_file_content)
			var target_directory_path := target_file_path.get_basename()
			extract_zip_recursively_to_path(child_zip_file_path, target_directory_path)
			continue
		target_directory.make_dir_recursive(target_file_path.get_base_dir())
		var target_file = FileAccess.open(target_file_path, FileAccess.WRITE)
		var target_file_content = zip_reader.read_file(file_subpath)
		target_file.store_buffer(target_file_content)
	return false

static func create(p_repository_name: String, p_repository_tag: String) -> BrisklancePluginMirror:
	var result := BrisklancePluginMirror.new()
	result.repository_name = p_repository_name
	result.repository_tag = p_repository_tag
	return result

func make_legible_directory_name() -> String:
	var regex := RegEx.new()
	regex.compile("[^A-Za-z\\d_]")
	return regex.sub("{0}_{1}".format([repository_name, repository_tag]), "_", true)

func compute_download_mirror_request_headers() -> PackedStringArray:
	var headers := PackedStringArray([
		"Accept: application/octet-stream",
	])
	if not BrisklanceLocalDevelopmentStore.get_singleton().github_api_key.is_empty():
		headers.append("Authorization: Bearer {token}".format({
			"token": BrisklanceLocalDevelopmentStore.get_singleton().github_api_key
		}))
	return headers

func compute_download_mirror_request_url(p_http_request : HTTPRequest) -> String:
	var github_release_metadata_url := "https://api.github.com/repos/{repository_name}/releases/tags/{repository_tag}".format({
		"repository_name": repository_name,
		"repository_tag": repository_tag
	})
	
	var metadata_headers := PackedStringArray([
		"Accept: application/vnd.github+json",
	])
	if not BrisklanceLocalDevelopmentStore.get_singleton().github_api_key.is_empty():
		metadata_headers.append("Authorization: Bearer {token}".format({
			"token": BrisklanceLocalDevelopmentStore.get_singleton().github_api_key
		}))
	p_http_request.download_file = ""
	var request_status := p_http_request.request(github_release_metadata_url, metadata_headers, HTTPClient.METHOD_GET)
	if request_status != OK:
		printerr("Fail to get metadata of '{0}' (Error: {1}).".format([repository_name, error_string(request_status)]))
		return ""
	
	var download_request_result := await p_http_request.request_completed as Array
	var download_request_result_result := download_request_result[0] as int
	if download_request_result_result != HTTPRequest.Result.RESULT_SUCCESS:
		printerr(
			"Fail to get metadata '{0}' (Request Result: {1})."
			.format([repository_name, download_request_result_result]),
		)
		return ""
	var download_response_code := download_request_result[1] as int
	if download_response_code != 200:
		printerr(
			"Fail to get metadata '{0}' (Response Code: {1})."
			.format([repository_name, download_response_code]),
		)
		return ""
	var download_response_body := download_request_result[3] as PackedByteArray
	var metadata = JSON.parse_string(download_response_body.get_string_from_utf8())
	
	for asset in metadata["assets"]:
		if asset["name"] != ZIP_FILE_NAME: continue
		return asset["url"]
	
	return ""

func get_plugin_directory_path() -> String:
	return (
		BrisklanceEditorPlugin
		.BRISKLANCE_DIRECTORY_PATH
		.path_join(PLUGINS_DIRECTORY_NAME)
		.path_join(make_legible_directory_name())
	)

func get_vendored_plugin_directory_path() -> String:
	return (
		BrisklanceEditorPlugin
		.BRISKLANCE_DIRECTORY_PATH
		.path_join(BrisklancePluginReference.SELF_ADDON_DIRECTORY_NAME)
		.path_join(VENDOR_DIRECTORY_NAME)
		.path_join(make_legible_directory_name())
	)

func vendor_self() -> void:
	DirAccess.rename_absolute(get_plugin_directory_path(), get_vendored_plugin_directory_path())

func purge_self() -> void:
	var plugin_directory_path := get_plugin_directory_path()
	var plugin_reference := BrisklancePluginReference.find(plugin_directory_path)
	plugin_reference.enable(false)
	remove_directory_recursively(plugin_directory_path)

func force_purge_all() -> void:
	for mirror : BrisklancePluginMirror in dependencies:
		mirror.force_purge_all()
	purge_self()

func purge_all() -> void:
	var dependant_mirrors := BrisklanceCentralDatabase.get_singleton().find_dependant_mirrors(self)
	if len(dependant_mirrors) > 0: return
	for mirror : BrisklancePluginMirror in dependencies:
		mirror.purge_all()
	purge_self()

func add_self_to_dependency_dictionary(p_dictionary: Dictionary) -> void:
	p_dictionary[repository_name] = repository_tag

func retreive_self(p_http_request: HTTPRequest) -> BrisklancePluginReference:
	var plugin_directory_path := get_plugin_directory_path()
	var plugin_reference := BrisklancePluginReference.find(plugin_directory_path)
	if plugin_reference: 
		await p_http_request.get_tree().process_frame
		plugin_reference.enable()
		return plugin_reference
	var mirror_url := await compute_download_mirror_request_url(p_http_request)
	if mirror_url.is_empty(): return null
	var temp_directory := DirAccess.create_temp(str(hash(repository_name)))
	var zip_file_path := temp_directory.get_current_dir().path_join(ZIP_FILE_NAME)
	p_http_request.download_file = zip_file_path
	var headers := compute_download_mirror_request_headers()
	var request_status := p_http_request.request(mirror_url, headers, HTTPClient.METHOD_GET)
	if request_status != OK:
		printerr("Fail to download '{0}' from '{1}' (Error: {2}).".format([repository_name, mirror_url, error_string(request_status)]))
		return null
	print("Downloading '{0}'.".format([repository_name]))
	DownloadReporter.start_report(p_http_request)
	var download_request_result := await p_http_request.request_completed as Array
	var download_response_code := download_request_result[1] as int
	if download_response_code != 200:
		printerr(
			"Fail to download '{0}' from '{1}' (Response Code: {2})."
			.format([repository_name, mirror_url, download_response_code]),
		)
		return null
	print("'{0}' downloaded.".format([repository_name]))
	
	print("Unzipping '{0}'.".format([repository_name]))
	extract_zip_recursively_to_path(zip_file_path, plugin_directory_path)
	print("'{0}' unzipped.".format([repository_name]))
	
	plugin_reference = BrisklancePluginReference.find(plugin_directory_path)
	if not plugin_reference: 
		purge_self()
		return null
	await p_http_request.get_tree().process_frame
	plugin_reference.enable()
	return plugin_reference

func install(
	p_http_request: HTTPRequest,
	p_already_installed_dependencies := BrisklanceCentralDatabase.get_singleton().plugin_mirrors.duplicate()
) -> Array:
	dependencies.clear()
	nested_dependencies.clear()
	var plugin_reference := await retreive_self(p_http_request)
	var plugin_mirror_repository_names := BrisklanceCentralDatabase.get_singleton().get_plugin_mirror_repository_names()
	for dependency_repository_name : String in plugin_reference.dependency_dictionary.keys():
		var dependency_repository_tag := plugin_reference.dependency_dictionary[dependency_repository_name] as String
		var dependency := BrisklancePluginMirror.create(dependency_repository_name, dependency_repository_tag)
		if dependency_repository_name in plugin_mirror_repository_names:
			dependencies.append(dependency)
			nested_dependencies.append(dependency)
			continue
		for already_installed_dependency : BrisklancePluginMirror in p_already_installed_dependencies:
			if dependency_repository_name == already_installed_dependency.repository_name:
				if not dependency_repository_name in plugin_mirror_repository_names:
					BrisklanceCentralDatabase.get_singleton().plugin_mirrors.append(already_installed_dependency)
		nested_dependencies.append_array(await dependency.install(p_http_request, p_already_installed_dependencies))
		p_already_installed_dependencies.append(dependency)
		dependencies.append(dependency)
		nested_dependencies.append(dependency)
	return nested_dependencies
