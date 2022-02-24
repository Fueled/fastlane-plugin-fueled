module Fastlane
  module Actions
    module SharedValues
    end

    class GenerateFilesFlutterAction < Action
      def self.run(params)
        variant = params[:build_variant]
        UI.message("Running Codegen for #{variant}")
        sh("flutter pub run build_runner build --delete-conflicting-outputs --define \"dynamic_config_generator|config_builder=variant=#{variant}\"")
        UI.message("Generating Localization files")
        sh("flutter pub run easy_localization:generate -S \"assets/translations\" -O \"lib/gen\"")
        sh("flutter pub run easy_localization:generate -S \"assets/translations\" -O \"lib/gen\" -o \"locale_keys.g.dart\" -f keys")
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        "Run code generators for a Flutter project"
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            key: :build_variant,
            env_name: "BUILD_VARIANT",
            description: "The build variant used for generating config file",
            is_string: true,
            default_value: "debug"
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
