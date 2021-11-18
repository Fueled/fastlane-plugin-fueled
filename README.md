# fueled plugin

[![fastlane Plugin Badge](https://rawcdn.githack.com/fastlane/fastlane/master/fastlane/assets/plugin-badge.svg)](https://rubygems.org/gems/fastlane-plugin-fueled)

## Getting Started

This project is a [_fastlane_](https://github.com/fastlane/fastlane) plugin. To get started with `fastlane-plugin-fueled`, add it to your project by adding:

```
gem 'fastlane-plugin-fueled', git: "https://github.com/Fueled/fastlane-plugin-fueled"
```

## About Fueled Fastlane plugin

This plugin embeds build steps that we use in our CI/CD pipeline at Fueled.
It has steps that could be reused easily by any project, on any platform (ios/android), and some others that are really
Fueled specific.

## Available Actions

* Common
  - [create_github_release](#user-content-create_github_release)
  - [generate_changelog](#user-content-generate_changelog)
  - [tag](#user-content-tag)
  - [upload_to_app_center](#user-content-upload_to_app_center)
* iOS
  - [define_versions_ios](#user-content-define_versions_ios)
  - [import_base_64_certificates](#user-content-import_base64_certificates)
  - [install_profiles](#user-content-install_profiles)
  - [install_wwdr_certificate](#user-content-install_wwdr_certificate)
  - [set_app_versions_plist_ios](#user-content-set_app_versions_plist_ios)
  - [set_app_versions_xcodeproj_ios](#user-content-set_app_versions_xcodeproj_ios)
* Android
  - [define_versions_android](#user-content-define_versions_android)
  - [set_app_versions_android](#user-content-set_app_versions_android)

## Example
We use `dotenv` files to specify most of the values being used by the actions. The advantage is that you can have several `dotenv` files, depending on the build target, or even the audience you intend to deliver the build to.

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
AC_APP_NAME=AppName
AC_DISTRIBUTION_GROUPS="Alpha Release,Collaborators"
AC_NOTIFY_TESTERS=true
# Testflight
TESTFLIGHT_APPLE_ID=$APPLE_ID
FASTLANE_APPLE_APPLICATION_SPECIFIC_PASSWORD=$APPLE_APP_PASSWORD
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
| `build_number` <br/> NONE | The build number (eg: 625) | `Actions.lane_context[SharedValues::BUILD_NUMBER]` |
| `build_config` <br/> `BUILD_CONFIGURATION` | The build configuration (eg: Debug) | `Debug` |
| `repository_name` <br/> `REPOSITORY_NAME` | The repository name (eg: fueled/zenni-ios) | |
| `github_token` <br/> `GITHUB_TOKEN` | A Github Token to interact with the GH APIs | |
| `upload_assets` <br/> `UPLOAD_ASSETS` | Assets to be included with the release | `Helper::FueledHelper.default_output_file` |

#### `define_versions_android`

Sets the new build version name and build number as shared values.

This action sets shared values for build number (`SharedValues::BUILD_NUMBER`) and build version name (`SharedValues::SHORT_VERSION_STRING`).
Your Fastfile should use these values in a next step to set them to the project accordingly (set_app_versions_android or set_app_versions_android).

| Key & Env Var | Description | Default Value
|-----------------|--------------------|---|
| `bump_type` <br/> `VERSION_BUMP_TYPE` | The version to bump (`major`, `minor`, `patch`, or `none`) | `none`

#### `define_versions_ios`

Sets the new CFBundleVersion and CFBundleShortVersion as shared values, without setting them in the project.

This action sets shared values for `CFBundleVersion` (`SharedValues::BUILD_NUMBER`) and `CFBundleShortVersion` (`SharedValues::SHORT_VERSION_STRING`).

Your Fastfile should use these values in a next step to set them to the project accordingly (`set_app_versions_xcodeproj_ios` or `set_app_versions_plist_ios`).

| Key & Env Var | Description | Default Value
|-----------------|--------------------|---|
| `project_path` <br/> `PROJECT_PATH` | The path to the project .xcodeproj |  |
| `bump_type` <br/> `VERSION_BUMP_TYPE` | The version to bump (`major`, `minor`, `patch`, or `none`) | `none`

#### `generate_changelog`
Generate a changelog.

Changelog is made of commits between now, and the previous tag using the same build configuration

| Key & Env Var | Description | Default Value
|-----------------|--------------------|---|
| `build_config` <br/> `BUILD_CONFIGURATION` | The build configuration (eg: Debug) | `Debug` |

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

#### `set_app_versions_android`
Update the Android app version using the passed parameters.

| Key & Env Var | Description | Default Value
|-----------------|--------------------|---|
| `short_version_string` | The short version string (eg: 0.2.6) | `SharedValues::SHORT_VERSION_STRING` |
| `build_number` <br/> `BUILD_NUMBER` | The build number (eg: 625) | `SharedValues::BUILD_NUMBER` |

#### `set_app_versions_plist_ios`
Update the iOS app versions in the plist file (`CFBundleVersion` & `CFShortBundleVersion`) using the passed parameters.

| Key & Env Var | Description | Default Value
|-----------------|--------------------|---|
| `project_path` <br/> `PROJECT_PATH` | The path to the project .xcodeproj |  |
| `build_config` <br/> `BUILD_CONFIGURATION` | The build configuration (eg: Debug) | |
| `short_version_string` | The short version string (eg: 0.2.6) | `SharedValues::SHORT_VERSION_STRING` |
| `build_number` <br/> `BUILD_NUMBER` | The build number (eg: 625) | `SharedValues::BUILD_NUMBER` |

#### `set_app_versions_xcodeproj_ios`
Update the iOS app versions in the xcodeproj (`CFBundleVersion` & `CFShortBundleVersion`) using the passed parameters.

| Key & Env Var | Description | Default Value
|-----------------|--------------------|---|
| `project_path` <br/> `PROJECT_PATH` | The path to the project .xcodeproj |  |
| `build_config` <br/> `BUILD_CONFIGURATION` | The build configuration (eg: Debug) | |
| `short_version_string` | The short version string (eg: 0.2.6) | `SharedValues::SHORT_VERSION_STRING` |
| `build_number` <br/> `BUILD_NUMBER` | The build number (eg: 625) | `SharedValues::BUILD_NUMBER` |

#### `tag`
Tag the version using the following pattern : `v[short_version]#[build_number]-[build_config]`

Note that tagging happens only on CI

| Key & Env Var | Description | Default Value
|-----------------|--------------------|---|
| `build_config` <br/> `BUILD_CONFIGURATION` | The build configuration (eg: Debug) | |
| `short_version_string` | The short version string (eg: 0.2.6) | `SharedValues::SHORT_VERSION_STRING` |
| `build_number` <br/> `BUILD_NUMBER` | The build number (eg: 625) | `SharedValues::BUILD_NUMBER` |

## Issues and Feedback

For any other issues and feedback about this plugin, please submit it to this repository.

## Troubleshooting

If you have trouble using plugins, check out the [Plugins Troubleshooting](https://docs.fastlane.tools/plugins/plugins-troubleshooting/) guide.

## Using _fastlane_ Plugins

For more information about how the `fastlane` plugin system works, check out the [Plugins documentation](https://docs.fastlane.tools/plugins/create-plugin/).

## About _fastlane_

_fastlane_ is the easiest way to automate beta deployments and releases for your iOS and Android apps. To learn more, check out [fastlane.tools](https://fastlane.tools).
