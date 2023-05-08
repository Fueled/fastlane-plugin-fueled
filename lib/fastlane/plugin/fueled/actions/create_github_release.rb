require_relative '../helper/fueled_helper'

module Fastlane
  module Actions
    module SharedValues
    end

    class CreateGithubReleaseAction < Action
      def self.run(params)
        tag_name = "v#{params[:short_version_string]}##{params[:build_number]}-#{params[:build_config]}"
        release_name = "v#{params[:short_version_string]} / #{params[:build_number]}-#{params[:build_config]}"
        if other_action.is_ci
          other_action.set_github_release(
            repository_name: params[:repository_name],
            api_bearer: params[:github_token],
            name: release_name,
            tag_name: tag_name,
            description: Actions.lane_context[SharedValues::CHANGELOG_GITHUB],
            upload_assets: params[:upload_assets]
          )
        else
          UI.message("Not creating a GH release as we're not on CI.")
        end
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        "Creates a Github Release for the given tag, and changelog"
      end

      def self.details
        "Only create a GH release if triggered on CI"
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
            description: "The build number (eg: 625)",
            optional: true,
            default_value: Actions.lane_context[SharedValues::FUELED_BUILD_NUMBER]
          ),
          FastlaneCore::ConfigItem.new(
            key: :build_config,
            env_name: "BUILD_CONFIGURATION",
            description: "The build configuration (eg: Debug)",
            optional: true,
            default_value: "Debug"
          ),
          FastlaneCore::ConfigItem.new(
            key: :repository_name,
            env_name: "REPOSITORY_NAME",
            description: "The repository name (eg: fueled/zenni-ios)",
            optional: false
          ),
          FastlaneCore::ConfigItem.new(
            key: :github_token,
            env_name: "GITHUB_TOKEN",
            description: "A Github Token to interact with the GH APIs",
            optional: false
          ),
          FastlaneCore::ConfigItem.new(
            key: :upload_assets,
            env_name: "UPLOAD_ASSETS",
            description: "Assets to be included with the release",
            optional: false,
            type: Array,
            default_value: Helper::FueledHelper.default_gh_release_output_files
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
