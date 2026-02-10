# frozen_string_literal: true

require 'fileutils'
require 'net/http'
require_relative '../../app_store_connect/api'
require_relative '../bundle_id/bundle_id_manager'
require_relative '../../xcode/project_detector'
require_relative '../../xcode/project_updater'
require_relative 'profile_validator'
require_relative 'profile_downloader'
require_relative 'profile_selector'
require_relative 'profile_helper'
require_relative '../certificates/certificate_selector'
require_relative '../certificates/keychain_manager'
require 'fastlane_core/ui/ui'

module Fastlane
  module Helper
    module AppleDevPortal
      module Profiles
        module ProfileManager
          module_function

          # Update DEVELOPMENT_TEAM in Xcode project file using regex
          #
          # Params:
          # - project_path: String, path to Xcode project
          # - team_id: String, development team ID
          # - bundle_id: String, bundle identifier (for logging)
          #
          # Returns: Boolean, true if updated successfully
          def update_xcode_project_team_id(project_path:, team_id:, bundle_id: nil)
            return false unless project_path && team_id

            begin
              Xcode::ProjectUpdater.update_development_team(
                project_path: project_path,
                team_id: team_id,
                bundle_id: bundle_id
              )
            rescue StandardError => e
              UI.important("⚠ Could not update DEVELOPMENT_TEAM in Xcode project: #{e.message}")
              UI.important("   You may need to manually update DEVELOPMENT_TEAM in your Xcode project settings")
              false
            end
          end

          # Ensure a provisioning profile exists for the given bundle ID
          #
          # Params:
          # - key_id, issuer_id, key_content, key_file_path: App Store Connect credentials
          # - bundle_id: String, bundle identifier (e.g., "com.example.app")
          # - profile_type: String, profile type (e.g., "IOS_APP_STORE", "IOS_APP_ADHOC", "IOS_APP_DEVELOPMENT")
          # - profile_name: String, optional name for the profile (auto-generated if not provided)
          # - certificate_id: String, optional certificate ID (uses distribution cert if not provided)
          # - app_store_connect_app_id: String, optional App Store Connect app ID (for multiple apps with same bundle ID)
          # - project_path: String, optional path to Xcode project/workspace (auto-detected from bundle_id if not provided)
          # - search_path: String, optional directory to search for Xcode projects (default: current directory)
          #
          # Returns: Hash with profile info
          def ensure_profile(key_id: nil, issuer_id: nil, key_content: nil, key_file_path: nil, bundle_id:, profile_type:, profile_name: nil, certificate_id: nil, app_store_connect_app_id: nil, project_path: nil, search_path: Dir.pwd)
            UI.message("Ensuring provisioning profile for bundle ID: #{bundle_id}")

            detected_project = nil
            unless project_path
              UI.message("🔍 Searching for Xcode project with bundle ID: #{bundle_id}")
              detected_project = Xcode::ProjectDetector.find_project_with_bundle_id(
                bundle_id: bundle_id,
                search_path: search_path
              )

              if detected_project
                project_path = detected_project[:project_path]
                UI.message("✓ Found bundle ID in project: #{project_path}")
              else
                UI.user_error!("Bundle ID '#{bundle_id}' not found in any Xcode project. " \
                              "Please ensure the bundle ID matches the PRODUCT_BUNDLE_IDENTIFIER in your Xcode project, " \
                              "or provide project_path parameter.")
              end
            end

            bundle_id_result = BundleId::BundleIdManager.ensure_bundle_id_exists(
              key_id: key_id,
              issuer_id: issuer_id,
              key_content: key_content,
              key_file_path: key_file_path,
              bundle_id: bundle_id
            )

            bundle_id_data = bundle_id_result[:data]
            bundle_id_id = bundle_id_data['id']
            team_id = bundle_id_data.dig('attributes', 'seedId')

            resolved_certificate_id = certificate_id
            unless resolved_certificate_id
              UI.message("Finding distribution certificate...")
              certs = AppStoreConnect::API.fetch_certificates(
                key_id: key_id,
                issuer_id: issuer_id,
                key_content: key_content,
                key_file_path: key_file_path,
                types: ['IOS_DISTRIBUTION']
              )

              if certs.empty?
                UI.user_error!("No distribution certificate found. Please ensure certificates exist first using ensure_certificates action.")
              end

              best_cert = Certificates::CertificateSelector.find_best(
                certs: certs,
                keychain_name: Certificates::KeychainManager.keychain_name,
                project_root: search_path
              )

              resolved_certificate_id = best_cert['id']
              cert_name = best_cert.dig('attributes', 'name')
              UI.message("Using certificate: #{cert_name}")
              
              code_sign_identity = if cert_name.include?('Distribution')
                                     'iPhone Distribution'
                                   elsif cert_name.include?('Development')
                                     'iPhone Developer'
                                   else
                                     nil
                                   end
            end

            resolved_profile_name = profile_name || ProfileHelper.generate_profile_name(bundle_id, profile_type)

            UI.message("Checking for existing provisioning profiles...")
            existing_profiles = AppStoreConnect::API.fetch_profiles(
              key_id: key_id,
              issuer_id: issuer_id,
              key_content: key_content,
              key_file_path: key_file_path,
              bundle_id_id: bundle_id_id,
              profile_type: profile_type
            )
            
            if existing_profiles && !existing_profiles.empty?
              UI.message("✓ Found #{existing_profiles.length} existing profile(s)")
            else
              UI.message("No profiles found in initial search")
            end

            if existing_profiles && !existing_profiles.empty?
              selection_result = ProfileSelector.select_best(
                existing_profiles: existing_profiles,
                bundle_id: bundle_id,
                profile_type: profile_type,
                bundle_id_id: bundle_id_id,
                  key_id: key_id,
                  issuer_id: issuer_id,
                  key_content: key_content,
                key_file_path: key_file_path
              )

              best_profile = selection_result[:best_profile]
              best_profile_valid = selection_result[:best_profile_valid]
              profiles_to_delete = selection_result[:profiles_to_delete]

              if !profiles_to_delete.empty?
                UI.message("Deleting #{profiles_to_delete.length} duplicate/invalid profile(s)...")
                profiles_to_delete.each do |p|
                  old_profile_id = p['id']
                  old_profile_name = p.dig('attributes', 'name') || 'Unknown'
                  UI.message("  Deleting: #{old_profile_name} (ID: #{old_profile_id})")
                  begin
                    AppStoreConnect::API.delete_profile(
                      key_id: key_id,
                      issuer_id: issuer_id,
                      key_content: key_content,
                      key_file_path: key_file_path,
                      profile_id: old_profile_id
                    )
                    UI.success("  ✓ Deleted: #{old_profile_name}")
                  rescue StandardError => e
                    UI.important("  ⚠ Failed to delete #{old_profile_name}: #{e.message}")
                  end
                end
              end

              if best_profile && best_profile_valid
                profile_id = best_profile['id']
                profile_attrs = best_profile['attributes'] || {}
                profile_name_found = profile_attrs['name']
                profile_uuid = profile_attrs['uuid']

                UI.message("✓ Using valid profile: #{profile_name_found} (UUID: #{profile_uuid})")

                ProfileDownloader.download_and_install(
                  key_id: key_id,
                  issuer_id: issuer_id,
                  key_content: key_content,
                  key_file_path: key_file_path,
                  profile_id: profile_id,
                  profile_uuid: profile_uuid,
                  project_path: project_path,
                  bundle_id: bundle_id,
                  team_id: team_id,
                  code_sign_identity: code_sign_identity
                )

                update_xcode_project_team_id(
                  project_path: project_path,
                  team_id: team_id,
                  bundle_id: bundle_id
                )

                return {
                  id: profile_id,
                  name: profile_name_found,
                  uuid: profile_uuid,
                  type: profile_type,
                  project_path: project_path,
                  bundle_id: bundle_id,
                  team_id: team_id,
                  code_sign_identity: code_sign_identity
                }
              elsif !profiles_to_delete.empty?
                UI.message("All existing profiles were invalid and have been deleted. Creating new profile...")
                existing_profiles = []
              end
            end

            UI.message("No existing profile found. Creating new profile: #{resolved_profile_name}")
            
            unless bundle_id_id
              UI.user_error!("Bundle ID ID is required to create a provisioning profile")
            end
            
            unless resolved_certificate_id
              UI.user_error!("Certificate ID is required to create a provisioning profile")
            end
            
            UI.message("Creating profile with bundle ID: #{bundle_id_id}, certificate: #{resolved_certificate_id}")

            begin
              new_profile = AppStoreConnect::API.create_profile(
                key_id: key_id,
                issuer_id: issuer_id,
                key_content: key_content,
                key_file_path: key_file_path,
                name: resolved_profile_name,
                bundle_id_id: bundle_id_id,
                certificate_id: resolved_certificate_id,
                profile_type: profile_type
              )

              unless new_profile
                UI.user_error!("Failed to create provisioning profile")
              end
            rescue StandardError => e
              error_msg = e.message.to_s
              
              if error_msg.include?('Multiple profiles found') || error_msg.include?('duplicate')
                UI.important("⚠ Multiple profiles found for bundle ID '#{bundle_id}' and type '#{profile_type}'. Re-fetching to use existing profile...")
                
                existing_profiles = ProfileSelector.refetch_profiles(
                  bundle_id: bundle_id,
                  profile_type: profile_type,
                  bundle_id_id: bundle_id_id,
                  resolved_profile_name: resolved_profile_name,
                  key_id: key_id,
                  issuer_id: issuer_id,
                  key_content: key_content,
                  key_file_path: key_file_path
                )
                
                if existing_profiles && !existing_profiles.empty?
                  selection_result = ProfileSelector.select_best(
                    existing_profiles: existing_profiles,
                    bundle_id: bundle_id,
                    profile_type: profile_type,
                    bundle_id_id: bundle_id_id,
                    key_id: key_id,
                    issuer_id: issuer_id,
                    key_content: key_content,
                    key_file_path: key_file_path
                  )

                  best_profile = selection_result[:best_profile]
                  best_profile_valid = selection_result[:best_profile_valid]
                  profiles_to_delete = selection_result[:profiles_to_delete]

                  if !profiles_to_delete.empty?
                    UI.message("Deleting #{profiles_to_delete.length} duplicate/invalid profile(s)...")
                    profiles_to_delete.each do |p|
                      old_profile_id = p['id']
                      old_profile_name = p.dig('attributes', 'name') || 'Unknown'
                      begin
                        AppStoreConnect::API.delete_profile(
                          key_id: key_id,
                          issuer_id: issuer_id,
                          key_content: key_content,
                          key_file_path: key_file_path,
                          profile_id: old_profile_id
                        )
                        UI.success("  ✓ Deleted: #{old_profile_name}")
                      rescue StandardError => del_error
                        UI.important("  ⚠ Failed to delete #{old_profile_name}: #{del_error.message}")
                      end
                    end
                  end

                  if best_profile && best_profile_valid
                    profile_id = best_profile['id']
                    profile_attrs = best_profile['attributes'] || {}
                    profile_name_found = profile_attrs['name']
                    profile_uuid = profile_attrs['uuid']
                    
                    UI.message("✓ Using existing profile: #{profile_name_found} (UUID: #{profile_uuid})")
                    
                    ProfileDownloader.download_and_install(
                      key_id: key_id,
                      issuer_id: issuer_id,
                      key_content: key_content,
                      key_file_path: key_file_path,
                      profile_id: profile_id,
                      profile_uuid: profile_uuid,
                      project_path: project_path,
                      bundle_id: bundle_id,
                      team_id: team_id,
                      code_sign_identity: code_sign_identity
                    )
                    
                    update_xcode_project_team_id(
                      project_path: project_path,
                      team_id: team_id,
                      bundle_id: bundle_id
                    )
                    
                    return {
                      id: profile_id,
                      name: profile_name_found,
                      uuid: profile_uuid,
                      type: profile_type,
                      project_path: project_path,
                      bundle_id: bundle_id,
                      team_id: team_id,
                      code_sign_identity: code_sign_identity
                    }
                  else
                    UI.message("All existing profiles were invalid. Creating new profile...")
                  end
                else
                  UI.user_error!("Failed to create profile due to multiple profiles error, but could not find existing profiles. " \
                                "This may be a timing issue. Please try again, or manually check and resolve duplicate profiles in App Store Connect.")
                end
              elsif error_msg.include?('program membership') || error_msg.include?('eligible for this feature')
                UI.user_error!("Failed to create provisioning profile: Your Apple Developer account may not have the required program membership. " \
                              "Original error: #{error_msg}")
              else
                raise
              end
            end

            profile_data_obj = new_profile['data'] || new_profile
            profile_id = profile_data_obj['id']
            profile_attrs = profile_data_obj['attributes'] || {}
            profile_uuid = profile_attrs['uuid']
            profile_name_created = profile_attrs['name']

            UI.success("✓ Created provisioning profile: #{profile_name_created}")

            download_url = new_profile.dig('data', 'links', 'download') ||
                          new_profile.dig('links', 'download') ||
                          profile_data_obj.dig('links', 'download')

            if download_url
              UI.message("Downloading provisioning profile...")
              profile_data = Net::HTTP.get(URI(download_url))
              
              profiles_dir = File.expand_path('~/Library/MobileDevice/Provisioning Profiles')
              FileUtils.mkdir_p(profiles_dir)

              profile_path = File.join(profiles_dir, "#{profile_uuid}.mobileprovision")
              File.binwrite(profile_path, profile_data)

              UI.success("✓ Installed provisioning profile to: #{profile_path}")
            else
              ProfileDownloader.download_and_install(
                key_id: key_id,
                issuer_id: issuer_id,
                key_content: key_content,
                key_file_path: key_file_path,
                profile_id: profile_id,
                profile_uuid: profile_uuid,
                project_path: project_path,
                bundle_id: bundle_id,
                team_id: team_id,
                code_sign_identity: code_sign_identity
              )
            end

            update_xcode_project_team_id(
              project_path: project_path,
              team_id: team_id,
              bundle_id: bundle_id
            )

            {
              id: profile_id,
              name: profile_name_created,
              uuid: profile_uuid,
              type: profile_type,
              project_path: project_path,
              bundle_id: bundle_id,
              team_id: team_id,
              code_sign_identity: code_sign_identity
            }
          end

        end
      end
    end
  end
end

