# frozen_string_literal: true

require 'plist'
require 'fastlane_core/ui/ui'

module Fastlane
  module Helper
    module AppleDevPortal
      module Profiles
        module ProfileHelper
          module_function

          # Generate a profile name based on bundle ID and type
          def generate_profile_name(bundle_id, profile_type)
            type_suffix = case profile_type
                          when 'IOS_APP_STORE'
                            'App Store'
                          when 'IOS_APP_ADHOC'
                            'Ad Hoc'
                          when 'IOS_APP_DEVELOPMENT'
                            'Development'
                          else
                            profile_type
                          end

            "#{bundle_id} #{type_suffix}"
          end

          # Extract entitlements from Xcode project
          def extract_entitlements_from_project(project_path)
            return {} unless project_path

            # Find .entitlements file in project
            project_dir = File.dirname(project_path)
            entitlements_files = Dir.glob(File.join(project_dir, '**', '*.entitlements'))

            # Try to find entitlements file for the main target
            # Usually named like "App.entitlements" or "App-Debug.entitlements"
            entitlements_file = entitlements_files.first

            if entitlements_file && File.exist?(entitlements_file)
              begin
                entitlements_plist = Plist.parse_xml(entitlements_file)
                return entitlements_plist || {}
              rescue StandardError => e
                UI.important("⚠ Could not parse entitlements file #{entitlements_file}: #{e.message}")
              end
            end

            {}
          end

          # Normalize entitlements for comparison (convert to simple hash, sort keys)
          def normalize_entitlements(entitlements)
            normalized = {}
            entitlements.each do |key, value|
              # Only include capability-related keys (those starting with com.apple.developer)
              # or common entitlement keys
              if key.start_with?('com.apple.developer.') || 
                 key.start_with?('aps-environment') ||
                 key.start_with?('get-task-allow') ||
                 key.start_with?('keychain-access-groups')
                normalized[key] = value
              end
            end
            normalized
          end
        end
      end
    end
  end
end

