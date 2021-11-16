require_relative '../helper/fueled_helper'

module Fastlane
  module Actions
    class SetAppVersionsPlistIosAction < Action
      def self.run(params)
        version_string = "#{params[:build_number]}-#{params[:build_config]}"
        other_action.increment_version_number_in_plist(
          version_number: params[:short_version_string],
            xcodeproj: params[:project_path]
        )
        other_action.increment_build_number_in_plist(
          build_number: version_string,
            xcodeproj: params[:project_path]
        )
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        "Update the iOS app versions in the plist file (CFBundleVersion & CFShortBundleVersion) using the passed parameters."
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            key: :project_path,
            env_name: "PROJECT_PATH",
            description: "The path to the project .xcodeproj",
            is_string: true,
            optional: false
          ),
          FastlaneCore::ConfigItem.new(
            key: :build_config,
            env_name: "BUILD_CONFIGURATION",
            description: "The build configuration (eg: Debug)",
            optional: false
          ),
          FastlaneCore::ConfigItem.new(
            key: :short_version_string,
            description: "The short version string (eg: 0.2.6)",
            optional: true,
            default_value: Actions.lane_context[SharedValues::SHORT_VERSION_STRING]
          ),
          FastlaneCore::ConfigItem.new(
            key: :build_number,
            description: "The build number (eg: 625)",
            optional: true,
            default_value: Actions.lane_context[SharedValues::BUILD_NUMBER]
          )
        ]
      end

      def self.output
        []
      end

      def self.authors
        ["fueled"]
      end

      def self.is_supported?(platform)
        [:ios, :mac].include?(platform)
      end
    end
  end
end
