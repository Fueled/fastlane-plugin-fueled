# frozen_string_literal: true

require_relative '../../app_store_connect/api'
require_relative 'profile_validator'
require 'cgi'
require 'uri'
require 'fastlane_core/ui/ui'

module Fastlane
  module Helper
    module AppleDevPortal
      module Profiles
        module ProfileSelector
          module_function

          # Find and select the best profile from existing profiles
          # Handles validation, duplicate detection, and selection
          #
          # Params:
          # - existing_profiles: Array, list of profile hashes from API
          # - bundle_id: String, bundle identifier
          # - profile_type: String, profile type
          # - bundle_id_id: String, bundle ID ID
          # - key_id, issuer_id, key_content, key_file_path: App Store Connect credentials
          #
          # Returns: Hash with :best_profile, :profiles_to_delete, :best_profile_valid
          def select_best(existing_profiles:, bundle_id:, profile_type:, bundle_id_id:, key_id: nil, issuer_id: nil, key_content: nil, key_file_path: nil)
            return { best_profile: nil, profiles_to_delete: [], best_profile_valid: false } if existing_profiles.empty?

            if existing_profiles.length > 1
              UI.important("⚠ Found #{existing_profiles.length} duplicate profiles for bundle ID '#{bundle_id}' and type '#{profile_type}'.")
              existing_profiles.each_with_index do |p, idx|
                name = p.dig('attributes', 'name') || 'Unknown'
                uuid = p.dig('attributes', 'uuid') || 'Unknown'
                expiration = p.dig('attributes', 'expirationDate') || 'Unknown'
                UI.message("  #{idx + 1}. #{name} (UUID: #{uuid}, Expires: #{expiration})")
              end
              UI.important("Cleaning up duplicates: will keep the most recent valid profile and delete others...")
            end

            best_profile = nil
            best_profile_valid = false
            profiles_to_delete = []

            existing_profiles.each do |p|
              profile_id = p['id']
              profile_attrs = p['attributes'] || {}
              profile_expiration_date = profile_attrs['expirationDate']
              profile_certificate_ids = p.dig('relationships', 'certificates', 'data')&.map { |c| c['id'] } || []

              validation_result = ProfileValidator.validate(
                key_id: key_id,
                issuer_id: issuer_id,
                key_content: key_content,
                key_file_path: key_file_path,
                profile_id: profile_id,
                profile_expiration_date: profile_expiration_date,
                profile_certificate_ids: profile_certificate_ids,
                bundle_id_id: bundle_id_id
              )

              if validation_result[:needs_update]
                profiles_to_delete << p
              else
                if !best_profile || !best_profile_valid
                  best_profile = p
                  best_profile_valid = true
                else
                  profiles_to_delete << p
                end
              end
            end

            if best_profile_valid && existing_profiles.length > 1
              valid_profiles = existing_profiles.reject { |p| profiles_to_delete.include?(p) }
              if valid_profiles.length > 1
                valid_profiles.sort_by! do |p|
                  exp_date = p.dig('attributes', 'expirationDate')
                  exp_date ? Time.parse(exp_date) : Time.at(0)
                end.reverse!
                
                best_profile = valid_profiles.first
                valid_profiles[1..-1].each { |p| profiles_to_delete << p }
              end
            end

            {
              best_profile: best_profile,
              profiles_to_delete: profiles_to_delete,
              best_profile_valid: best_profile_valid
            }
          end

          # Re-fetch profiles when creation fails due to duplicates
          # Tries multiple approaches to find existing profiles
          def refetch_profiles(bundle_id:, profile_type:, bundle_id_id:, resolved_profile_name:, key_id: nil, issuer_id: nil, key_content: nil, key_file_path: nil)
            existing_profiles = nil
            
            begin
              existing_profiles = AppStoreConnect::API.fetch_profiles(
                key_id: key_id,
                issuer_id: issuer_id,
                key_content: key_content,
                key_file_path: key_file_path,
                bundle_id_id: bundle_id_id,
                profile_type: profile_type
              )
            rescue StandardError => fetch_error
              UI.important("⚠ First fetch attempt failed: #{fetch_error.message}")
            end
            
            if existing_profiles.nil? || existing_profiles.empty?
              UI.message("Trying alternative method: fetching all profiles and matching by name...")
              begin
                all_profiles = []
                cursor = nil
                iteration = 0
                
                loop do
                  iteration += 1
                  UI.user_error!('Infinite loop detected in alternative profile fetch') if iteration > 50
                  
                  query = { 'filter[profileType]' => profile_type }
                  query['cursor'] = cursor if cursor
                  query['limit'] = 200
                  query['include'] = 'bundleId'
                  
                  response = AppStoreConnect::API.request(
                    key_id: key_id,
                    issuer_id: issuer_id,
                    key_content: key_content,
                    key_file_path: key_file_path,
                    path: '/profiles',
                    params: query
                  )
                  
                  data = response['data']
                  all_profiles.concat(data) if data
                  
                  next_url = response.dig('links', 'next')
                  break unless next_url
                  
                  uri = URI(next_url)
                  cursor = CGI.parse(uri.query)['cursor']&.first
                  break unless cursor
                end
                
                existing_profiles = all_profiles.select do |profile|
                  profile_name = profile.dig('attributes', 'name') || ''
                  profile_name == resolved_profile_name || 
                  profile_name.include?(bundle_id) ||
                  (profile.dig('relationships', 'bundleId', 'data', 'id') == bundle_id_id)
                end
                
                if existing_profiles && !existing_profiles.empty?
                  UI.message("✓ Found #{existing_profiles.length} profile(s) matching by name: #{resolved_profile_name}")
                else
                  UI.important("⚠ Still no profiles found matching name '#{resolved_profile_name}'.")
                  UI.important("   Waiting 2 seconds and retrying normal fetch...")
                  sleep(2)
                  
                  existing_profiles = AppStoreConnect::API.fetch_profiles(
                    key_id: key_id,
                    issuer_id: issuer_id,
                    key_content: key_content,
                    key_file_path: key_file_path,
                    bundle_id_id: bundle_id_id,
                    profile_type: profile_type
                  )
                end
              rescue StandardError => alt_error
                UI.important("⚠ Alternative fetch also failed: #{alt_error.message}")
              end
            end

            existing_profiles
          end
        end
      end
    end
  end
end

