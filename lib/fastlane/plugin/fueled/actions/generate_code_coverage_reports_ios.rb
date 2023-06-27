require_relative '../helper/fueled_helper'

module Fastlane
    module Actions

    class GenerateCodeCoverageReportsIosAction < Action

        def self.run(params)
            code_coverage_config_file_path = params[:code_coverage_config_file_path]
            result_bundle_file_path = params[:result_bundle_file_path]
            minimum_code_coverage_percentage = params[:minimum_code_coverage_percentage]

            if !minimum_code_coverage_percentage.between?(0, 100)
              UI.user_error!("Minimum code coverage percentage should be between 0 and 100.")
            end 

            report_file_string = Helper::FueledHelper.calculate_code_coverage_percentage(
              code_coverage_config_file_path,
              result_bundle_file_path,
              minimum_code_coverage_percentage,
              true
            )
            
            current_datetime = DateTime.now.strftime('%Y%m%d%H%M%S')
            file_name = "./test_coverage_report_#{current_datetime}.html"

            File.open(File.expand_path(file_name), "w") do |file|
              file.write(report_file_string)
            end

            UI.success("Code coverage reports have been generated successfully ✅.")
            file_name
        end

         #####################################################
        # @!group Documentation
        #####################################################
  
        def self.description
            "Generate code coverage reports"
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