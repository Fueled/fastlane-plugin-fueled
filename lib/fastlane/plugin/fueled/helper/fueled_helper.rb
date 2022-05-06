require 'fastlane/action'
require 'fastlane_core/ui/ui'
require 'fastlane/plugin/versioning'
require 'fastlane/plugin/appcenter'

module Fastlane
  UI = FastlaneCore::UI unless Fastlane.const_defined?("UI")

  module Helper
    class FueledHelper
      # Returns if a string is nil or empty.
      def self.nil_or_empty(input)
        input.nil? || input.empty?
      end

      # Returns the last tag in the repo, one can filter tags by specifying the parameter
      def self.fetch_last_tag(filter:)
        tag = nil
        git_cmd = "git tag -l --sort=-creatordate"
        if filter == nil
           filter =""
        end
        git_cmd = git_cmd + "| grep -iF '#{filter}' -m 1"
        begin
          tag = Actions::sh(git_cmd)
        rescue FastlaneCore::Interface::FastlaneShellError
        end
        tag
      end
      
      # Returns the new build number, by bumping the last git tag build number.
      def self.new_build_number(filter:)
        last_tag = fetch_last_tag(filter: filter)
        last_tag = last_tag || "v0.0.0#0-None"
        last_build_number = (last_tag[/#(.*?)-/m, 1] || "0").to_i
        last_build_number + 1
      end

      # Returns the current short version. If the skip_version_limit flag is not set and the major version in the project or
      # plist is equal or greater than 1, it will be returned. Otherwise, the version
      # returned will be the one identified in the last git tag.
      def self.short_version_ios(project_path:, scheme:, skip_version_limit:, build_type:)
        version = Actions::GetVersionNumberFromPlistAction.run(
          xcodeproj: project_path,
          target: nil,
          scheme: scheme,
          build_configuration_name: nil
        )
        UI.important("No short version found in plist, looking in Xcodeproj...") if version.nil?
        if version.nil?
          version = Actions::GetVersionNumberFromXcodeprojAction.run(
            xcodeproj: project_path,
            target: nil,
            scheme: scheme,
            build_configuration_name: nil
          )
        end
        UI.important("No short version found in the project, will rely on git tags to find out the last short version.") if version.nil?
        if !skip_version_limit && !version.nil? && version.split('.').first.to_i >= 1
          version
        else
          short_version_from_tag(filter:build_type)
        end
      end

      # Returns the current short version. If the major version in the pubspec
      # is equal or greater than 1, it will be returned. Otherwise, the version
      # returned will be the one identified in the last git tag.
      def self.short_version_flutter(build_type:)
        file_name = "pubspec.yaml"
        pubspec_content = File.read(file_name)
        version = pubspec_content[/version:\ (\d+(\.\d+){0,2})\+[\da-zA-Z]+/m, 1]
        UI.important("No short version found in the pubspec, will rely on git tags to find out the last short version.") if version.nil?
        if !version.nil? && version.split('.').first.to_i >= 1
          version
        else
          UI.important("App found in pubspec is lower than 1.0.0 (#{version}), reading the version from the last git tag.")
          short_version_from_tag(filter:build_type)
        end
      end

      # Returns the current short version.  Returns the current short version. If the skip_version_limit flag is not set and the major version in package.json
      # is equal or greater than 1, it will be returned. Otherwise, the version
      # returned will be the one identified in the last git tag.
      def self.short_version_react_native(skip_version_limit:, build_type:)
        file_name = "package.json"
        package_content = File.read(file_name)
        version = package_content[/"version":\ "(\d+(\.\d+){0,2})"/m, 1]
        UI.important("No short version found in #{file_name}, will rely on git tags to find out the last short version.") if version.nil?
        if !skip_version_limit && !version.nil? && version.split('.').first.to_i >= 1
          version
        else
          UI.important("App found in #{file_name} is lower than 1.0.0 (#{version}), reading the version from the last git tag.")
          short_version_from_tag(filter:build_type)
        end
      end

      # Returns the current short version, only by reading the last tag.
      def self.short_version_from_tag(filter:)
        last_tag = fetch_last_tag(filter: filter)
        last_tag = last_tag || "v0.0.0#0-None"
        last_tag[/v(.*?)[(#]/m, 1]
      end

      # Bump a given semver version, by incrementing the appropriate
      # component, as per the bump_type (patch, minor, major, or none).
      def self.bump_semver(semver:, bump_type:)
        splitted_version = {
            major: semver.split('.').map(&:to_i)[0] || 0,
            minor: semver.split('.').map(&:to_i)[1] || 0,
            patch: semver.split('.').map(&:to_i)[2] || 0
          }
        case bump_type
        when "patch"
          splitted_version[:patch] = splitted_version[:patch] + 1
        when "minor"
          splitted_version[:minor] = splitted_version[:minor] + 1
          splitted_version[:patch] = 0
        when "major"
          splitted_version[:major] = splitted_version[:major] + 1
          splitted_version[:minor] = 0
          splitted_version[:patch] = 0
        end
        [splitted_version[:major], splitted_version[:minor], splitted_version[:patch]].map(&:to_s).join('.')
      end

      # Returns the default artefact file depending on the platform (ios vs android).
      # This function is being used by the upload_to_app_center and the
      # create_github_release actions.
      def self.default_output_file
        platform = Actions.lane_context[Actions::SharedValues::PLATFORM_NAME].to_s
        if platform == "ios"
          Actions.lane_context[Actions::SharedValues::IPA_OUTPUT_PATH]
        elsif platform == "android" && ENV['BUILD_FORMAT'] == "apk"
          Actions.lane_context[Actions::SharedValues::GRADLE_APK_OUTPUT_PATH]
        elsif platform == "android"
          Actions.lane_context[Actions::SharedValues::GRADLE_AAB_OUTPUT_PATH]
        end
      end
    end
  end
end
