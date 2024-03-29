require_relative '../helper/fueled_helper'

module Fastlane
    module Actions

    class CheckCodeCoverageIosAction < Action

        def self.run(params)
            code_coverage_config_file_path = params[:code_coverage_config_file_path]
            result_bundle_file_path = params[:result_bundle_file_path]
            minimum_code_coverage_percentage = params[:minimum_code_coverage_percentage]

            if !minimum_code_coverage_percentage.between?(0, 100)
              UI.user_error!("Minimum code coverage percentage should be between 0 and 100.")
            end 

            total_code_coverage_percentage = Helper::FueledHelper.calculate_code_coverage_percentage(code_coverage_config_file_path, result_bundle_file_path)
            
            if total_code_coverage_percentage < minimum_code_coverage_percentage
              UI.build_failure!("Code coverage percentage is below the minimum! 🚫🚫🚫")
            else
              UI.success("Code coverage percentage is accepted ✅.")
            end
        end

         #####################################################
        # @!group Documentation
        #####################################################
  
        def self.description
            "Check the code coverage percentage, if it's lower than the provided one the action will fail. result_bundle should be set to true in your scan action"
        end

        def self.available_options
            [
              FastlaneCore::ConfigItem.new(
                key: :code_coverage_config_file_path,
                env_name: "CODE_COVERAGE_CONFIG_FILE_PATH",
                description: "The Fueled code coverage config file path",
                is_string: true,
                optional: false
              ),
              FastlaneCore::ConfigItem.new(
                key: :result_bundle_file_path,
                env_name: "RESULT_BUNDLE_FILE_PATH",
                description: "The result bundle file path (xcresult)",
                is_string: true,
                optional: false
              ),
              FastlaneCore::ConfigItem.new(
                key: :minimum_code_coverage_percentage,
                env_name: "MINIMUM_CODE_COVERAGE_PERCENTAGE",
                description: "The minimum percentage required for code coverage, a calculated percentage below the given one will lead to a failure",
                is_string: false,
                optional: true,
                default_value: 80
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