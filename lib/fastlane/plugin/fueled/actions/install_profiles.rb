require_relative '../helper/fueled_helper'

module Fastlane
  module Actions
    module SharedValues
    end

    class InstallProfilesAction < Action
      def self.run(params)
        folder = params[:folder]
        UI.message("Crawling #{folder}...")
        Dir.children(folder).each do |profile|
          UI.message("Found #{profile}")
          other_action.install_provisioning_profile(
            path: File.join(folder, profile)
          )
        end
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        "Install provisioning profiles from the given folder"
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            key: :folder,
            env_name: "PROFILES_FOLDER",
            description: "The folder where the provisioning profiles are stored",
            is_string: true,
            default_value: "fastlane/profiles"
          )
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
