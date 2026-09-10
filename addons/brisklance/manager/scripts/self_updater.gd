@tool
extends RefCounted
class_name BrisklanceSelfUpdater

const REPOSITORY_NAME := "RechieKho/brisklance"
const MANAGER_ZIP_FILE_NAME := "brisklance_manager.zip"
const MANAGER_DIRECTORY_PATH := "res://addons/brisklance/manager"
const STAGING_DIRECTORY_PATH := "res://addons/brisklance/.brisklance_manager_update"
const CONFIGURATION_FILE_NAME := "plugin.cfg"
const PLUGIN_SECTION_KEY := &"plugin"
const VERSION_KEY := &"version"
const LATEST_RELEASE_URL_TEMPLATE := "https://api.github.com/repos/{repository_name}/releases/latest"


static func normalize_version(p_version: String) -> PackedInt32Array:
	var trimmed := p_version.strip_edges()
	if trimmed.begins_with("v") or trimmed.begins_with("V"):
		trimmed = trimmed.substr(1)
	var result := PackedInt32Array([0, 0, 0])
	var segments := trimmed.split(".", false)
	for index in mini(segments.size(), 3):
		result[index] = int(segments[index])
	return result


static func compare_versions(p_a: String, p_b: String) -> int:
	var a := normalize_version(p_a)
	var b := normalize_version(p_b)
	for index in 3:
		if a[index] > b[index]: return 1
		if a[index] < b[index]: return -1
	return 0


func get_current_version() -> String:
	var configuration := ConfigFile.new()
	var status := configuration.load(MANAGER_DIRECTORY_PATH.path_join(CONFIGURATION_FILE_NAME))
	if status != OK:
		printerr("Fail to read the installed Brisklance version (Error: {0}).".format([error_string(status)]))
		return ""
	return configuration.get_value(PLUGIN_SECTION_KEY, VERSION_KEY, "") as String


func compute_request_headers(p_accept: String) -> PackedStringArray:
	var headers := PackedStringArray(["Accept: " + p_accept])
	var api_key := BrisklanceLocalDevelopmentStore.get_singleton().github_api_key
	if not api_key.is_empty():
		headers.append("Authorization: Bearer " + api_key)
	return headers


func fetch_latest_release_metadata(p_http_request: HTTPRequest) -> Dictionary:
	var url := LATEST_RELEASE_URL_TEMPLATE.format({"repository_name": REPOSITORY_NAME})
	p_http_request.download_file = ""
	var request_status := p_http_request.request(url, compute_request_headers("application/vnd.github+json"), HTTPClient.METHOD_GET)
	if request_status != OK:
		printerr("Fail to check for Brisklance update (Error: {0}).".format([error_string(request_status)]))
		return {}
	var result := await p_http_request.request_completed as Array
	var result_code := result[0] as int
	if result_code != HTTPRequest.Result.RESULT_SUCCESS:
		printerr("Fail to check for Brisklance update (Request Result: {0}).".format([result_code]))
		return {}
	var response_code := result[1] as int
	if response_code != 200:
		printerr("Fail to check for Brisklance update (Response Code: {0}).".format([response_code]))
		return {}
	var body := result[3] as PackedByteArray
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		printerr("Fail to parse Brisklance release metadata.")
		return {}
	return parsed as Dictionary


func fetch_latest_version(p_http_request: HTTPRequest) -> String:
	var metadata := await fetch_latest_release_metadata(p_http_request)
	return metadata.get("tag_name", "") as String


func is_update_available(p_http_request: HTTPRequest) -> String:
	var latest_version := await fetch_latest_version(p_http_request)
	if latest_version.is_empty(): return ""
	if compare_versions(latest_version, get_current_version()) > 0:
		return latest_version
	return ""


func resolve_manager_zip_url(p_http_request: HTTPRequest) -> String:
	var metadata := await fetch_latest_release_metadata(p_http_request)
	if metadata.is_empty(): return ""
	for asset in metadata.get("assets", []):
		if (asset as Dictionary).get("name", "") == MANAGER_ZIP_FILE_NAME:
			return (asset as Dictionary).get("url", "") as String
	printerr("Latest Brisklance release has no '{0}' asset.".format([MANAGER_ZIP_FILE_NAME]))
	return ""


func install_staged_update(p_zip_file_path: String) -> bool:
	if DirAccess.dir_exists_absolute(STAGING_DIRECTORY_PATH):
		BrisklancePluginMirror.remove_directory_recursively(STAGING_DIRECTORY_PATH)
	BrisklancePluginMirror.extract_zip_recursively_to_path(p_zip_file_path, STAGING_DIRECTORY_PATH)

	var staged_manager_path := STAGING_DIRECTORY_PATH.path_join("manager")
	var staged_configuration_path := staged_manager_path.path_join(CONFIGURATION_FILE_NAME)
	if not FileAccess.file_exists(staged_configuration_path):
		printerr("Brisklance update archive is malformed; aborting.")
		BrisklancePluginMirror.remove_directory_recursively(STAGING_DIRECTORY_PATH)
		return false

	var staged_configuration := ConfigFile.new()
	staged_configuration.load(staged_configuration_path)
	var staged_version := staged_configuration.get_value(PLUGIN_SECTION_KEY, VERSION_KEY, "") as String
	if compare_versions(staged_version, get_current_version()) <= 0:
		printerr("Brisklance update ('{0}') is not newer than the installed version ('{1}'); aborting.".format([staged_version, get_current_version()]))
		BrisklancePluginMirror.remove_directory_recursively(STAGING_DIRECTORY_PATH)
		return false

	BrisklancePluginMirror.remove_directory_recursively(MANAGER_DIRECTORY_PATH)
	var rename_status := DirAccess.rename_absolute(staged_manager_path, MANAGER_DIRECTORY_PATH)
	if rename_status != OK:
		printerr("Fail to install Brisklance update (Error: {0}). Reinstall 'brisklance.zip' manually to recover.".format([error_string(rename_status)]))
		return false
	BrisklancePluginMirror.remove_directory_recursively(STAGING_DIRECTORY_PATH)
	print("Brisklance update installed. Restart the editor to finish.")
	return true


func apply_update(p_http_request: HTTPRequest) -> bool:
	var mirror_url := await resolve_manager_zip_url(p_http_request)
	if mirror_url.is_empty(): return false

	var temp_directory := DirAccess.create_temp("brisklance_self_update")
	var zip_file_path := temp_directory.get_current_dir().path_join(MANAGER_ZIP_FILE_NAME)
	p_http_request.download_file = zip_file_path
	var request_status := p_http_request.request(mirror_url, compute_request_headers("application/octet-stream"), HTTPClient.METHOD_GET)
	if request_status != OK:
		printerr("Fail to download Brisklance update (Error: {0}).".format([error_string(request_status)]))
		return false
	print("Downloading Brisklance update.")
	DownloadReporter.start_report(p_http_request)
	var download_result := await p_http_request.request_completed as Array
	var download_response_code := download_result[1] as int
	if download_response_code != 200:
		printerr("Fail to download Brisklance update (Response Code: {0}).".format([download_response_code]))
		return false
	print("Brisklance update downloaded.")

	return install_staged_update(zip_file_path)
