require_relative '../helper/fueled_helper'

module Fastlane
  module Actions
    module SharedValues
    end

    class UploadToTestFairyAndroidAction < Action
      def self.run(params)
        if other_action.is_ci
          other_action.testfairy(
            api_key: params[:api_key],
            apk: params[:apk],
            comment: params[:comment],
            symbols_file: params[:mapping],
          )
        else
          UI.message("Not uploading #{params[:file_path]} as we're not on CI.")
        end
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        "Upload the given file to TestFairy"
      end

      def self.details
        "
        You need to pass custom distribution groups to properly target audiences.
        Note that it only runs on CI.
        "
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            key: :api_key,
            env_name: "TESTFAIRY_ACCESS_KEY",
            description: "The upload API token to interact with TestFairy APIs",
            is_string: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :apk,
            description: "The path to the your Android APK file",
            is_string: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :mapping,
            description: "The path to the your Android APK mapping file",
            is_string: true,
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :comment,
            description: "The changelog for this release",
            is_string: true,
            optional: true,
            default_value: Actions.lane_context[SharedValues::CHANGELOG_MARKDOWN_PUBLIC]
          )
        ]
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
