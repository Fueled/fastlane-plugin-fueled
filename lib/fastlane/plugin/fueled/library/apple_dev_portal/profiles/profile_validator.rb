# frozen_string_literal: true

require_relative '../../app_store_connect/api'
require 'fastlane_core/ui/ui'

module Fastlane
  module Helper
    module AppleDevPortal
      module Profiles
        module ProfileValidator
          module_function

          # Validate profile: check expiry, certificate validity, and capabilities
          #
          # Params:
          # - key_id, issuer_id, key_content, key_file_path: App Store Connect credentials
          # - profile_id: String, profile ID
          # - profile_expiration_date: String, expiration date
          # - profile_certificate_ids: Array, certificate IDs in the profile
          # - bundle_id_id: String, bundle ID ID
          #
          # Returns: Hash with :needs_update (Boolean) and :reason (String)
          def validate(key_id: nil, issuer_id: nil, key_content: nil, key_file_path: nil, profile_id:, profile_expiration_date:, profile_certificate_ids:, bundle_id_id:)
            reasons = []

            if profile_expiration_date
              expiration = Time.parse(profile_expiration_date)
              days_until_expiry = (expiration - Time.now) / (24 * 60 * 60)
              
              if days_until_expiry < 0
                reasons << "profile expired #{days_until_expiry.abs.to_i} days ago"
              elsif days_until_expiry < 30
                reasons << "profile expires in #{days_until_expiry.to_i} days"
              end
            end

            if profile_certificate_ids && !profile_certificate_ids.empty?
              profile_certificate_ids.each do |cert_id|
                cert_valid = check_certificate_validity(
                  key_id: key_id,
                  issuer_id: issuer_id,
                  key_content: key_content,
                  key_file_path: key_file_path,
                  certificate_id: cert_id
                )
                unless cert_valid
                  reasons << "certificate #{cert_id} is invalid or expired"
                end
              end
            end

            {
              needs_update: !reasons.empty?,
              reason: reasons.join(', ')
            }
          end

          # Check if certificate is valid (not expired, not revoked)
          def check_certificate_validity(key_id: nil, issuer_id: nil, key_content: nil, key_file_path: nil, certificate_id:)
            certs = AppStoreConnect::API.fetch_certificates(
              key_id: key_id,
              issuer_id: issuer_id,
              key_content: key_content,
              key_file_path: key_file_path,
              types: ['IOS_DEVELOPMENT', 'IOS_DISTRIBUTION']
            )

            cert = certs.find { |c| c['id'] == certificate_id }
            return false unless cert

            expiration_date = cert.dig('attributes', 'expirationDate')
            if expiration_date
              expiration = Time.parse(expiration_date)
              return false if expiration < Time.now
            end

            true
          end
        end
      end
    end
  end
end

