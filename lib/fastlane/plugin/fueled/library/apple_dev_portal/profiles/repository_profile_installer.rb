# frozen_string_literal: true

require 'plist'
require 'fileutils'
require 'time'
require_relative 'profile_downloader'
require_relative '../../xcode/project_detector'
require 'fastlane_core/ui/ui'

module Fastlane
  module Helper
    module AppleDevPortal
      module Profiles
        # Installs a provisioning profile committed in the repository (e.g. an enterprise in-house profile),
        # without calling App Store Connect.
        module RepositoryProfileInstaller
          module_function

          PROFILES_DIR = 'fastlane/profiles'

          # Install a committed provisioning profile and point the Xcode project to it
          #
          # Params:
          # - bundle_id: String, bundle identifier the profile is for
          # - profile_path: String, optional path to the .mobileprovision (default: the only one in fastlane/profiles)
          # - project_path: String, optional path to Xcode project/workspace (auto-detected from bundle_id if not provided)
          # - search_path: String, directory to search for the profile and the Xcode project (default: current directory)
          #
          # Returns: Hash with profile info (same keys as ProfileManager.ensure_profile)
          def install(bundle_id:, profile_path: nil, project_path: nil, search_path: Dir.pwd)
            profile_path ||= default_profile_path(search_path)
            UI.user_error!("Provisioning profile not found at #{profile_path}") unless File.exist?(profile_path)

            profile = parse(profile_path)
            validate(profile, bundle_id: bundle_id, profile_path: profile_path)
            uuid = profile['UUID']
            name = profile['Name']
            team_id = Array(profile['TeamIdentifier']).first

            installed_path = File.join(File.expand_path('~/Library/MobileDevice/Provisioning Profiles'), "#{uuid}.mobileprovision")
            FileUtils.mkdir_p(File.dirname(installed_path))
            FileUtils.cp(profile_path, installed_path)
            UI.success("✓ Installed provisioning profile '#{name}' (UUID: #{uuid})")

            project_path = update_xcode_project(project_path, bundle_id: bundle_id, search_path: search_path, profile_uuid: uuid, team_id: team_id)

            {
              id: nil,
              name: name,
              uuid: uuid,
              type: 'repository',
              project_path: project_path,
              bundle_id: bundle_id,
              team_id: team_id,
              code_sign_identity: nil
            }
          end

          def validate(profile, bundle_id:, profile_path:)
            name = profile['Name']
            expiration = profile['ExpirationDate']
            if expiration && expiration.to_time < Time.now
              UI.user_error!("Provisioning profile '#{name}' expired on #{expiration.to_time.strftime('%Y-%m-%d')}. Replace #{profile_path} with a valid one.")
            end

            application_identifier = profile.dig('Entitlements', 'application-identifier').to_s
            return if application_identifier.end_with?(".#{bundle_id}", '.*')

            UI.important("⚠ Provisioning profile '#{name}' is for '#{application_identifier}', not for '#{bundle_id}'")
          end

          # Returns the project path that was updated, or nil when no project has the bundle id.
          def update_xcode_project(project_path, bundle_id:, search_path:, profile_uuid:, team_id:)
            project_path ||= Xcode::ProjectDetector.find_project_with_bundle_id(bundle_id: bundle_id, search_path: search_path)&.dig(:project_path)
            if project_path
              ProfileDownloader.update_xcode_project(project_path: project_path, bundle_id: bundle_id, profile_uuid: profile_uuid, team_id: team_id)
            else
              UI.important("⚠ Bundle ID '#{bundle_id}' not found in any Xcode project. Skipping Xcode project signing settings update.")
            end
            project_path
          end

          def default_profile_path(search_path)
            profiles = Dir.glob(File.join(search_path, PROFILES_DIR, '*.mobileprovision'))
            UI.user_error!("No provisioning profile found in #{File.join(search_path, PROFILES_DIR)}. Commit one there or set profile_path.") if profiles.empty?
            UI.user_error!("More than one provisioning profile in #{File.join(search_path, PROFILES_DIR)}. Set profile_path to pick one.") if profiles.size > 1

            profiles.first
          end

          # Decode the signed .mobileprovision into its plist.
          def parse(profile_path)
            plist_xml = `security cms -D -i "#{profile_path}" 2>/dev/null`
            plist_xml = extract_plist(File.binread(profile_path)) unless $?.success? && !plist_xml.strip.empty?

            plist = Plist.parse_xml(plist_xml.to_s)
            UI.user_error!("Could not read provisioning profile at #{profile_path}") unless plist && plist['UUID']

            plist
          end

          # The plist is embedded as plain text in the CMS envelope, so it can be read without `security` (e.g. on Linux).
          def extract_plist(raw)
            raw.dup.force_encoding('BINARY')[%r{<\?xml.*</plist>}m]&.force_encoding('UTF-8')
          end
        end
      end
    end
  end
end
