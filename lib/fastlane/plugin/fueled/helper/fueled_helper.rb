require 'fastlane/action'
require 'fastlane_core/ui/ui'
require 'fastlane/plugin/versioning'
require 'fastlane/plugin/appcenter'

module Fastlane
  UI = FastlaneCore::UI unless Fastlane.const_defined?("UI")

  module Helper
    class FueledHelper
      # Returns if a string is nil or empty.
      def self.nil_or_empty(input)
        input.nil? || input.empty?
      end

      # Returns the last tag in the repo, one can filter tags by specifying the parameter
      def self.fetch_last_tag(filter:)
        tag = nil
        git_cmd = "git tag -l --sort=-v:refname"
        if filter == nil
           filter =""
        end
        git_cmd = git_cmd + "| grep -iF '#{filter}' -m 1"
        begin
          tag = Actions::sh(git_cmd)
        rescue FastlaneCore::Interface::FastlaneShellError
        end
        tag
      end
      
      # Returns the new build number, by bumping the last git tag build number.
      def self.new_build_number(filter:)
        last_tag = fetch_last_tag(filter: filter)
        last_tag = last_tag || "v0.0.0#0-None"
        last_build_number = (last_tag[/#(.*?)-/m, 1] || "0").to_i
        last_build_number + 1
      end

      # Returns the current short version. If the skip_version_limit flag is not set and the major version in the project or
      # plist is equal or greater than 1, it will be returned. Otherwise, the version
      # returned will be the one identified in the last git tag.
      def self.short_version_ios(project_path:, scheme:, skip_version_limit:, build_type:)
        version = Actions::GetVersionNumberFromPlistAction.run(
          xcodeproj: project_path,
          target: nil,
          scheme: scheme,
          build_configuration_name: build_type
        )
        if version != nil && !version.split('.').first.match?(/[[:digit:]]/)
          UI.important("Version found in plist is not digit: #{version}")
          version = nil
        end
        UI.important("No short version found in plist, looking in Xcodeproj...") if version.nil?
        if version.nil?
          version = Actions::GetVersionNumberFromXcodeprojAction.run(
            xcodeproj: project_path,
            target: nil,
            scheme: scheme,
            build_configuration_name: build_type
          )
        end
        UI.important("No short version found in the project, will rely on git tags to find out the last short version.") if version.nil?
        if !skip_version_limit && !version.nil? && version.split('.').first.to_i >= 1
          UI.important("Version: #{version}")
          version
        else
          short_version_from_tag(filter:build_type)
        end
      end

      # Returns the current short version. If the major version in the pubspec
      # is equal or greater than 1, it will be returned. Otherwise, the version
      # returned will be the one identified in the last git tag.
      def self.short_version_flutter(build_type:)
        file_name = "pubspec.yaml"
        pubspec_content = File.read(file_name)
        version = pubspec_content[/version:\ (\d+(\.\d+){0,2})\+[\da-zA-Z]+/m, 1]
        UI.important("No short version found in the pubspec, will rely on git tags to find out the last short version.") if version.nil?
        if !version.nil? && version.split('.').first.to_i >= 1
          version
        else
          UI.important("App found in pubspec is lower than 1.0.0 (#{version}), reading the version from the last git tag.")
          short_version_from_tag(filter:build_type)
        end
      end

      # Returns the current short version.  Returns the current short version. If the skip_version_limit flag is not set and the major version in package.json
      # is equal or greater than 1, it will be returned. Otherwise, the version
      # returned will be the one identified in the last git tag.
      def self.short_version_react_native(skip_version_limit:, build_type:)
        file_name = "package.json"
        package_content = File.read(file_name)
        version = package_content[/"version":\ "(\d+(\.\d+){0,2})"/m, 1]
        UI.important("No short version found in #{file_name}, will rely on git tags to find out the last short version.") if version.nil?
        if !skip_version_limit && !version.nil? && version.split('.').first.to_i >= 1
          version
        else
          UI.important("App found in #{file_name} is lower than 1.0.0 (#{version}), reading the version from the last git tag.")
          short_version_from_tag(filter:build_type)
        end
      end

      # Returns the current short version, only by reading the last tag.
      def self.short_version_from_tag(filter:)
        UI.important("Setting short_version from most recent tag")
        last_tag = fetch_last_tag(filter: filter)
        last_tag = (last_tag.nil? || last_tag.empty?) ?  "v0.0.0#0-None" : last_tag
        last_tag[/v(.*?)[(#]/m, 1]
      end

      # Bump a given semver version, by incrementing the appropriate
      # component, as per the bump_type (patch, minor, major, or none).
      def self.bump_semver(semver:, bump_type:)
        splitted_version = {
            major: semver.split('.').map(&:to_i)[0] || 0,
            minor: semver.split('.').map(&:to_i)[1] || 0,
            patch: semver.split('.').map(&:to_i)[2] || 0
          }
        case bump_type
        when "patch"
          splitted_version[:patch] = splitted_version[:patch] + 1
        when "minor"
          splitted_version[:minor] = splitted_version[:minor] + 1
          splitted_version[:patch] = 0
        when "major"
          splitted_version[:major] = splitted_version[:major] + 1
          splitted_version[:minor] = 0
          splitted_version[:patch] = 0
        end
        [splitted_version[:major], splitted_version[:minor], splitted_version[:patch]].map(&:to_s).join('.')
      end

      # Returns the default artefact file depending on the platform (ios vs android).
      # This function is being used by the upload_to_app_center
      def self.default_output_file
        platform = Actions.lane_context[Actions::SharedValues::PLATFORM_NAME].to_s
        if platform == "ios"
          Actions.lane_context[Actions::SharedValues::IPA_OUTPUT_PATH]
        elsif platform == "android" && ENV['BUILD_FORMAT'] == "apk"
          Actions.lane_context[Actions::SharedValues::GRADLE_APK_OUTPUT_PATH]
        elsif platform == "android"
          Actions.lane_context[Actions::SharedValues::GRADLE_AAB_OUTPUT_PATH]
        end
      end

      # Returns the list of generated build artifacts.
      # This function is being used by the create_github_release actions.
      def self.default_gh_release_output_files
        [
          Actions.lane_context[Actions::SharedValues::IPA_OUTPUT_PATH],
          Actions.lane_context[Actions::SharedValues::DSYM_OUTPUT_PATH],
          Actions.lane_context[Actions::SharedValues::GRADLE_APK_OUTPUT_PATH],
          Actions.lane_context[Actions::SharedValues::GRADLE_AAB_OUTPUT_PATH],
          Actions.lane_context[Actions::SharedValues::GRADLE_MAPPING_TXT_OUTPUT_PATH]
        ].compact!
      end

      # Calculate the code coverage percentage
      # This function takes the code coverage configuration file and checks the result bundle file for the code coverage percentage using the xccov tool.
      # Additionally, this function can also generate HTML reports for the code coverage.
      def self.calculate_code_coverage_percentage(
        code_coverage_config_file_path,
        result_bundle_file_path,
        minimum_code_coverage_percentage = nil,
        generate_reports = false
      )
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

        reports_data = []

        test_results['targets'].each do |target|
          target_name = target['name'].split(".")[0]
          if included_targets.include?(target_name)
            target['files'].each do |file|
              if should_check_code_coverage(file, code_coverage_config)
                percentage = file['lineCoverage'] * 100
                UI.message("#{file['name']}: #{percentage}%")
                number_of_files += 1
                code_coverage_percentage += percentage
                reports_data << { 'file_name': file['name'], 'coverage_percentage': percentage, 'target_name': target_name }
              end
            end
          end
        end
          
          if number_of_files == 0
            UI.important("No files/tests were found, please check if this is intentional")
          end
        
        total_code_coverage_percentage = number_of_files > 0 ? code_coverage_percentage / number_of_files : 100
        file_message = number_of_files > 1 ? "files" : "file"
        UI.message("Checked code coverage on #{number_of_files} #{file_message} with total percentage of #{total_code_coverage_percentage}%")

        if generate_reports
          UI.error("You should pass minimum code coverage percentage in order to generate reports") unless minimum_code_coverage_percentage
          return generate_code_reports(reports_data, minimum_code_coverage_percentage, total_code_coverage_percentage)
        end

        total_code_coverage_percentage
      end

      private

      def self.should_check_code_coverage(file, code_coverage_config)
        file_name = file['name'].downcase
        include_condition = code_coverage_config['file_name_include'].reduce(false) { |result, name| result || file_name.include?(name.downcase) }
        exclude_condition = code_coverage_config['file_name_exclude'].reduce(false) { |result, name| result || file_name.include?(name.downcase) }
        include_condition && !exclude_condition && !file_name.end_with?(".generated.swift")
      end

      def self.generate_code_reports(data, minimum_code_coverage_percentage, total_code_coverage_percentage)
        grouped_data = data.group_by { |hash| hash[:target_name] }
        html = %Q(
          <!DOCTYPE html>
          <html>
            <head>
              <style>
                * {
                  font-family: sans-serif, Arial, Helvetica;
                }

                #code-coverage-table {
                  border-collapse: collapse;
                  width: 100%;
                  margin-bottom: 5%;
                }

                #code-coverage-table td, #code-coverage-table th {
                  border: 1px solid #ddd;
                  padding: 8px;
                }

                #code-coverage-table tr:nth-child(even){background-color: #f2f2f2;}

                #code-coverage-table tr:hover {background-color: #ddd;}

                #code-coverage-table th {
                  padding-top: 12px;
                  padding-bottom: 12px;
                  text-align: left;
                  background-color: #04AA6D;
                  color: white;
                }

                #test-title {
                  margin-bottom: 5%;
                }

                tfoot td {
                  background-color: #f2f2f2;
                  font-weight: bold;
                }

                .content {
                  width: 75%;
                  margin: 0 auto;
                }

                .red {
                  color: red;
                }
              </style>
            </head>
            <body class="content">
            <h2 id="test-title">Total Test Coverage Percentage is <span class="coloredValue">#{total_code_coverage_percentage}%</span></h2>
        )

          grouped_data.each do |target_name, hashes|
            html += %Q(
              <h3>#{target_name}</h3>
              <table id="code-coverage-table">
                <thead>
                  <tr>
                    <th>File Name</th>
                    <th>Coverage Percentage</th>
                  </tr>
                </thead>
                <tbody>
            )         

            hashes.each do |hash|
              html += %Q(
                    <tr>
                      <td>#{hash[:file_name]}</td>
                      <td class="coloredValue">#{hash[:coverage_percentage]}%</td>
                    </tr>
              )
            end

            total_percentage = hashes.sum { |hash| hash[:coverage_percentage] } / hashes.length.to_f 

            html += %Q(
                </tbody>
                <tfoot>
                  <tr>
                    <td colspan="1">Total Percentage</td>
                      <td class="coloredValue">#{total_percentage}%</td>
                    </tr>
                  </tfoot>
                </table>
              )
          end

          html += %Q(
              </body>
              <script>
                var coloredValues = document.getElementsByClassName('coloredValue');

                for (var i = 0; i < coloredValues.length; i++) {
                  var coloredValue = coloredValues[i];
                  var value = parseFloat(coloredValue.textContent);

                  console.log(value);
                  if (value < #{minimum_code_coverage_percentage}) {
                    coloredValue.classList.add('red');
                  }
                }
              </script>
            </html>
          )

          html
      end

      # Update Xcode project signing settings after build tools (Flutter, CocoaPods, etc.) modify it
      # This should be called after flutter build ios or pod install
      def self.update_xcode_signing_after_build
        require_relative '../library/xcode/project_updater'
        
        begin
          Helper::Xcode::ProjectUpdater.update_provisioning_profile_from_lane_context
          true
        rescue StandardError => e
          UI.important("⚠ Could not update Xcode project after build: #{e.message}")
          false
        end
      end
    end
  end
end
