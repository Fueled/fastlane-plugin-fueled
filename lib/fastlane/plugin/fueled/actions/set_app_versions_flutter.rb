module Fastlane
  module Actions
    module SharedValues
    end

    class SetAppVersionsFlutterAction < Action
      def self.run(params)
        full_version_string = "#{params[:short_version_string]}-#{params[:build_config]}+#{params[:build_number]}"
        file_name = "pubspec.yaml"
        text = File.read(file_name)
        new_contents = text.gsub(/version:\ \d+(\.\d+){0,2}\+[\da-zA-Z\-]+/, "version: #{full_version_string}")
        File.open(file_name, "w") { |file| 
          file.puts new_contents 
        }
        UI.important("Updated version in pubspec.yaml to #{full_version_string}")
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        "Update the pubspec.yaml file with the passed short version, build number, and build configuration"
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
