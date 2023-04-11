# fueled plugin

[![fastlane Plugin Badge](https://rawcdn.githack.com/fastlane/fastlane/master/fastlane/assets/plugin-badge.svg)](https://rubygems.org/gems/fastlane-plugin-fueled)

## Getting Started

This project is a [_fastlane_](https://github.com/fastlane/fastlane) plugin. To get started
with `fastlane-plugin-fueled`, add it to your project by adding:

```
gem 'fastlane-plugin-fueled', git: "https://github.com/Fueled/fastlane-plugin-fueled"
```

## About Fueled Fastlane plugin

This plugin embeds build steps that we use in our CI/CD pipeline at Fueled. It has steps that could
be reused easily by any project, on any platform (ios/android), and some others that are really
Fueled specific.

## Available Actions

* Common
    - [create_github_release](#user-content-create_github_release)
    - [generate_changelog](#user-content-generate_changelog)
    - [is_build_necessary](#user-content-is_build_necessary)
    - [move_linear_tickets](#user-content-move_linear_tickets)
    - [use_git_credential_store](#user-content-use_git_credential_store)
    - [tag](#user-content-tag)
    - [upload_to_app_center](#user-content-upload_to_app_center)
* iOS
    - [define_versions_ios](#user-content-define_versions_ios)
    - [import_base_64_certificates](#user-content-import_base64_certificates)
    - [generate_secrets_ios](#generate_secrets_ios)
    - [install_profiles](#user-content-install_profiles)
    - [install_wwdr_certificate](#user-content-install_wwdr_certificate)
    - [set_app_versions_plist_ios](#user-content-set_app_versions_plist_ios)
    - [set_app_versions_xcodeproj_ios](#user-content-set_app_versions_xcodeproj_ios)
    - [check_code_coverage_ios](#user-content-check_code_coverage_ios)
    - [upload_to_app_store](#user-content-upload_to_app_store)
* Android
    - [define_versions_android](#user-content-define_versions_android)
    - [set_app_versions_android](#user-content-set_app_versions_android)
* Flutter
    - [define_versions_flutter](#user-content-define_versions_flutter)
    - [set_app_versions_flutter](#user-content-set_app_versions_flutter)
    - [formatting_checks_flutter](#user-content-formatting_checks_flutter)
    - [generate_files_flutter](#user-content-generate_files_flutter)
    - [ci_checks_flutter](#user-content-ci_checks_flutter)
* React Native
    - [define_versions_react_native](#user-content-define_versions_react_native)

## Example

We use `dotenv` files to specify most of the values being used by the actions. The advantage is that
you can have several `dotenv` files, depending on the build target, or even the audience you intend
to deliver the build to.

Note that sensitive data should be hosted outside of the dotenv file, and passed at build time.

Here is an example of a `dotenv` file for the iOS platform :

```
# General
GITHUB_TOKEN=$GITHUB_TOKEN
REPOSITORY_NAME=$REPOSITORY_NAME
WORKSPACE=App.xcworkspace
PROJECT_PATH=App.xcodeproj
BUILD_CONFIGURATION=Debug
SCHEME=SchemeToBuild
EXPORT_METHOD=enterprise
VERSION_BUMP_TYPE=minor
# Signing
P12_PASSWORD=$P12_PASSWORD
BASE64_CERTIFICATE_INPUT=A_BASE64_ENCODED_P12_FILE
# Appcenter
AC_API_TOKEN=$APPCENTER_API_TOKEN
AC_OWNER_NAME=OwnerName
AC_APP_NAME=AppName
AC_DISTRIBUTION_GROUPS="Alpha Release,Collaborators"
AC_NOTIFY_TESTERS=true
# Testflight
TESTFLIGHT_USERNAME=$APPLE_ID
TESTFLIGHT_APP_SPECIFIC_PASSWORD=$APPLE_APP_PASSWORD
```

Here is a sample iOS Fastfile leveraging this plugin.

```
fastlane_version "2.197.0"
opt_out_usage

platform :ios do
  keychain_name = "temp"
  keychain_password = "foo"

  lane :app_center do
    pre_build
    define_versions_ios
    set_app_versions_xcodeproj_ios
    build
    upload_to_app_center
    tag
    create_github_release
    post_build
  end

  lane :app_store do
    pre_build
    define_versions_ios
    set_app_versions_xcodeproj_ios
    build
    upload_to_testflight
    tag
    create_github_release
    post_build
  end

  lane :tests do
    run_tests(
      workspace: ENV['WORKSPACE'],
      devices: ["iPhone 13",],
      scheme: ENV['SCHEME']
    )
  end

  private_lane :pre_build do
    create_keychain(
      name: keychain_name,
      default_keychain: true,
      password: keychain_password,
      unlock: true,
      timeout: 0
    )
    install_wwdr_certificate(
      keychain_name: keychain_name,
      keychain_password: keychain_password
    )
    import_base64_certificates(
      keychain_name: keychain_name,
      keychain_password: keychain_password
    )
    install_profiles
    generate_changelog
  end

  private_lane :post_build do
    delete_keychain(
      name: keychain_name
    )
  end

  private_lane :build do
    build_ios_app(
      workspace: ENV['WORKSPACE'],
      configuration: ENV['BUILD_CONFIGURATION'],
      scheme: ENV['SCHEME'],
      silent: true,
      clean: false,
      disable_xcpretty: false,
      export_options: {
        method: ENV['EXPORT_METHOD']
      }
    )
  end
end
```

## Parameters

#### `create_github_release`

Creates a Github Release for the given tag, and changelog

Only create a GH release if triggered on CI

| Key & Env Var | Description | Default Value
|-----------------|--------------------|---|
| `short_version_string` <br/> NONE | The short version string (eg: 0.2.6) | `Actions.lane_context[SharedValues::SHORT_VERSION_STRING]` | |
| `build_number` <br/> NONE | The build number (eg: 625) | `Actions.lane_context[SharedValues::FUELED_BUILD_NUMBER]` |
| `build_config` <br/> `BUILD_CONFIGURATION` | The build configuration (eg: Debug) | `Debug` |
| `repository_name` <br/> `REPOSITORY_NAME` | The repository name (eg: fueled/zenni-ios) | |
| `github_token` <br/> `GITHUB_TOKEN` | A Github Token to interact with the GH APIs | |
| `upload_assets` <br/> `UPLOAD_ASSETS` | Assets to be included with the release | `Helper::FueledHelper.default_output_file` |

#### `define_versions_android`

Sets the new build version name and build number as shared values. In case
the `DISABLE_VERSION_LIMIT` environment variable is not set we cap the version bumping limit to
1.x.x.

This action sets shared values for build number (`SharedValues::FUELED_BUILD_NUMBER`) and build
version name (`SharedValues::SHORT_VERSION_STRING`). Your Fastfile should use these values in a next
step to set them to the project accordingly (set_app_versions_android or set_app_versions_android).

| Key & Env Var                                         | Description | Default Value
|-------------------------------------------------------|--------------------|---------------|
| `bump_type` <br/> `VERSION_BUMP_TYPE`                 | The version to bump (`major`, `minor`, `patch`, or `none`) | `none`        |
| `disable_version_limit` <br/> `DISABLE_VERSION_LIMIT` | When true it skips the version limiting currently set for `1.x.x`+ versions | `false`       |
| `build_type` <br/> `BUILD_CONFIGURATION`              | This is used to retrieve tag belonging to this build_type | `none`

#### `define_versions_flutter`

Sets the new version (--build-name) and build number (--build-number) as shared values, without
setting them in the pubspec.

This action sets shared values for *build-number* (`SharedValues::FUELED_BUILD_NUMBER`) and *
build-name*(`SharedValues::SHORT_VERSION_STRING`). Your Fastfile should use these values in a next
step to set them to the project accordingly (`set_app_versions_flutter`). In case
the `DISABLE_VERSION_LIMIT` environment variable is not set we cap the version bumping limit to
1.x.x.

| Key & Env Var | Description | Default Value
|-----------------|--------------------|---|
| `bump_type` <br/> `VERSION_BUMP_TYPE` | The version to bump (`major`, `minor`, `patch`, or `none`) | `none`
| `disable_version_limit` <br/> `DISABLE_VERSION_LIMIT` | When true it skips the version limiting currently set for `1.x.x`+ versions | `false`       |
| `build_type` <br/> `BUILD_CONFIGURATION` | This is used to retrieve tag belonging to this build_type | `none`

#### `define_versions_ios`

Sets the new CFBundleVersion and CFBundleShortVersion as shared values, without setting them in the
project. In case the `` environment variable is not set we cap the version bumping limit to 1.x.x.

This action sets shared values for `CFBundleVersion` (`SharedValues::FUELED_BUILD_NUMBER`)
and `CFBundleShortVersion` (`SharedValues::SHORT_VERSION_STRING`).

Your Fastfile should use these values in a next step to set them to the project
accordingly (`set_app_versions_xcodeproj_ios` or `set_app_versions_plist_ios`).

| Key & Env Var | Description | Default Value
|-----------------|--------------------|---|
| `project_path` <br/> `PROJECT_PATH` | The path to the project .xcodeproj |  |
| `bump_type` <br/> `VERSION_BUMP_TYPE` | The version to bump (`major`, `minor`, `patch`, or `none`) | `none`
| `disable_version_limit` <br/> `DISABLE_VERSION_LIMIT` | When true it skips the version limiting currently set for `1.x.x`+ versions | `false`       |
| `build_type` <br/> `BUILD_CONFIGURATION` | This is used to retrieve tag belonging to this build_type | `none`

#### `define_versions_react_native`

Sets the new version and build number as shared values, without setting them in the package.json
file or the projects themselves.

This action sets shared values for build number (`SharedValues::FUELED_BUILD_NUMBER`) and version
number (`SharedValues::SHORT_VERSION_STRING`). Your Fastfile should use these values in a next step
to set them to the project accordingly (`set_app_versions_plist_ios` and `set_app_versions_android`)
.

| Key & Env Var | Description | Default Value
|-----------------|--------------------|---|
| `bump_type` <br/> `VERSION_BUMP_TYPE` | The version to bump (`major`, `minor`, `patch`, or `none`) | `none`
| `disable_version_limit` <br/> `DISABLE_VERSION_LIMIT` | When true it skips the version limiting currently set for `1.x.x`+ versions | `false`       |
| `build_type` <br/> `BUILD_CONFIGURATION` | This is used to retrieve tag belonging to this build_type | `none`

#### `generate_changelog`

Generate a changelog.

Changelog is made of commits between now, and the previous tag using the same build configuration

| Key & Env Var | Description                                                     | Default Value
|-----------------|-----------------------------------------------------------------|---|
| `build_config` <br/> `BUILD_CONFIGURATION` | The build configuration (eg: Debug)                             | `Debug` |
| `ticket_base_url` <br/> `TICKET_BASE_URL` | The base url for tickets (eg. https://linear.app/fueled/issue/) | `https://linear.app/fueled/issue/` |

#### `generate_secrets_ios`

Generate [ArkanaKeys](https://github.com/rogerluan/arkana) Package containing project secrets.

The generated package contains secrets based on the provided template and environment file. 

| Key & Env Var | Description                                                     | Default Value
|-----------------|-----------------------------------------------------------------|---|
| `template_file` <br/> `ARKANA_TEMPLATE_FILE` | Name/Path of Arkana template file                             | `.arkana.yml` |
| `environment_file` <br/> `ARKANA_ENVIRONMENT_FILE` | Name/Path of Arkana environment file | `.env.arkana_ci` |

#### `import_base64_certificates`

Import p12 certificates encoded as base64

| Key & Env Var | Description | Default Value
|-----------------|--------------------|---|
| `base64_input` <br> `BASE64_CERTIFICATE_INPUT` | The base64 string describing the p12 file | |
| `p12_password` <br/> `P12_PASSWORD` | The decrypted p12 password | |
| `keychain_name` <br/> `KEYCHAIN_NAME` | The keychain name to install the certificates to | `login` |
| `keychain_password` <br/> `KEYCHAIN_PASSWORD` | The keychain password to install the certificates to | |

#### `install_profiles`

Install provisioning profiles from the given folder

| Key & Env Var | Description | Default Value
|-----------------|--------------------|---|
| `folder` <br/> `PROFILES_FOLDER` | The folder where the provisioning profiles are stored | `fastlane/profiles` |

#### `install_wwdr_certificate`

Pulls and adds the WWDR Apple Certificate to the given keychain

| Key & Env Var | Description | Default Value
|-----------------|--------------------|---|
| `keychain_name` <br/> `KEYCHAIN_NAME` | The keychain name to install the certificates to | `login` |
| `keychain_password` <br/> `KEYCHAIN_PASSWORD` | The keychain password to install the certificates to | |

### `is_build_necessary`

Defines if the build is necessary by looking up changes since the last tag for the same build
configuration.<br/>
If the number of revisions between the last tag matching the given build configuration, and HEAD is
higher than 0, the action will return true.

| Key & Env Var | Description | Default Value
|-----------------|--------------------|---|
| `build_config` <br/> `BUILD_CONFIGURATION` | The build configuration (eg: Debug) | |
| `force_necessary` <br/> `FORCE_NECESSARY` | If the lane should continue, regardless of changes being made or not | `false` |

#### `move_linear_tickets`

Automatically moves Linear tickets form a state to another one, for a specific team and a set of
labels (comma separated). If any of the parameter is not provided, the action will emit a warning
and be skipped.

| Key & Env Var | Description | Default Value
|-----------------|--------------------|---|
| `linear_api_key` <br/> `FUELED_LINEAR_API_KEY` | The Linear API key | |
| `linear_team_id` <br/> `FUELED_LINEAR_TEAM_ID` | The Linear Team ID | |
| `from_state` <br/> `FUELED_LINEAR_FROM_STATE` | The state ID to issues should be moved from | |
| `to_state` <br/> `FUELED_LINEAR_TO_STATE` | The state ID to issues should be moved to | |
| `labels` <br/> `FUELED_LINEAR_LABELS` | The label IDs of the tickets to filter with (comma separated for multiple) | |

#### `set_app_versions_android`

Update the Android app version using the passed parameters.

| Key & Env Var | Description | Default Value
|-----------------|--------------------|---|
| `short_version_string` | The short version string (eg: 0.2.6) | `SharedValues::SHORT_VERSION_STRING` |
| `build_number` <br/> `BUILD_NUMBER` | The build number (eg: 625) | `SharedValues::FUELED_BUILD_NUMBER` |

#### `set_app_versions_flutter`

Update the pubspec.yaml file with the passed short version, build number, and build configuration.

| Key & Env Var | Description | Default Value
|-----------------|--------------------|---|
| `build_config` <br/> `BUILD_CONFIGURATION` | The build configuration (eg: Debug) | |
| `short_version_string` | The short version string (eg: 0.2.6) | `SharedValues::SHORT_VERSION_STRING` |
| `build_number` | The build number (eg: 625) | `SharedValues::FUELED_BUILD_NUMBER` |

#### `set_app_versions_plist_ios`

Update the iOS app versions in the plist file (`CFBundleVersion` & `CFShortBundleVersion`) using the
passed parameters. Note that an export method of `app-store` will trim the `CFBundleVersion` to only
contain the build number.

| Key & Env Var | Description | Default Value
|-----------------|--------------------|---|
| `project_path` <br/> `PROJECT_PATH` | The path to the project .xcodeproj |  |
| `build_config` <br/> `BUILD_CONFIGURATION` | The build configuration (eg: Debug) | |
| `short_version_string` | The short version string (eg: 0.2.6) | `SharedValues::SHORT_VERSION_STRING` |
| `build_number` <br/> `BUILD_NUMBER` | The build number (eg: 625) | `SharedValues::FUELED_BUILD_NUMBER` |
| `export_method` <br/> `EXPORT_METHOD` | The build export method (eg: app-store) | |

#### `set_app_versions_xcodeproj_ios`

Update the iOS app versions in the xcodeproj (`CFBundleVersion` & `CFShortBundleVersion`) using the
passed parameters. Note that an export method of `app-store` will trim the `CFBundleVersion` to only
contain the build number.

| Key & Env Var | Description | Default Value
|-----------------|--------------------|---|
| `project_path` <br/> `PROJECT_PATH` | The path to the project .xcodeproj |  |
| `build_config` <br/> `BUILD_CONFIGURATION` | The build configuration (eg: Debug) | |
| `short_version_string` | The short version string (eg: 0.2.6) | `SharedValues::SHORT_VERSION_STRING` |
| `build_number` <br/> `BUILD_NUMBER` | The build number (eg: 625) | `SharedValues::FUELED_BUILD_NUMBER` |
| `export_method` <br/> `EXPORT_METHOD` | The build export method (eg: app-store) | |

### `check_code_coverage_ios`

Check how much of your code is covered by unit tests.

| Key & Env Var | Description | Default Value
|-----------------|--------------------|---|
| `code_coverage_config_file_path` | The path of the code coverage config file, the structure of this file is created by Fueled |  |
| `result_bundle_file_path` | The result bundle file path (xcresult) | |
| `minimum_code_coverage_percentage` | The minimum code coverage percentage accepted (eg: 64.5) | 80 |

#### `use_git_credential_store`

Store your git credential in the git credential store (~/.git-credentials)

| Key & Env Var | Description | Default Value
|-----------------|--------------------|---|
| `git_token` <br/> `GIT_TOKEN` | The git token that will be stored | |
| `git_user_name` <br/> `GIT_USER_NAME` | The git username that will be stored | |
| `git_host` <br/> `GIT_HOST` | The host of your git repository | |

#### `tag`

Tag the version using the following pattern : `v[short_version]#[build_number]-[build_config]`

Note that tagging happens only on CI

| Key & Env Var | Description | Default Value
|-----------------|--------------------|---|
| `build_config` <br/> `BUILD_CONFIGURATION` | The build configuration (eg: Debug) | |
| `short_version_string` | The short version string (eg: 0.2.6) | `SharedValues::SHORT_VERSION_STRING` |
| `build_number` <br/> `BUILD_NUMBER` | The build number (eg: 625) | `SharedValues::FUELED_BUILD_NUMBER` |

#### `upload_to_app_center`

Upload the given file to app center. You need to pass custom distribution groups to properly target
audiences. Note that it only runs on CI.

| Key & Env Var | Description | Default Value
|-----------------|--------------------|---|
| `api_token` <br/> `AC_API_TOKEN` | The API Token to interact with AppCenter APIs | |
| `owner_name` <br/> `AC_OWNER_NAME` | The owner/organization name in AppCenter | `Fueled` |
| `app_name` <br/> `AC_APP_NAME` | The app name as set in AppCenter | |
| `file_path` | The path to the your app file | `Helper::FueledHelper.default_output_file` |
| `mapping` | The path to the your Android app mapping file | |
| `dsym` | The path to the your iOS app dysm file | |
| `groups` <br/> `AC_DISTRIBUTION_GROUPS` | A comma separated list of distribution groups | |
| `notify_testers` <br/> `AC_NOTIFY_TESTERS` | Should the testers be notified | |
| `changelog` | The changelog for this release | |

#### `upload_to_app_store`

Upload the given file to the AppStore (TestFlight)
This action uses an application specific password. Note that it only runs on CI.

| Key & Env Var | Description | Default Value
|-----------------|--------------------|---|
| `file_path` | The path to the your app file | `Helper::FueledHelper.default_output_file` |
| `username` <br/> `TESTFLIGHT_USERNAME` | The app name as set in AppCenter | |
| `password` <br/> `TESTFLIGHT_APP_SPECIFIC_PASSWORD` | The AppleId app specific password | |
| `target_platform` | The target platform (`macos` | `ios` | `appletvos`) | `ios` |

#### `formatting_checks_flutter`

Check the formatting of the code using `flutter format`

#### `generate_files_flutter`

Performs code generation

| Key & Env Var | Description | Default Value
|-----------------|--------------------|---|
| `build_variant` | The build variant used for generating files | `debug` |

#### `ci_checks_flutter`

Run tests and check code coverage

## Issues and Feedback

For any other issues and feedback about this plugin, please submit it to this repository.

## Troubleshooting

If you have trouble using plugins, check out
the [Plugins Troubleshooting](https://docs.fastlane.tools/plugins/plugins-troubleshooting/) guide.

## Using _fastlane_ Plugins

For more information about how the `fastlane` plugin system works, check out
the [Plugins documentation](https://docs.fastlane.tools/plugins/create-plugin/).

## About _fastlane_

_fastlane_ is the easiest way to automate beta deployments and releases for your iOS and Android
apps. To learn more, check out [fastlane.tools](https://fastlane.tools).