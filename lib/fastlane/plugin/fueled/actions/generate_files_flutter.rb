module Fastlane
  module Actions
    module SharedValues
    end

    class GenerateFilesFlutterAction < Action
      def self.run(params)
        variant = params[:build_variant]
        paths = params[:targets]
        if paths.empty?
          paths = "."
        end
        paths = (paths.to_s).split(',')
        # Loop through each item using a for loop
        paths.each do |path|
          UI.message("Running Codegen for #{variant} on #{path}")
          cmd = "cd #{path} && "
          cmd += "flutter pub get && "
          cmd += "dart run build_runner build --verbose --delete-conflicting-outputs --define \"dynamic_config_generator|config_builder=variant=#{variant}\""
          if !params[:skip_localization] && check_localization_package(path)
            cmd += " && echo \"Generating Localization files \""
            cmd += " && dart run easy_localization:generate -S \"assets/translations\" -O \"lib/gen\""
            cmd += " && dart run easy_localization:generate -S \"assets/translations\" -O \"lib/gen\" -o \"locale_keys.g.dart\" -f keys"
          end
          sh(cmd)
        end
      end

      def self.check_localization_package(folder_path)
        localization_package = "easy_localization"
        pubspec_file = File.join(folder_path, 'pubspec.yaml')
        if File.exist?(pubspec_file)
          content = File.read(pubspec_file)
          if content.include?(localization_package)
            return true
          else
            return false
          end
        else
          false
        end
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
          ),
          FastlaneCore::ConfigItem.new(
            key: :skip_localization,
            env_name: "SKIP_LOCALIZATION",
            description: "Whether to skip generating the localization files",
            optional: true,
            is_string: false,
            default_value: false
          ),
          FastlaneCore::ConfigItem.new(
            key: :targets,
            env_name: "BUILD_RUNNER_TARGETS",
            description: "In case your app uses multiple packages/modules and you want to run codegen in all of them, supply comma separated paths to each of them",
            is_string: true,
            default_value: ""
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
