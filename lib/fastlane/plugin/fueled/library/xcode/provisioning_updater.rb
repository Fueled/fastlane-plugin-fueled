# frozen_string_literal: true

require 'xcodeproj'
require_relative 'project_parser'
require 'fastlane_core/ui/ui'

module Fastlane
  module Helper
    module Xcode
      module ProvisioningUpdater
        module_function

        # Update provisioning profile settings in Xcode project
        #
        # Params:
        # - project_path: path to .xcodeproj or .xcworkspace
        # - bundle_id: String, bundle identifier to match targets
        # - profile_uuid: String, provisioning profile UUID
        # - profile_specifier: String, optional provisioning profile specifier (name)
        #
        # Returns: Boolean, true if any updates were made
        def update_provisioning_profile(project_path:, bundle_id:, profile_uuid:, profile_specifier: nil)
          return false unless project_path && bundle_id && profile_uuid
          return false unless File.exist?(project_path)

          begin
            UI.message("Updating Xcode project signing settings...")
            project = resolve_project(project_path)
            updated = false

            project.targets.each do |target|
              target.build_configurations.each do |config|
                settings = config.build_settings
                next unless settings['PRODUCT_BUNDLE_IDENTIFIER'] == bundle_id

                old_uuid = settings['PROVISIONING_PROFILE']
                old_specifier = settings['PROVISIONING_PROFILE_SPECIFIER']
                sdk_specific_keys = settings.keys.select { |key| key.start_with?('PROVISIONING_PROFILE_SPECIFIER[sdk=') }

                settings['PROVISIONING_PROFILE'] = profile_uuid

                if profile_specifier
                  settings['PROVISIONING_PROFILE_SPECIFIER'] = profile_specifier
                  sdk_specific_keys.each { |key| settings[key] = profile_specifier }
                else
                  (['PROVISIONING_PROFILE_SPECIFIER'] + sdk_specific_keys).each do |key|
                    settings.delete(key)
                    settings[key] = nil
                  end
                end

                new_specifier = settings['PROVISIONING_PROFILE_SPECIFIER']
                specifier_changed = if profile_specifier.nil?
                                      old_specifier != nil && old_specifier != ''
                                    else
                                      old_specifier != new_specifier
                                    end

                if old_uuid != profile_uuid || specifier_changed
                  specifier_display = new_specifier.nil? ? '(removed)' : "'#{new_specifier}'"
                  sdk_info = sdk_specific_keys.empty? ? '' : " (#{sdk_specific_keys.length} SDK variant(s) updated)"
                  UI.message("Updated target '#{target.name}' (#{config.name}): PROVISIONING_PROFILE = #{profile_uuid}, PROVISIONING_PROFILE_SPECIFIER = #{specifier_display}#{sdk_info}")
                  updated = true
                end
              end
            end

            project.save
            UI.success("✓ Updated Xcode project to use profile UUID: #{profile_uuid}") if updated
            updated
          rescue StandardError => e
            UI.important("⚠ Failed to update Xcode project signing: #{e.message}")
            false
          end
        end

        # Update bundle identifier in Xcode project
        #
        # Params:
        # - project_path: path to .xcodeproj or .xcworkspace
        # - old_bundle_id: String, current bundle identifier to match
        # - new_bundle_id: String, new bundle identifier to set
        #
        # Returns: Boolean, true if any updates were made
        def update_bundle_id(project_path:, old_bundle_id:, new_bundle_id:)
          return false unless project_path && old_bundle_id && new_bundle_id
          return false unless File.exist?(project_path)

          begin
            project = resolve_project(project_path)
            updated = false

            project.targets.each do |target|
              target.build_configurations.each do |config|
                settings = config.build_settings
                if settings['PRODUCT_BUNDLE_IDENTIFIER'] == old_bundle_id
                  settings['PRODUCT_BUNDLE_IDENTIFIER'] = new_bundle_id
                  UI.verbose("Updated target '#{target.name}' (#{config.name}): PRODUCT_BUNDLE_IDENTIFIER = #{new_bundle_id}")
                  updated = true
                end
              end
            end

            if updated
              project.save
              UI.success("✓ Updated bundle identifier from #{old_bundle_id} to #{new_bundle_id}")
            end
            updated
          rescue StandardError => e
            UI.important("⚠ Failed to update bundle identifier: #{e.message}")
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

      end
    end
  end
end

