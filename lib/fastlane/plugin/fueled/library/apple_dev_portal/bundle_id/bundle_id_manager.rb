# frozen_string_literal: true

require_relative '../../app_store_connect/api'
require 'fastlane_core/ui/ui'

module Fastlane
  module Helper
    module AppleDevPortal
      module BundleId
        module BundleIdManager
          module_function

          # Ensure a bundle ID exists on App Store Connect
          #
          # Params:
          # - key_id, issuer_id, key_content, key_file_path: App Store Connect credentials
          # - bundle_id: String, bundle identifier (e.g., "com.example.app")
          # - name: String, optional name for the bundle ID (auto-generated if not provided)
          # - platform: String, platform (default: "IOS")
          #
          # Returns: Hash with bundle ID info and whether it existed
          def ensure_bundle_id_exists(key_id: nil, issuer_id: nil, key_content: nil, key_file_path: nil, bundle_id:, name: nil, platform: 'IOS')
            # Check if bundle ID already exists
            existing = AppStoreConnect::API.fetch_bundle_ids(
              key_id: key_id,
              issuer_id: issuer_id,
              key_content: key_content,
              key_file_path: key_file_path,
              identifier: bundle_id
            )

            if existing && !existing.empty?
              UI.message("✓ Bundle ID '#{bundle_id}' already exists")
              return {
                existed: true,
                data: existing.first
              }
            end

            # Create bundle ID
            UI.message("Creating bundle ID '#{bundle_id}' on App Store Connect...")
            name ||= AppStoreConnect::API.humanize_bundle_id(bundle_id)
            
            new_bundle_id = AppStoreConnect::API.create_bundle_id(
              key_id: key_id,
              issuer_id: issuer_id,
              key_content: key_content,
              key_file_path: key_file_path,
              identifier: bundle_id,
              name: name,
              platform: platform
            )

            unless new_bundle_id
              UI.user_error!("Failed to create bundle ID '#{bundle_id}'")
            end

            UI.success("✓ Created bundle ID: #{name} (#{bundle_id})")

            {
              existed: false,
              data: new_bundle_id
            }
          end
        end
      end
    end
  end
end

