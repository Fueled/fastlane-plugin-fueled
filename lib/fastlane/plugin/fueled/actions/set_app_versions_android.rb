require_relative '../helper/fueled_helper'

module Fastlane
  module Actions
    class SetAppVersionsAndroidAction < Action
      def self.run(params)
        ENV['BUILD_VERSION_NAME'] = params[:short_version_string]
        ENV['BUILD_NUMBER'] = params[:build_number]
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        "Update the Android app version using the passed parameters."
      end

      def self.details
        "Update the Android app version using the passed parameters."
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            key: :short_version_string,
            description: "The short version string (eg: 0.2.6)",
            optional: true,
            default_value: Actions.lane_context[SharedValues::SHORT_VERSION_STRING]
          ),
          FastlaneCore::ConfigItem.new(
            key: :build_number,
            env_name: "BUILD_NUMBER",
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
        [:android].include?(platform)
      end
    end
  end
end
