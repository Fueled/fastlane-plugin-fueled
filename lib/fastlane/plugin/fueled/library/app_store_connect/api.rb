# frozen_string_literal: true

require 'cgi'
require 'json'
require 'net/http'
require 'uri'
require_relative 'jwt_generator'
require_relative 'credentials'
require 'fastlane_core/ui/ui'

module Fastlane
  module Helper
    module AppStoreConnect
      module API
        module_function

        BASE_URL = 'https://api.appstoreconnect.apple.com/v1'

        # ---------------------------------------------
        # Generic Request Handler
        # ---------------------------------------------
        def request(key_id: nil, issuer_id: nil, key_content: nil, key_file_path: nil, path:, method: :get, params: nil, body: nil)
          credentials = Credentials.get(
            key_id: key_id,
            issuer_id: issuer_id,
            key_content: key_content,
            key_file_path: key_file_path
          )

          jwt = JWTGenerator.generate(
            p8_content: credentials['p8'],
            key_id: credentials['key_id'],
            issuer_id: credentials['issuer_id']
          )

          uri = URI("#{BASE_URL}#{path}")
          uri.query = URI.encode_www_form(params) if params

          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          # forces Ruby to use the correct CA store
          http.ca_file = OpenSSL::X509::DEFAULT_CERT_FILE
          http.ca_path = OpenSSL::X509::DEFAULT_CERT_DIR
          http.verify_mode = OpenSSL::SSL::VERIFY_PEER

          req = build_request(method, uri)
          req['Authorization'] = "Bearer #{jwt}"
          req['Content-Type'] = 'application/json' if body
          req.body = body.to_json if body

          response = http.request(req)

          # DELETE requests may return 204 No Content with empty body
          if method == :delete && (response.code == '204' || response.body.nil? || response.body.strip.empty?)
            return {} if response.code.to_i < 400
            UI.user_error!("[ASC ERROR] Delete request failed with status #{response.code}")
          end

          json = begin
            JSON.parse(response.body)
          rescue StandardError
            {}
          end

          if json['errors']
            error_messages = json['errors'].map { |e| e['detail'] }.join(', ')
            UI.user_error!("[ASC ERROR] #{error_messages}")
          end

          json
        end

        def build_request(method, uri)
          case method
          when :get then Net::HTTP::Get.new(uri)
          when :post then Net::HTTP::Post.new(uri)
          when :patch then Net::HTTP::Patch.new(uri)
          when :delete then Net::HTTP::Delete.new(uri)
          else
            UI.user_error!("Unsupported HTTP method: #{method}")
          end
        end

        # ---------------------------------------------
        # Bundle IDs
        # ---------------------------------------------
        def fetch_bundle_ids(key_id: nil, issuer_id: nil, key_content: nil, key_file_path: nil, identifier: nil)
          params = {}
          params['filter[identifier]'] = identifier if identifier

          results = []
          cursor = nil
          iteration = 0

          loop do
            iteration += 1
            UI.user_error!('Infinite loop detected in fetch_bundle_ids') if iteration > 50

            query = params.dup
            query['cursor'] = cursor if cursor
            query['limit'] = 200

            response = request(
              key_id: key_id,
              issuer_id: issuer_id,
              key_content: key_content,
              key_file_path: key_file_path,
              path: '/bundleIds',
              params: query
            )

            data = response['data']
            results.concat(data) if data

            next_url = response.dig('links', 'next')
            break unless next_url

            uri = URI(next_url)
            cursor = CGI.parse(uri.query)['cursor']&.first
            break unless cursor
          end

          results
        end

        # Fetch a specific bundle ID with its capabilities
        def fetch_bundle_id(key_id: nil, issuer_id: nil, key_content: nil, key_file_path: nil, bundle_id_id:)
          response = request(
            key_id: key_id,
            issuer_id: issuer_id,
            key_content: key_content,
            key_file_path: key_file_path,
            path: "/bundleIds/#{bundle_id_id}",
            params: { 'include' => 'capabilities' }
          )

          response['data']
        end

        def create_bundle_id(key_id: nil, issuer_id: nil, key_content: nil, key_file_path: nil, identifier:, name: nil, platform: 'IOS')
          name ||= humanize_bundle_id(identifier)
          
          body = {
            data: {
              type: 'bundleIds',
              attributes: {
                identifier: identifier,
                name: name,
                platform: platform
              }
            }
          }

          response = request(
            key_id: key_id,
            issuer_id: issuer_id,
            key_content: key_content,
            key_file_path: key_file_path,
            path: '/bundleIds',
            method: :post,
            body: body
          )

          response['data']
        end

        def humanize_bundle_id(bundle_id)
          last = bundle_id.split('.').last || bundle_id
          last.split(/[-_]/).map(&:capitalize).join(' ')
        end

        # ---------------------------------------------
        # Certificates
        # ---------------------------------------------
        # Fetch certificates from App Store Connect
        #
        # Params:
        # - key_id, issuer_id, key_content, key_file_path: Credentials (see Credentials.get)
        # - types: Array, the certificate types to fetch (e.g. ["IOS_DEVELOPMENT", "IOS_DISTRIBUTION"])
        #
        # Returns: Array, the certificates
        # [
        #   { id: "...", type: "...", attributes: { ... } },
        # ]
        # Example:
        # fetch_certificates(types: %w[IOS_DEVELOPMENT IOS_DISTRIBUTION])
        # fetch_certificates(types: %w[IOS_DEVELOPMENT])
        # fetch_certificates(types: %w[IOS_DISTRIBUTION])
        # fetch_certificates() # defaults to IOS_DEVELOPMENT and IOS_DISTRIBUTION
        def fetch_certificates(key_id: nil, issuer_id: nil, key_content: nil, key_file_path: nil, types: %w[IOS_DEVELOPMENT IOS_DISTRIBUTION])
          params = {}
          params['filter[certificateType]'] = Array(types).join(',') if types

          results = []
          cursor = nil
          iteration = 0

          loop do
            iteration += 1
            UI.user_error!('Infinite loop detected in fetch_certificates') if iteration > 50

            query = params.dup
            query['cursor'] = cursor if cursor
            query['limit'] = 200

            response = request(
              key_id: key_id,
              issuer_id: issuer_id,
              key_content: key_content,
              key_file_path: key_file_path,
              path: '/certificates',
              params: query
            )

            data = response['data']
            results.concat(data) if data

            next_url = response.dig('links', 'next')
            break unless next_url

            uri = URI(next_url)
            cursor = CGI.parse(uri.query)['cursor']&.first
            break unless cursor
          end

          results
        end

        # Create a new certificate
        #
        # Params:
        # - key_id, issuer_id, key_content, key_file_path: Credentials (see Credentials.get)
        # - csr_content: String, the CSR content
        # - certificate_type: String, the certificate type (e.g. "IOS_DEVELOPMENT", "IOS_DISTRIBUTION")
        #
        # Returns: Hash, the certificate data
        def create_certificate(key_id: nil, issuer_id: nil, key_content: nil, key_file_path: nil, csr_content:, certificate_type:)
          body = {
            data: {
              type: 'certificates',
              attributes: {
                certificateType: certificate_type,
                csrContent: csr_content,
              },
            },
          }

          response = request(
            key_id: key_id,
            issuer_id: issuer_id,
            key_content: key_content,
            key_file_path: key_file_path,
            method: :post,
            path: '/certificates',
            body: body
          )

          response['data']
        end

        # Delete a certificate
        #
        # Params:
        # - key_id, issuer_id, key_content, key_file_path: Credentials (see Credentials.get)
        # - id: String, the certificate ID
        #
        # Returns: Boolean, true if the certificate was deleted
        def delete_certificate(key_id: nil, issuer_id: nil, key_content: nil, key_file_path: nil, id:)
          request(
            key_id: key_id,
            issuer_id: issuer_id,
            key_content: key_content,
            key_file_path: key_file_path,
            method: :delete,
            path: "/certificates/#{id}"
          )

          true
        end

        # ---------------------------------------------
        # Provisioning Profiles
        # ---------------------------------------------
        def fetch_profiles(key_id: nil, issuer_id: nil, key_content: nil, key_file_path: nil, bundle_id_id:, profile_type:)
          # Try with bundleId filter first (as per working code)
          # Use raw request to check for errors before UI.user_error! is called
          credentials = Credentials.get(
            key_id: key_id,
            issuer_id: issuer_id,
            key_content: key_content,
            key_file_path: key_file_path
          )

          jwt = JWTGenerator.generate(
            p8_content: credentials['p8'],
            key_id: credentials['key_id'],
            issuer_id: credentials['issuer_id']
          )

          uri = URI("#{BASE_URL}/profiles")
          uri.query = URI.encode_www_form({
            'filter[bundleId]' => bundle_id_id,
            'filter[profileType]' => profile_type,
          })

          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          http.ca_file = OpenSSL::X509::DEFAULT_CERT_FILE
          http.ca_path = OpenSSL::X509::DEFAULT_CERT_DIR
          http.verify_mode = OpenSSL::SSL::VERIFY_PEER

          req = Net::HTTP::Get.new(uri)
          req['Authorization'] = "Bearer #{jwt}"

          response = http.request(req)
          json = begin
            JSON.parse(response.body)
          rescue StandardError
            {}
          end

          # Check if there's a filter error
          if json['errors']
            error_messages = json['errors'].map { |e| e['detail'] }.join(', ')
            if error_messages.include?('not a valid filter') || error_messages.include?('bundleId') || error_messages.include?('bundleIds')
              # Fallback: fetch all profiles and filter client-side
              UI.important("⚠ Bundle ID filter not supported, fetching all profiles and filtering client-side...")
              
              all_profiles = []
              cursor = nil
              iteration = 0
              
              loop do
                iteration += 1
                UI.user_error!('Infinite loop detected in fetch_profiles') if iteration > 50
                
                query = { 
                  'filter[profileType]' => profile_type,
                  'include' => 'bundleId'  # Include bundleId relationship for filtering
                }
                query['cursor'] = cursor if cursor
                query['limit'] = 200
                
                response = request(
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
              
              # Filter by bundle ID client-side
              # Try multiple ways to access the bundle ID relationship
              filtered = []
              
              all_profiles.each do |profile|
                profile_id = profile['id']
                profile_name = profile.dig('attributes', 'name') || 'Unknown'
                
                # Try to get bundle ID from relationship
                bundle_id_in_profile = profile.dig('relationships', 'bundleId', 'data', 'id')
                
                # If not found in relationship, try fetching the profile individually to get full relationship data
                if bundle_id_in_profile.nil?
                  begin
                    profile_detail = request(
                      key_id: key_id,
                      issuer_id: issuer_id,
                      key_content: key_content,
                      key_file_path: key_file_path,
                      path: "/profiles/#{profile_id}",
                      params: { 'include' => 'bundleId' }
                    )
                    
                    bundle_id_in_profile = profile_detail.dig('data', 'relationships', 'bundleId', 'data', 'id')
                  rescue StandardError => e
                    UI.verbose("Could not fetch profile detail for #{profile_name}: #{e.message}")
                  end
                end
                
                matches = bundle_id_in_profile == bundle_id_id
                
                if matches
                  filtered << profile
                elsif UI.verbose?
                  UI.verbose("Profile '#{profile_name}' (ID: #{profile_id}) has bundle ID: #{bundle_id_in_profile.inspect}, looking for: #{bundle_id_id}")
                end
              end
              
              if filtered.empty? && !all_profiles.empty?
                UI.important("⚠ Client-side filtering found 0 profiles matching bundle ID #{bundle_id_id}, but #{all_profiles.length} profiles of type #{profile_type} exist.")
                profile_names = all_profiles.map { |p| p.dig('attributes', 'name') }.compact
                if !profile_names.empty?
                  UI.important("   Profile names found: #{profile_names.join(', ')}")
                  UI.important("   Trying to match by profile name instead...")
                  
                  # Fallback: if we can't match by bundle ID, at least return profiles that might match by name pattern
                  # This is a workaround for when relationship data is missing
                  name_filtered = all_profiles.select do |p|
                    name = p.dig('attributes', 'name') || ''
                    # Check if name contains the bundle ID (common pattern: "bundle.id App Store")
                    name.include?(bundle_id_id.split('.').last) || name.include?(bundle_id_id)
                  end
                  
                  if !name_filtered.empty?
                    UI.important("   Found #{name_filtered.length} profile(s) that might match by name. Using first one.")
                    return name_filtered
                  end
                end
              end
              
              return filtered
            else
              # Other errors - raise normally
              error_messages = json['errors'].map { |e| e['detail'] }.join(', ')
              UI.user_error!("[ASC ERROR] #{error_messages}")
            end
          end

          json['data'] || []
        end

        # Create new provisioning profile
        def create_profile(key_id: nil, issuer_id: nil, key_content: nil, key_file_path: nil, name:, bundle_id_id:, certificate_id:, profile_type:)
          body = {
            data: {
              type: 'profiles',
              attributes: {
                name: name,
                profileType: profile_type,
              },
              relationships: {
                bundleId: {
                  data: {
                    type: 'bundleIds',
                    id: bundle_id_id,
                  },
                },
                certificates: {
                  data: [
                    {
                      type: 'certificates',
                      id: certificate_id,
                    },
                  ],
                },
              },
            },
          }

          response = request(
            key_id: key_id,
            issuer_id: issuer_id,
            key_content: key_content,
            key_file_path: key_file_path,
            method: :post,
            path: '/profiles',
            body: body
          )

          # Return the full response structure (data + links if available)
          response
        end

        # Delete a provisioning profile
        #
        # Params:
        # - key_id, issuer_id, key_content, key_file_path: Credentials (see Credentials.get)
        # - profile_id: String, the profile ID
        #
        # Returns: Boolean, true if the profile was deleted
        def delete_profile(key_id: nil, issuer_id: nil, key_content: nil, key_file_path: nil, profile_id:)
          request(
            key_id: key_id,
            issuer_id: issuer_id,
            key_content: key_content,
            key_file_path: key_file_path,
            method: :delete,
            path: "/profiles/#{profile_id}"
          )

          true
        end

        # Download the mobileprovision file
        # Uses the App Store Connect API profileContent field which contains the base64-encoded profile
        def download_profile(key_id: nil, issuer_id: nil, key_content: nil, key_file_path: nil, profile_id:)
          # Retry multiple times in case the profile needs a moment to be ready
          # Profiles can take 5-60 seconds to be fully processed after creation
          max_retries = 8
          retry_delay = 2
          max_retry_delay = 30 # Cap the delay to prevent excessive waiting
          
          max_retries.times do |attempt|
            UI.message("Attempt #{attempt + 1}/#{max_retries}: Fetching profile with profileContent...")
            
            begin
              # Request profile with profileContent field as per App Store Connect API documentation
              # GET /v1/profiles/{id}?fields[profiles]=profileContent
            res = request(
              key_id: key_id,
              issuer_id: issuer_id,
              key_content: key_content,
              key_file_path: key_file_path,
                path: "/profiles/#{profile_id}",
                params: { 'fields[profiles]' => 'profileContent' }
              )

              profile_data = res.dig('data') || {}
              profile_attrs = profile_data['attributes'] || {}
              profile_content = profile_attrs['profileContent']
              
              if profile_content && !profile_content.strip.empty?
                UI.message("Found profileContent, decoding...")
                begin
                  require 'base64'
                  decoded = Base64.decode64(profile_content.gsub(/\s+/, ''))
                  
                  # Validate it's a mobileprovision file
                  if decoded.include?('<?xml') || decoded.include?('<!DOCTYPE plist') || decoded.include?('<plist')
                    UI.success("✓ Successfully decoded profile from profileContent (size: #{decoded.length} bytes)")
                    return decoded
                  else
                    UI.important("⚠ profileContent decoded but doesn't look like a valid mobileprovision file")
                    UI.verbose("First 200 chars: #{decoded[0..200].inspect}")
                  end
                rescue StandardError => e
                  UI.important("⚠ Failed to decode profileContent: #{e.message}")
                  UI.verbose("Error class: #{e.class}")
                end
              else
                UI.verbose("No profileContent in response (may not be ready yet)")
                if attempt < max_retries - 1
                  UI.important("Profile not ready yet, waiting #{retry_delay} second(s) before retry...")
                  sleep(retry_delay)
                  retry_delay = [retry_delay * 2, max_retry_delay].min # Exponential backoff with cap
                end
              end
            rescue StandardError => e
              UI.important("⚠ Failed to fetch profile: #{e.message}")
            if attempt < max_retries - 1
                UI.important("Waiting #{retry_delay} second(s) before retry...")
              sleep(retry_delay)
                retry_delay = [retry_delay * 2, max_retry_delay].min
              end
            end
          end

          # If we get here, all retries failed
          UI.user_error!("Cannot download profile: profileContent not available after #{max_retries} attempts. " \
                        "Profile ID: #{profile_id}. " \
                        "The profile may need more time to be fully processed, or there may be an API issue.")
        end

        # ---------------------------------------------
        # Users
        # ---------------------------------------------
        # Fetch the team ID for a specific bundle ID
        #
        # Params:
        # - key_id, issuer_id, key_content, key_file_path: Credentials (see Credentials.get)
        # - bundle_id: String, the bundle identifier (e.g., "com.example.app")
        #
        # Returns: String, the team ID (10-character alphanumeric), or nil if not found
        #
        # Note: The team ID is found in the seedId attribute of bundle IDs.
        def fetch_team_id_by_bundle_id(key_id: nil, issuer_id: nil, key_content: nil, key_file_path: nil, bundle_id:)
          # Fetch the specific bundle ID
          bundle_ids = fetch_bundle_ids(
            key_id: key_id,
            issuer_id: issuer_id,
            key_content: key_content,
            key_file_path: key_file_path,
            identifier: bundle_id
          )

          return nil if bundle_ids.empty?

          # Extract team ID from the seedId attribute
          bundle_id_data = bundle_ids.first
          team_id = bundle_id_data.dig('attributes', 'seedId')

          return team_id if team_id

          nil
        end

        # Fetch the team ID for the given account (legacy method for backward compatibility)
        #
        # Params:
        # - key_id, issuer_id, key_content, key_file_path: Credentials (see Credentials.get)
        #
        # Returns: String, the team ID (10-character alphanumeric), or nil if not found
        #
        # Note: This method fetches the first available bundle ID's team ID.
        # For more accurate results, use fetch_team_id_by_bundle_id with a specific bundle ID.
        def fetch_team_id(key_id: nil, issuer_id: nil, key_content: nil, key_file_path: nil)
          # Fetch bundle IDs - the team ID is in the seedId attribute
          bundle_ids = fetch_bundle_ids(
            key_id: key_id,
            issuer_id: issuer_id,
            key_content: key_content,
            key_file_path: key_file_path
          )

          return nil if bundle_ids.empty?

          # Extract team ID from the seedId attribute of the first bundle ID
          first_bundle_id = bundle_ids.first
          team_id = first_bundle_id.dig('attributes', 'seedId')

          return team_id if team_id

          nil
        end
      end
    end
  end
end

