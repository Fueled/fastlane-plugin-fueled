# frozen_string_literal: true

require 'fileutils'
require_relative '../../app_store_connect/api'
require_relative '../../xcode/project_updater'
require 'fastlane_core/ui/ui'

module Fastlane
  module Helper
    module AppleDevPortal
      module Profiles
        module ProfileDownloader
          module_function

          # Download and install a provisioning profile
          #
          # Params:
          # - key_id, issuer_id, key_content, key_file_path: App Store Connect credentials
          # - profile_id: String, profile ID
          # - profile_uuid: String, profile UUID
          # - project_path: String, optional path to Xcode project/workspace
          # - bundle_id: String, optional bundle identifier
          # - team_id: String, optional development team ID
          # - code_sign_identity: String, optional code signing identity
          #
          # Returns: String, path to installed profile
          def download_and_install(key_id: nil, issuer_id: nil, key_content: nil, key_file_path: nil, profile_id:, profile_uuid:, project_path: nil, bundle_id: nil, team_id: nil, code_sign_identity: nil)
            profiles_dir = File.expand_path('~/Library/MobileDevice/Provisioning Profiles')
            profile_path = File.join(profiles_dir, "#{profile_uuid}.mobileprovision")
            
            if File.exist?(profile_path)
              UI.message("✓ Provisioning profile already exists locally at: #{profile_path}")
              begin
                profile_content = File.read(profile_path)
                if profile_content.include?(profile_uuid) || profile_content.include?('<?xml') || profile_content.include?('<plist')
                  UI.success("✓ Using existing local profile")
                  update_xcode_project(
                    project_path: project_path,
                    bundle_id: bundle_id,
                    profile_uuid: profile_uuid,
                    team_id: team_id,
                    code_sign_identity: code_sign_identity
                  )
                  return profile_path
                else
                  UI.important("⚠ Local profile file exists but appears invalid, will re-download")
                end
              rescue StandardError => e
                UI.important("⚠ Error reading local profile: #{e.message}, will re-download")
              end
            end

            UI.message("Downloading provisioning profile...")

            profile_data = AppStoreConnect::API.download_profile(
              key_id: key_id,
              issuer_id: issuer_id,
              key_content: key_content,
              key_file_path: key_file_path,
              profile_id: profile_id
            )

            FileUtils.mkdir_p(profiles_dir)
            File.binwrite(profile_path, profile_data)

            UI.success("✓ Installed provisioning profile to: #{profile_path}")

            update_xcode_project(
              project_path: project_path,
              bundle_id: bundle_id,
              profile_uuid: profile_uuid,
              team_id: team_id,
              code_sign_identity: code_sign_identity
            )

            profile_path
          end

          private

          def update_xcode_project(project_path:, bundle_id:, profile_uuid:, team_id: nil, code_sign_identity: nil)
            return unless project_path && bundle_id && profile_uuid

            if team_id || code_sign_identity
              Xcode::ProjectUpdater.update_signing_settings(
                project_path: project_path,
                bundle_id: bundle_id,
                team_id: team_id,
                signing_style: 'Manual',
                code_sign_identity: code_sign_identity
              )
            end

            Xcode::ProjectUpdater.update_provisioning_profile(
              project_path: project_path,
              bundle_id: bundle_id,
              profile_uuid: profile_uuid
            )
          end

          module_function :update_xcode_project
        end
      end
    end
  end
end

