require_relative '../helper/fueled_helper'

module Fastlane
  module Actions
    module SharedValues
    end

    class UploadToAppStoreAction < Action
      def self.run(params)
        if other_action.is_ci
          sh("xcrun altool --upload-app -t #{params[:target_platform]} -u #{params[:username]} -p #{params[:password]} -f #{params[:file_path]}")
        else
          UI.message("Not uploading #{params[:file_path]} as we're not on CI.")
        end
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        "Upload the given file to the AppStore (TestFlight)"
      end

      def self.details
        "
        This action uses an application specific password
        Note that it only runs on CI.
        "
      end

      def self.available_options
        verify_block = lambda do |value|
          allowed_values = ["macos", "ios", "appletvos"]
          UI.user_error!("Invalid platform : #{value}. Allowed values are #{allowed_values.join(', ')}.") unless allowed_values.include?(value)
        end
        [
          FastlaneCore::ConfigItem.new(
            key: :file_path,
            description: "The path to the your app file",
            is_string: true,
            default_value: Helper::FueledHelper.default_output_file
          ),
          FastlaneCore::ConfigItem.new(
            key: :username,
            env_name: "TESTFLIGHT_USERNAME",
            description: "The AppleId username (email address)",
            is_string: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :password,
            env_name: "TESTFLIGHT_APP_SPECIFIC_PASSWORD",
            description: "The AppleId app specific password",
            is_string: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :target_platform,
            description: "The target platform (macos | ios | appletvos)",
            is_string: true,
            default_value: "ios",
            verify_block: verify_block
          ),
        ]
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
