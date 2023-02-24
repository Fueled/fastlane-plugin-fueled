require 'json'

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

            if !File.exist? code_coverage_config_file_path
                UI.user_error!("Cannot find Fueled code coverage config file at #{code_coverage_config_file_path}")
            end

            if !File.exist? result_bundle_file_path
              UI.user_error!("Cannot find result bundle file at #{result_bundle_file_path}")
            end

            code_coverage_config_file = File.read(code_coverage_config_file_path)

            if !code_coverage_config = JSON.parse(code_coverage_config_file) rescue nil
                UI.user_error!('The provided Fueled code coverage config file isn\'t in a valid format')
            end 

            UI.message("Calculating Code Coverage Percentage... 🤓")
            test_results_json_string = `xcrun xccov view --report --json \"#{result_bundle_file_path}\"`
            test_results = JSON.parse(test_results_json_string)

            included_targets = code_coverage_config["targets"]
            UI.message("\n\nLooking inside these targets: #{included_targets.join(', ')} 🕵🏻‍♂️\n")

            number_of_files = 0
            code_coverage_percentage = 0
    
            test_results['targets'].each do |target|
              target_name = target['name'].split(".")[0]
              if included_targets.include?(target_name)
                target['files'].each do |file|
                  if should_check_code_coverage(file, code_coverage_config)
                    UI.message("#{file['name']}: #{file['lineCoverage'] * 100}%")
                    number_of_files += 1
                    code_coverage_percentage += file['lineCoverage'] * 100
                  end
                end
              end
            end

            total_code_coverage_percentage = code_coverage_percentage / number_of_files
            file_message = number_of_files > 1 ? "files" : "file"
            UI.message("Checked code coverage on #{number_of_files} #{file_message} with total percentage of #{total_code_coverage_percentage}%")

            if total_code_coverage_percentage < minimum_code_coverage_percentage
              UI.build_failure!("Code coverage percentage is below the minimum! 🚫🚫🚫")
            else
              UI.success("Code coverage percentage is accepted ✅.")
            end
        end

        def self.should_check_code_coverage(file, code_coverage_config)
          file_name = file['name'].downcase
          include_condition = code_coverage_config['file_name_include'].reduce(false) { |result, name| result || file_name.include?(name.downcase) }
          exclude_condition = code_coverage_config['file_name_exclude'].reduce(false) { |result, name| result || file_name.include?(name.downcase) }
          include_condition && !exclude_condition && !file_name.end_with?(".generated.swift")
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