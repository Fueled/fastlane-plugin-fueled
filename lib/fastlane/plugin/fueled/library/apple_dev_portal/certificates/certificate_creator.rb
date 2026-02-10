# frozen_string_literal: true

require 'openssl'
require 'base64'
require 'tempfile'
require 'securerandom'
require 'time'
require_relative '../../app_store_connect/api'
require_relative 'csr_generator'
require_relative 'storage/certificate_storage'
require_relative 'storage/keychain_storage'
require_relative 'keychain_helper'
require 'fastlane_core/ui/ui'
require 'fastlane_core/helper'

module Fastlane
  module Helper
    module AppleDevPortal
      module Certificates
        module CertificateCreator
          module_function

          # Create a new distribution certificate
          def create_new_distribution_certificate(key_id: nil, issuer_id: nil, key_content: nil, key_file_path: nil, keychain_name: "login", keychain_password: "", project_root: Dir.pwd, encryption_key: nil, certificate_name: 'distribution')
            unless encryption_key && !encryption_key.strip.empty?
              encryption_key = SecureRandom.base64(32)
              UI.message("Generated new encryption key for certificate storage")
              
              if issuer_id && FastlaneCore::Helper.mac?
                Storage::KeychainStorage.store_encryption_key(encryption_key, issuer_id: issuer_id, keychain_name: keychain_name)
              end
              
              UI.important("")
              UI.important("⚠ IMPORTANT: Encryption key generated and stored in keychain")
              UI.important("   To retrieve it for CI/CD, run:")
              UI.important("   bundle exec fastlane run get_certificate_encryption_key")
              UI.important("")
            end
            
            UI.message("📝 Step 1: Generating Certificate Signing Request")
            csr_data = CSRGenerator.generate_distribution
            UI.success("✓ CSR generated successfully")

            UI.message("☁️  Step 2: Creating Certificate on App Store Connect")

            asc_cert = AppStoreConnect::API.create_certificate(
              key_id: key_id,
              issuer_id: issuer_id,
              key_content: key_content,
              key_file_path: key_file_path,
              csr_content: csr_data[:csr_pem],
              certificate_type: 'IOS_DISTRIBUTION'
            )

            unless asc_cert
              UI.user_error!("Failed to create certificate: App Store Connect returned no certificate")
            end

            attributes = asc_cert['attributes'] || {}
            name = attributes['name']
            exp = attributes['expirationDate']
            content64 = attributes['certificateContent']

            unless content64
              UI.user_error!("Failed to create certificate: App Store Connect certificate missing content")
            end

            UI.success("✓ Certificate created on App Store Connect")

            UI.message("📦 Step 3: Building PKCS12 Package")

            content64_clean = content64.gsub(/\s+/, '')
            der = Base64.decode64(content64_clean)
            cert = OpenSSL::X509::Certificate.new(der)
            private_key = OpenSSL::PKey::RSA.new(csr_data[:private_key_pem])

            p12_password = 'fastlane'
            pkcs12 = OpenSSL::PKCS12.create(
              p12_password,
              'Fastlane Distribution',
              private_key,
              cert
            )

            plain_bytes = pkcs12.to_der
            sha1 = OpenSSL::Digest::SHA1.hexdigest(cert.to_der).upcase
            UI.success("✓ PKCS12 package built successfully")

            if encryption_key
              UI.message("🔐 Step 4: Encrypting and Storing Certificate")
              metadata = {
                'sha1' => sha1,
                'common_name' => name,
                'expires_at' => exp,
                'created_at' => Time.now.utc.iso8601,
                'id' => asc_cert['id']
              }
              
              begin
                Storage::CertificateStorage.save_encrypted(
                  plain_bytes,
                  metadata,
                  project_root,
                  encryption_key,
                  certificate_name: certificate_name
                )
                UI.success("✓ Saved encrypted certificate to fastlane/certificates/#{certificate_name}.p12.enc")
                
                if issuer_id
                  Storage::KeychainStorage.store_encryption_key(encryption_key, issuer_id: issuer_id, keychain_name: keychain_name)
                end
              rescue StandardError => e
                UI.important("⚠ Failed to save encrypted certificate: #{e.message}")
                UI.important("⚠ Certificate will only be in keychain")
              end
            else
              UI.important("⚠ CERTIFICATE_ENCRYPTION_KEY not set - certificate will not be saved to encrypted storage")
              UI.important("⚠ Set CERTIFICATE_ENCRYPTION_KEY environment variable to enable encrypted storage")
            end

            UI.message("🔑 Step 5: Installing Certificate to Keychain")
            Tempfile.create(['distribution', '.p12']) do |f|
              f.binmode
              f.write(plain_bytes)
              f.flush
              f.close

              begin
                test_p12 = OpenSSL::PKCS12.new(File.binread(f.path), p12_password)
                UI.message("✓ Verified p12 file is valid")
              rescue OpenSSL::PKCS12::PKCS12Error => e
                UI.user_error!("Failed to verify p12 file: #{e.message}. This indicates a problem with the p12 creation.")
              end

              UI.message("Importing certificate to keychain...")
              KeychainHelper.import_certificate_to_keychain(f.path, p12_password, keychain_name, keychain_password)
            end

            UI.success("✓ Certificate installed to keychain")
            UI.success("✓ Created and installed distribution certificate: #{name}")

            {
              id: asc_cert['id'],
              name: name,
              expires: exp,
              sha1: sha1
            }
          end
        end
      end
    end
  end
end

