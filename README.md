# Brisklance

Brisklance is a simple addon manager suite for Godot, inspired from package manager such as [NPM](https://www.npmjs.com).
It is to address the issue of Godot's Asset Store not supporting automatic dependency installation.
It utilize Github's release as host to host archives.

## Setting up

To setup Brisklance, you will need to download the `brisklance.zip` from the [release page](https://github.com/brisketty/brisklance/releases).
Then, extract the files and place it under `res://addons/brisklance` directory as it matches the directories shown in [Directories Description](#directories-descriptions)

However, if you are attempting to create plugins that could be installed via Brisklance, it would be wise to utilize this repository as a template.
This is because this template already set up the necessary Github workflow to publish your plugin in the format acceptable to brisklance.

## Updating Brisklance

Brisklance can update itself.
On editor start it checks its own repository for the latest release, and clicking **Refresh** in the dock re-checks.
When a newer version exists, a notice with an **Update** button appears above the Github Setting row in the Brisklance dock.
Clicking **Update** downloads the new manager, replaces `res://addons/brisklance/manager` in place, and restarts the editor.
Your own plugin under `res://addons/brisklance/self`, your installed plugins, and your vendored plugins are left untouched.

Setting a GitHub API key in the dock's Github Setting raises the API rate limit but is not required to update from a public repository.

## Export addons to Brisklance

To make your addons accessible by Brisklance, the only requirement is to upload a `brisklance_module.zip` file as asset to the release of your Github repository.
This is usually automated with Github workflow. Once you set up the file, Brisklance will find the file, download it and extract the content to `res://addons/brisklance/plugins` directory.
The `brisklance_module.zip` is packaged from `res://addons/brisklance/self`, so any plugin you have vendored under `res://addons/brisklance/self/vendor` ships with your module as a frozen dependency.

## Directories Descriptions

Here discusses the crucial directory and its description to further explain on how Brisklance works.

| Directory                         | Description                                                                                                                                                        |
| --------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `res://addons/brisklance/manager` | Here lies all the script that manages download and installations.                                                                                                  |
| `res://addons/brisklance/plugins` | Here lies all the downloaded plugins. The installed plugins are excluded from versioning system as it is automatically installed during start up and installation. |
| `res://addons/brisklance/self`    | Here lies your own plugin. The installed plugins will be registered to the plugin as dependencies. This directory is packaged into `brisklance_module.zip`.          |
| `res://addons/brisklance/self/vendor` | Here lies all the vendored plugins. They are kept under versioning as they are not managed by Brisklance, and are packaged into `brisklance_module.zip` as frozen dependencies of your plugin. |

## Dependency Resolution

First Come, First Serve manual dependency management is employed due to the nature of Godot's architecture.
Godot's module cannot be local; each module is global.
Thus, we cannot install a dependency that is local for a particular module like Node.js.
As a result, the maintainer must be diligent in selecting the version of dependency that satisfies all plugins.
Any conflicting dependency would be resolved by taking the existing plugin version (first come, first served basis).

Let's assume a scenario in which plugin Foo and plugin Bar both depend on plugin Car.
Then, the version of the car will be installed depending on which dependent plugin is installed first.
For this case, if Foo is installed first, then Foo's Car is installed.
If the version is not suitable, the user will need to install the correct version of the car manually.
