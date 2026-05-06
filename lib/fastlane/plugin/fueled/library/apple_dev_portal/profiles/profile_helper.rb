# frozen_string_literal: true

require 'plist'
require 'set'
require_relative '../../app_store_connect/api'
require 'fastlane_core/ui/ui'

module Fastlane
  module Helper
    module AppleDevPortal
      module Profiles
        module ProfileHelper
          # Maps Xcode entitlement keys to App Store Connect capability types.
          # When the project requires an entitlement that the App ID doesn't have,
          # the plugin uses this mapping to enable the capability automatically.
          ENTITLEMENT_TO_CAPABILITY = {
            'com.apple.developer.associated-domains' => 'ASSOCIATED_DOMAINS',
            'aps-environment' => 'PUSH_NOTIFICATIONS',
            'com.apple.developer.applesignin' => 'APPLE_ID_AUTH',
            'com.apple.security.application-groups' => 'APP_GROUPS',
            'com.apple.developer.icloud-container-identifiers' => 'ICLOUD',
            'com.apple.developer.icloud-services' => 'ICLOUD',
            'com.apple.developer.default-data-protection' => 'DATA_PROTECTION',
            'com.apple.developer.healthkit' => 'HEALTHKIT',
            'com.apple.developer.healthkit.access' => 'HEALTHKIT',
            'com.apple.developer.homekit' => 'HOMEKIT',
            'com.apple.developer.networking.multipath' => 'MULTIPATH',
            'com.apple.developer.networking.networkextension' => 'NETWORK_EXTENSIONS',
            'com.apple.developer.nfc.readersession.formats' => 'NFC_TAG_READING',
            'com.apple.developer.siri' => 'SIRI',
            'com.apple.developer.pass-type-identifiers' => 'WALLET',
            'com.apple.developer.networking.wifi-info' => 'ACCESS_WIFI_INFORMATION',
            'com.apple.developer.game-center' => 'GAME_CENTER',
            'com.apple.developer.maps' => 'MAPS',
            'com.apple.developer.in-app-payments' => 'APPLE_PAY',
            'com.apple.developer.ClassKit-environment' => 'CLASSKIT',
            'com.apple.developer.networking.HotspotConfiguration' => 'HOT_SPOT',
            'com.apple.developer.usernotifications.communication' => 'USER_MANAGEMENT',
            'com.apple.developer.group-session' => 'GROUP_ACTIVITIES',
          }.freeze

          module_function

          # Sync project entitlements to App Store Connect by enabling
          # any capabilities the project requires but the App ID lacks.
          #
          # Call this before creating a new provisioning profile so the
          # profile will include the correct entitlements.
          def sync_capabilities_to_portal(project_path:, bundle_id_id:, key_id: nil, issuer_id: nil, key_content: nil, key_file_path: nil)
            project_ents = extract_entitlements_from_project(project_path)
            return if project_ents.empty?

            # Determine which capability types the project needs
            needed_types = Set.new
            project_ents.each_key do |entitlement_key|
              capability_type = ENTITLEMENT_TO_CAPABILITY[entitlement_key]
              needed_types << capability_type if capability_type
            end
            return if needed_types.empty?

            # Fetch current capabilities from the portal
            current_capabilities = AppStoreConnect::API.fetch_bundle_id_capabilities(
              key_id: key_id,
              issuer_id: issuer_id,
              key_content: key_content,
              key_file_path: key_file_path,
              bundle_id_id: bundle_id_id
            )
            current_types = Set.new(current_capabilities.map { |c| c.dig('attributes', 'capabilityType') }.compact)

            missing_types = needed_types - current_types
            return if missing_types.empty?

            UI.message("Enabling #{missing_types.length} missing capability(ies) on App ID...")
            missing_types.each do |capability_type|
              begin
                AppStoreConnect::API.enable_bundle_id_capability(
                  key_id: key_id,
                  issuer_id: issuer_id,
                  key_content: key_content,
                  key_file_path: key_file_path,
                  bundle_id_id: bundle_id_id,
                  capability_type: capability_type
                )
                UI.success("  ✓ Enabled #{capability_type}")
              rescue StandardError => e
                UI.important("  ⚠ Could not enable #{capability_type}: #{e.message}")
              end
            end
          end

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

          # Extract entitlements from an installed provisioning profile on disk
          def extract_entitlements_from_profile(profile_uuid)
            return {} unless profile_uuid

            profile_path = File.expand_path("~/Library/MobileDevice/Provisioning Profiles/#{profile_uuid}.mobileprovision")
            return {} unless File.exist?(profile_path)

            extract_entitlements_from_mobileprovision(profile_path)
          end

          # Extract entitlements from raw mobileprovision data (bytes).
          # Writes to a temp file and uses `security cms -D` to decode.
          def extract_entitlements_from_profile_data(raw_data)
            return {} unless raw_data && !raw_data.empty?

            require 'tempfile'

            tmpfile = Tempfile.new(['profile', '.mobileprovision'])
            begin
              tmpfile.binmode
              tmpfile.write(raw_data)
              tmpfile.close

              extract_entitlements_from_mobileprovision(tmpfile.path)
            ensure
              tmpfile.close! rescue nil
            end
          end

          # Extract entitlements from a mobileprovision file at the given path
          def extract_entitlements_from_mobileprovision(path)
            return {} unless path && File.exist?(path)

            begin
              plist_xml = `security cms -D -i "#{path}" 2>/dev/null`
              return {} unless $?.success? && !plist_xml.strip.empty?

              plist = Plist.parse_xml(plist_xml)
              return {} unless plist

              plist['Entitlements'] || {}
            rescue StandardError => e
              UI.important("Could not extract entitlements from profile at #{path}: #{e.message}")
              {}
            end
          end

          # Compare project entitlements against profile entitlements.
          # Returns a mismatch description if the project requires capabilities
          # the profile doesn't provide; nil otherwise.
          # Extra capabilities in the profile are harmless and ignored.
          #
          # When the profile is not on disk (e.g. fresh CI), falls back to
          # downloading profile content from the App Store Connect API if
          # credentials and profile_id are provided.
          def check_entitlements_mismatch(project_path:, profile_uuid:, key_id: nil, issuer_id: nil, key_content: nil, key_file_path: nil, profile_id: nil)
            project_ents = normalize_entitlements(extract_entitlements_from_project(project_path))
            return nil if project_ents.empty?

            profile_ents = normalize_entitlements(extract_entitlements_from_profile(profile_uuid))

            # If profile is not on disk, try downloading from ASC API
            if profile_ents.empty? && profile_id
              UI.message("Profile not found on disk, downloading from App Store Connect to check entitlements...")
              begin
                raw_data = AppStoreConnect::API.download_profile(
                  key_id: key_id,
                  issuer_id: issuer_id,
                  key_content: key_content,
                  key_file_path: key_file_path,
                  profile_id: profile_id
                )
                profile_ents = normalize_entitlements(extract_entitlements_from_profile_data(raw_data))
              rescue StandardError => e
                UI.important("Could not download profile for entitlement check: #{e.message}")
              end
            end

            return nil if profile_ents.empty?

            missing = []
            project_ents.each_key do |key|
              next if profile_ents.key?(key)
              # For aps-environment, presence is what matters — value differs
              # between debug (development) and release (production) builds
              next if key == 'aps-environment' && profile_ents.key?('aps-environment')

              missing << key
            end

            return nil if missing.empty?

            "project requires entitlements missing from profile: #{missing.join(', ')}"
          end
        end
      end
    end
  end
end

