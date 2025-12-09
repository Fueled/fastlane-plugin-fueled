# frozen_string_literal: true

require 'xcodeproj'
require_relative 'project_parser'
require_relative 'project_detector'
require 'fastlane_core/ui/ui'

module Fastlane
  module Helper
    module Xcode
      module SigningUpdater
        module_function

        # Update signing settings in Xcode project
        #
        # Params:
        # - project_path: path to .xcodeproj or .xcworkspace
        # - bundle_id: String, bundle identifier to match targets
        # - team_id: String, optional development team ID
        # - signing_style: String, optional "Automatic" or "Manual"
        # - code_sign_identity: String, optional code signing identity
        #
        # Returns: Boolean, true if any updates were made
        def update_signing_settings(project_path:, bundle_id:, team_id: nil, signing_style: nil, code_sign_identity: nil)
          return false unless project_path && bundle_id
          return false unless File.exist?(project_path)

          begin
            project = resolve_project(project_path)
            updated = false

            UI.verbose("Updating signing settings for project: #{project_path}")
            UI.verbose("Team ID: #{team_id}, Signing style: #{signing_style}, Code sign identity: #{code_sign_identity}")

            project.build_configurations.each do |config|
              settings = config.build_settings
              updated |= update_config_setting(settings, 'DEVELOPMENT_TEAM', team_id, "project-level (#{config.name})")
              updated |= update_config_setting(settings, 'CODE_SIGN_STYLE', signing_style, "project-level (#{config.name})")
            end

            project.targets.each do |target|
              target.build_configurations.each do |config|
                settings = config.build_settings
                target_bundle_id = settings['PRODUCT_BUNDLE_IDENTIFIER']
                should_update = bundle_id.nil? || target_bundle_id == bundle_id

                if should_update
                  updated |= update_config_setting(settings, 'DEVELOPMENT_TEAM', team_id, "target '#{target.name}' (#{config.name})")
                  updated |= update_config_setting(settings, 'CODE_SIGN_STYLE', signing_style, "target '#{target.name}' (#{config.name})")
                  updated |= update_config_setting(settings, 'CODE_SIGN_IDENTITY', code_sign_identity, "target '#{target.name}' (#{config.name})")
                end
              end
            end

            project.save
            UI.success("✓ Updated signing settings for bundle ID: #{bundle_id}") if updated
            updated
          rescue StandardError => e
            UI.important("⚠ Failed to update signing settings: #{e.message}")
            false
          end
        end

        # Update DEVELOPMENT_TEAM in Xcode project file using regex
        # This directly modifies the .pbxproj file to ensure DEVELOPMENT_TEAM is set correctly
        # even if build tools (like Flutter) overwrite it
        #
        # Params:
        # - project_path: path to .xcodeproj or .xcworkspace
        # - team_id: String, development team ID to set
        # - bundle_id: String, optional bundle identifier (for logging)
        #
        # Returns: Boolean, true if updated successfully
        def update_development_team(project_path:, team_id:, bundle_id: nil)
          return false unless project_path && team_id

          actual_project_path = resolve_project_path(project_path)
          pbxproj_path = File.join(actual_project_path, 'project.pbxproj')
          return false unless File.exist?(pbxproj_path)

          begin
            UI.message("Updating DEVELOPMENT_TEAM in project file: #{pbxproj_path}")
            UI.verbose("Setting DEVELOPMENT_TEAM to: #{team_id}")
            lines = File.readlines(pbxproj_path)
            updated = false
            matches_found = 0

            lines.map! do |line|
              original_line = line.dup
              
              if line.match?(/DEVELOPMENT_TEAM\[sdk=/)
                sdk_pattern = /(\s*["']?DEVELOPMENT_TEAM\[sdk=[^\]]+\][\"']?\s*=\s*)(["']?)([^"';]+)(\2)(\s*;)/
                if line =~ sdk_pattern
                  matches_found += 1
                  old_value = $3.strip
                  sdk_match = line[/sdk=([^\]]+)/, 1]
                  UI.verbose("Found DEVELOPMENT_TEAM[sdk=#{sdk_match}] = #{old_value}")
                  if old_value != team_id
                    updated = true
                    UI.verbose("  → Updating to #{team_id}")
                    line = line.gsub(sdk_pattern, "\\1\\2#{team_id}\\2\\5")
                  else
                    UI.verbose("  → Already correct, skipping")
                  end
                end
              elsif line.match?(/\s+DEVELOPMENT_TEAM\s*=\s*/) && !line.match?(/DEVELOPMENT_TEAM\[sdk=/)
                regular_pattern = /(\s+DEVELOPMENT_TEAM\s*=\s*)(["']?)([^"';]+)(\2)(\s*;)/
                if line =~ regular_pattern
                  matches_found += 1
                  old_value = $3.strip
                  UI.verbose("Found DEVELOPMENT_TEAM = #{old_value}")
                  if old_value != team_id
                    updated = true
                    UI.verbose("  → Updating to #{team_id}")
                    line = line.gsub(regular_pattern, "\\1\\2#{team_id}\\2\\5")
                  else
                    UI.verbose("  → Already correct, skipping")
                  end
                end
              end
              
              line
            end

            if updated
              File.write(pbxproj_path, lines.join)
              UI.success("✓ Updated DEVELOPMENT_TEAM to #{team_id} in project file (#{matches_found} occurrence(s) found)")
              UI.verbose("  Bundle ID: #{bundle_id}") if bundle_id
              true
            elsif matches_found > 0
              UI.verbose("DEVELOPMENT_TEAM already set to #{team_id} (#{matches_found} occurrence(s) found)")
              false
            else
              UI.important("⚠ No DEVELOPMENT_TEAM entries found in project file")
              false
            end
          rescue StandardError => e
            UI.important("⚠ Failed to update DEVELOPMENT_TEAM in project file: #{e.message}")
            false
          end
        end

        # Update PROVISIONING_PROFILE UUID in Xcode project file using regex
        # This directly modifies the .pbxproj file to ensure PROVISIONING_PROFILE is set correctly
        # even if build tools (like Flutter) overwrite it
        #
        # Params:
        # - project_path: path to .xcodeproj or .xcworkspace
        # - profile_uuid: String, provisioning profile UUID to set
        # - bundle_id: String, optional bundle identifier (for logging)
        #
        # Returns: Boolean, true if updated successfully
        def update_provisioning_profile_uuid(project_path:, profile_uuid:, bundle_id: nil)
          return false unless project_path && profile_uuid

          actual_project_path = resolve_project_path(project_path)
          pbxproj_path = File.join(actual_project_path, 'project.pbxproj')
          return false unless File.exist?(pbxproj_path)

          begin
            UI.message("Updating PROVISIONING_PROFILE UUID in project file: #{pbxproj_path}")
            UI.verbose("Setting PROVISIONING_PROFILE to: #{profile_uuid}")
            lines = File.readlines(pbxproj_path)
            updated = false
            matches_found = 0

            lines.map! do |line|
              if line.match?(/PROVISIONING_PROFILE\[sdk=/)
                sdk_pattern = /(\s*["']?PROVISIONING_PROFILE\[sdk=[^\]]+\][\"']?\s*=\s*)(["']?)([^"';]+)(\2)(\s*;)/
                if line =~ sdk_pattern
                  matches_found += 1
                  old_value = $3.strip
                  sdk_match = line[/sdk=([^\]]+)/, 1]
                  UI.verbose("Found PROVISIONING_PROFILE[sdk=#{sdk_match}] = #{old_value}")
                  if old_value != profile_uuid
                    updated = true
                    UI.verbose("  → Updating to #{profile_uuid}")
                    line = line.gsub(sdk_pattern, "\\1\\2#{profile_uuid}\\2\\5")
                  else
                    UI.verbose("  → Already correct, skipping")
                  end
                end
              elsif line.match?(/\s+PROVISIONING_PROFILE\s*=\s*/) && !line.match?(/PROVISIONING_PROFILE\[sdk=/)
                regular_pattern = /(\s+PROVISIONING_PROFILE\s*=\s*)(["']?)([^"';]+)(\2)(\s*;)/
                if line =~ regular_pattern
                  matches_found += 1
                  old_value = $3.strip
                  UI.verbose("Found PROVISIONING_PROFILE = #{old_value}")
                  if old_value != profile_uuid
                    updated = true
                    UI.verbose("  → Updating to #{profile_uuid}")
                    line = line.gsub(regular_pattern, "\\1\\2#{profile_uuid}\\2\\5")
                  else
                    UI.verbose("  → Already correct, skipping")
                  end
                end
              end
              
              line
            end

            if updated
              File.write(pbxproj_path, lines.join)
              UI.success("✓ Updated PROVISIONING_PROFILE to #{profile_uuid} in project file (#{matches_found} occurrence(s) found)")
              UI.verbose("  Bundle ID: #{bundle_id}") if bundle_id
              true
            elsif matches_found > 0
              UI.verbose("PROVISIONING_PROFILE already set to #{profile_uuid} (#{matches_found} occurrence(s) found)")
              false
            else
              UI.important("⚠ No PROVISIONING_PROFILE entries found in project file")
              false
            end
          rescue StandardError => e
            UI.important("⚠ Failed to update PROVISIONING_PROFILE in project file: #{e.message}")
            false
          end
        end

        # Remove PROVISIONING_PROFILE_SPECIFIER from Xcode project file using regex
        # This directly modifies the .pbxproj file to ensure PROVISIONING_PROFILE_SPECIFIER is removed
        # even if build tools (like Flutter) overwrite it
        #
        # Params:
        # - project_path: path to .xcodeproj or .xcworkspace
        # - bundle_id: String, optional bundle identifier (for logging)
        #
        # Returns: Boolean, true if any updates were made
        def remove_provisioning_profile_specifier(project_path:, bundle_id: nil)
          return false unless project_path

          actual_project_path = resolve_project_path(project_path)
          pbxproj_path = File.join(actual_project_path, 'project.pbxproj')
          return false unless File.exist?(pbxproj_path)

          begin
            UI.verbose("Removing PROVISIONING_PROFILE_SPECIFIER from project file: #{pbxproj_path}")
            lines = File.readlines(pbxproj_path)
            updated = false
            matches_found = 0

            lines.reject! do |line|
              if line.match?(/PROVISIONING_PROFILE_SPECIFIER\[sdk=/)
                sdk_pattern = /^\s*["']?PROVISIONING_PROFILE_SPECIFIER\[sdk=[^\]]+\][\"']?\s*=\s*["']?[^"';]+["']?\s*;\s*$/
                if line =~ sdk_pattern
                  matches_found += 1
                  sdk_match = line[/sdk=([^\]]+)/, 1]
                  UI.verbose("Found PROVISIONING_PROFILE_SPECIFIER[sdk=#{sdk_match}] line, removing...")
                  updated = true
                  true
                else
                  false
                end
              elsif line.match?(/\s+PROVISIONING_PROFILE_SPECIFIER\s*=\s*/) && !line.match?(/PROVISIONING_PROFILE_SPECIFIER\[sdk=/)
                regular_pattern = /^\s+PROVISIONING_PROFILE_SPECIFIER\s*=\s*["']?[^"';]+["']?\s*;\s*$/
                if line =~ regular_pattern
                  matches_found += 1
                  UI.verbose("Found PROVISIONING_PROFILE_SPECIFIER line, removing...")
                  updated = true
                  true
                else
                  false
                end
              else
                false
              end
            end

            if updated
              File.write(pbxproj_path, lines.join)
              UI.success("✓ Removed PROVISIONING_PROFILE_SPECIFIER from project file (#{matches_found} occurrence(s) removed)")
              UI.verbose("  Bundle ID: #{bundle_id}") if bundle_id
              true
            elsif matches_found > 0
              UI.verbose("PROVISIONING_PROFILE_SPECIFIER already removed (#{matches_found} occurrence(s) found but not removed)")
              false
            else
              UI.verbose("No PROVISIONING_PROFILE_SPECIFIER entries found in project file")
              false
            end
          rescue StandardError => e
            UI.important("⚠ Failed to remove PROVISIONING_PROFILE_SPECIFIER from project file: #{e.message}")
            false
          end
        end

        # Update DEVELOPMENT_TEAM for a bundle ID by finding the project automatically
        #
        # Params:
        # - bundle_id: String, bundle identifier
        # - team_id: String, development team ID
        # - search_path: String, directory to search for projects (default: current directory)
        #
        # Returns: Boolean, true if updated successfully
        def update_development_team_for_bundle_id(bundle_id:, team_id:, search_path: Dir.pwd)
          return false unless bundle_id && team_id

          begin
            UI.message("🔍 Searching for Xcode project with bundle ID: #{bundle_id}")
            detected_project = ProjectDetector.find_project_with_bundle_id(
              bundle_id: bundle_id,
              search_path: search_path
            )

            if detected_project
              UI.message("✓ Found project: #{detected_project[:project_path]}")
              update_development_team(
                project_path: detected_project[:project_path],
                team_id: team_id,
                bundle_id: bundle_id
              )
            else
              UI.important("⚠ Could not find Xcode project with bundle ID: #{bundle_id}")
              false
            end
          rescue StandardError => e
            UI.important("⚠ Failed to update DEVELOPMENT_TEAM: #{e.message}")
            false
          end
        end

        def resolve_project(project_path)
          if project_path.end_with?('.xcworkspace')
            ProjectParser.resolve_project_from_workspace(project_path)
          else
            Xcodeproj::Project.open(project_path)
          end
        end
        module_function :resolve_project

        def resolve_project_path(project_path)
          if project_path.end_with?('.xcworkspace')
            ProjectParser.resolve_project_from_workspace(project_path).path
          else
            project_path
          end
        end
        module_function :resolve_project_path

        def update_config_setting(settings, key, value, location)
          return false unless value

          old_value = settings[key]
          settings[key] = value
          if old_value != value
            UI.message("Updated #{location}: #{key} = #{value} (was: '#{old_value}')")
            true
          else
            false
          end
        end
      end
    end
  end
end

