require_relative '../helper/fueled_helper'

module Fastlane
  module Actions
    module SharedValues
      TAG_NAME = :TAG_NAME
    end

    class TagAction < Action
      def self.run(params)
        tag_name = "v#{params[:short_version_string]}##{params[:build_number]}-#{params[:build_config]}"
        Actions.lane_context[SharedValues::TAG_NAME] = tag_name
        if other_action.is_ci
          UI.message("Tagging #{tag_name}...")
          other_action.sh("git tag -f \"#{tag_name}\" && git push origin \"refs/tags/#{tag_name}\" --force")
          return tag_name
        else
          UI.message("Not tagging #{tag_name} as we're not on CI.")
        end
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        "Tag the version using the following pattern : v[short_version]#[build_number]-[build_config]"
      end

      def self.details
        "Note that tagging happens only on CI"
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            key: :short_version_string,
            description: "The short version string (eg: 0.2.6)",
            optional: false,
            default_value: Actions.lane_context[SharedValues::SHORT_VERSION_STRING]
          ),
          FastlaneCore::ConfigItem.new(
            key: :build_number,
            description: "The build number (eg: 625)",
            optional: false,
            default_value: Actions.lane_context[SharedValues::FUELED_BUILD_NUMBER]
          ),
          FastlaneCore::ConfigItem.new(
            key: :build_config,
            env_name: "BUILD_CONFIGURATION",
            description: "The build configuration (eg: Debug)",
            optional: false
          )
        ]
      end

      def self.output
        [
          ['TAG_NAME', 'The tag name']
        ]
      end

      def self.return_value
        "Return the git tag if any was done. Only tagging on CI"
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
