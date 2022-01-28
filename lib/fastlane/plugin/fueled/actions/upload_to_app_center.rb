require_relative '../helper/fueled_helper'

module Fastlane
  module Actions
    module SharedValues
    end

    class UploadToAppCenterAction < Action
      def self.run(params)
        if other_action.is_ci
          other_action.appcenter_upload(
            api_token: params[:api_token],
            owner_type: "organization",
            owner_name: params[:owner_name],
            app_name: params[:app_name],
            mapping: params[:mapping],
            dsym: params[:dsym],
            file: params[:file_path],
            destinations: (params[:groups]).to_s,
            destination_type: "group",
            notify_testers: params[:notify_testers],
            release_notes: params[:changelog]
          )
        else
          UI.message("Not uploading #{params[:file_path]} as we're not on CI.")
        end
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        "Upload the given file to app center"
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
            key: :api_token,
            env_name: "AC_API_TOKEN",
            description: "The API Token to interact with AppCenter APIs",
            is_string: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :owner_name,
            env_name: "AC_OWNER_NAME",
            description: "The owner/organization name in AppCenter",
            optional: true,
            default_value: "Fueled",
            is_string: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :app_name,
            env_name: "AC_APP_NAME",
            description: "The app name as set in AppCenter",
            is_string: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :file_path,
            description: "The path to the your app file",
            is_string: true,
            default_value: Helper::FueledHelper.default_output_file
          ),
          FastlaneCore::ConfigItem.new(
            key: :mapping,
            description: "The path to the your Android app mapping file",
            is_string: true,
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :dsym,
            description: "The path to the your iOS app dysm file",
            is_string: true,
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :groups,
            env_name: "AC_DISTRIBUTION_GROUPS",
            description: "A comma separated list of distribution groups",
            is_string: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :notify_testers,
            env_name: "AC_NOTIFY_TESTERS",
            description: "Should the testers be notified",
            optional: true,
            default_value: true,
            is_string: false
          ),
          FastlaneCore::ConfigItem.new(
            key: :changelog,
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
        true
      end
    end
  end
end
