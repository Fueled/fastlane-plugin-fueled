require_relative '../helper/fueled_helper'

module Fastlane
  module Actions
    module SharedValues
      IS_BUILD_NECESSARY = :IS_BUILD_NECESSARY
    end

    class IsBuildNecessaryAction < Action
      def self.run(params)
        if params[:force_necessary] || has_recent_commits(build_config: params[:build_config], suffix: params[:suffix])
            UI.important("Build is required.")
            Actions.lane_context[SharedValues::IS_BUILD_NECESSARY] = true
            true
        else
            UI.important("Build is not required, no additional revisions since last successful build.")
            Actions.lane_context[SharedValues::IS_BUILD_NECESSARY] = false
            false
        end
      rescue
        true
      end

      def self.has_recent_commits(build_config:, suffix:)
        last_config_tag = other_action.last_git_tag(pattern: "v*-#{build_config}*#{suffix}*") || ""
        if last_config_tag.empty?
          # No previous tag should start a build and intialize a starting tag
          true
        else
          number_of_commits = sh("git rev-list #{last_config_tag}.. --count").strip.to_i
          number_of_commits > 0
        end
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        "Defines if the build is necessary by looking up changes since the last tag for the same build configuration."
      end

      def self.details
        "
        If the number of revisions between the last tag matching the given build configuration, and HEAD
        is higher than 0, the action will return true.
        "
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            key: :build_config,
            env_name: "BUILD_CONFIGURATION",
            description: "The build configuration (eg: Debug)",
            optional: false
          ),
          FastlaneCore::ConfigItem.new(
            key: :force_necessary,
            env_name: "FORCE_NECESSARY",
            description: "If the lane should continue, regardless of changes being made or not",
            optional: false,
            default_value: false
          ),
          FastlaneCore::ConfigItem.new(
            key: :suffix,
            env_name: "SUFFIX",
            description: "The suffix used to distinguish platforms with shared codebase (eg: -iOS, -macOS)",
            optional: false,
            default_value: ""
          )
        ]
      end

      def self.return_value
        "Return if the build is necessary or not"
      end

      def self.output
        [
          ['IS_BUILD_NECESSARY', 'If the build is necessary or not']
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
