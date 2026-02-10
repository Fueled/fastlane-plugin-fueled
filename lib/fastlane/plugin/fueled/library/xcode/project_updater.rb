# frozen_string_literal: true

require_relative 'signing_updater'
require_relative 'provisioning_updater'
require_relative 'project_detector'
require 'fastlane_core/ui/ui'

module Fastlane
  module Helper
    module Xcode
      module ProjectUpdater
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
          ProvisioningUpdater.update_provisioning_profile(
            project_path: project_path,
            bundle_id: bundle_id,
            profile_uuid: profile_uuid,
            profile_specifier: profile_specifier
          )
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
          ProvisioningUpdater.update_bundle_id(
            project_path: project_path,
            old_bundle_id: old_bundle_id,
            new_bundle_id: new_bundle_id
          )
        end

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
          SigningUpdater.update_signing_settings(
            project_path: project_path,
            bundle_id: bundle_id,
            team_id: team_id,
            signing_style: signing_style,
            code_sign_identity: code_sign_identity
          )
        end

        # Update Xcode project provisioning profile using info from lane context
        # This is a convenience method that reads PROVISIONING_PROFILE_INFO from lane context
        # and updates the Xcode project accordingly. Useful after build tools modify the project.
        #
        # Params:
        # - bundle_id: String, optional bundle identifier (uses PROVISIONING_PROFILE_INFO from lane context if not provided)
        #
        # Returns: Boolean, true if update was successful
        def update_provisioning_profile_from_lane_context(bundle_id: nil)
          require 'fastlane'

          profile_info = Fastlane::Actions.lane_context[Fastlane::Actions::SharedValues::PROVISIONING_PROFILE_INFO]
          unless profile_info && profile_info[:uuid]
            UI.user_error!("No provisioning profile info found in lane context. Please run ensure_provisioning_profiles first.")
          end

          project_path = File.expand_path(profile_info[:project_path]) unless File.absolute_path?(profile_info[:project_path])
          bundle_id = bundle_id || profile_info[:bundle_id]
          profile_uuid = profile_info[:uuid]
          team_id = profile_info[:team_id]
          code_sign_identity = profile_info[:code_sign_identity]

          unless project_path && bundle_id && profile_uuid
            UI.user_error!("Missing required information in PROVISIONING_PROFILE_INFO. Please run ensure_provisioning_profiles first.")
          end

          UI.message("Updating Xcode project signing settings...")

          if team_id || code_sign_identity
            update_signing_settings(
              project_path: project_path,
              bundle_id: bundle_id,
              team_id: team_id,
              signing_style: 'Manual',
              code_sign_identity: code_sign_identity
            )
          end

          update_provisioning_profile(
            project_path: project_path,
            bundle_id: bundle_id,
            profile_uuid: profile_uuid
          )

          SigningUpdater.update_provisioning_profile_uuid(
            project_path: project_path,
            profile_uuid: profile_uuid,
            bundle_id: bundle_id
          )

          if team_id
            update_development_team(
              project_path: project_path,
              team_id: team_id,
              bundle_id: bundle_id
            )
          end

          SigningUpdater.remove_provisioning_profile_specifier(
            project_path: project_path,
            bundle_id: bundle_id
          )

          true
        end

        # Update DEVELOPMENT_TEAM in Xcode project file using regex
        #
        # Params:
        # - project_path: path to .xcodeproj or .xcworkspace
        # - team_id: String, development team ID to set
        # - bundle_id: String, optional bundle identifier (for logging)
        #
        # Returns: Boolean, true if updated successfully
        def update_development_team(project_path:, team_id:, bundle_id: nil)
          SigningUpdater.update_development_team(
            project_path: project_path,
            team_id: team_id,
            bundle_id: bundle_id
          )
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
          SigningUpdater.update_development_team_for_bundle_id(
            bundle_id: bundle_id,
            team_id: team_id,
            search_path: search_path
          )
        end
      end
    end
  end
end

