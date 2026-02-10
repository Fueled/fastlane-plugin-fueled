# frozen_string_literal: true

require_relative 'keychain_helper'
require_relative 'storage/certificate_storage'
require 'openssl'
require 'base64'
require 'fastlane_core/ui/ui'

module Fastlane
  module Helper
    module AppleDevPortal
      module Certificates
        module CertificateSelector
          module_function

          # Find the best certificate from a list, prioritizing local ones
          # Priority: 1) In keychain, 2) In encrypted storage, 3) Remote only
          #
          # Params:
          # - certs: Array, list of certificate hashes from API
          # - keychain_name: String, keychain name
          # - project_root: String, project root directory
          #
          # Returns: Hash, best certificate
          def find_best(certs:, keychain_name:, project_root: Dir.pwd)
            return certs.first if certs.empty?

            encryption_key = ENV['CERTIFICATE_ENCRYPTION_KEY']
            issuer_id = ENV['APP_STORE_CONNECT_ISSUER_ID']
            if (encryption_key.nil? || encryption_key.strip.empty?) && issuer_id
              require_relative 'storage/keychain_storage'
              encryption_key = Certificates::Storage::KeychainStorage.retrieve_encryption_key(
                issuer_id: issuer_id,
                keychain_name: keychain_name
              )
            end

            encrypted_metadata = nil
            if encryption_key && !encryption_key.strip.empty?
              encrypted_metadata = Certificates::Storage::CertificateStorage.load_metadata(project_root, certificate_name: 'distribution')
            end

            in_keychain = []
            in_encrypted_storage = []
            remote_only = []

            certs.each do |cert|
              cert_id = cert['id']
              cert_attrs = cert['attributes'] || {}
              cert_sha1 = nil
              
              if cert_attrs['certificateContent']
                cert_sha1 = extract_sha1_from_cert(cert_attrs['certificateContent'])
              end

              if cert_sha1 && Certificates::KeychainHelper.certificate_exists_in_keychain?(cert_sha1, keychain_name)
                in_keychain << cert
                next
              end

              if encrypted_metadata
                if cert_id == encrypted_metadata['id'] || (cert_sha1 && encrypted_metadata['sha1'] == cert_sha1)
                  in_encrypted_storage << cert
                  next
                end
              end

              remote_only << cert
            end
            if !in_keychain.empty?
              UI.verbose("Found #{in_keychain.length} certificate(s) in keychain, using first one")
              return in_keychain.first
            elsif !in_encrypted_storage.empty?
              UI.verbose("Found #{in_encrypted_storage.length} certificate(s) in encrypted storage, using first one")
              return in_encrypted_storage.first
            else
              UI.important("⚠ No certificates found locally. Using remote certificate. " \
                          "Consider running 'ensure_certificates' to install certificates locally.")
              return remote_only.first || certs.first
            end
          end

          # Extract SHA1 from certificate content (base64 encoded DER)
          def extract_sha1_from_cert(cert_content)
            begin
              # Remove whitespace and decode
              der = Base64.decode64(cert_content.gsub(/\s+/, ''))
              cert = OpenSSL::X509::Certificate.new(der)
              OpenSSL::Digest::SHA1.hexdigest(cert.to_der).upcase
            rescue StandardError
              nil
            end
          end
        end
      end
    end
  end
end

