# frozen_string_literal: true

require 'openssl'
require 'base64'
require 'tempfile'
require 'time'
require_relative '../../app_store_connect/api'
require_relative 'storage/certificate_storage'
require_relative 'storage/keychain_storage'
require_relative 'keychain_helper'
require_relative 'keychain_manager'
require_relative 'certificate_creator'
require 'fastlane_core/ui/ui'
require 'fastlane_core/helper'

module Fastlane
  module Helper
    module AppleDevPortal
      module Certificates
        module CertificateManager
          module_function

          # Ensure a distribution certificate exists locally and on App Store Connect
          #
          # Params:
          # - key_id, issuer_id, key_content, key_file_path: App Store Connect credentials
          # - keychain_name: String, keychain name (default: "login")
          # - keychain_password: String, keychain password
          # - project_root: String, project root directory (default: current directory)
          # - encryption_key: String, encryption key for certificate storage (from CERTIFICATE_ENCRYPTION_KEY env var)
          #
          # Returns: Hash with certificate info or nil if creation failed
          def ensure_distribution_certificate(key_id: nil, issuer_id: nil, key_content: nil, key_file_path: nil, keychain_name: nil, keychain_password: nil, project_root: Dir.pwd, encryption_key: nil, certificate_name: 'distribution')
            unless keychain_name
              KeychainManager.ensure_accessible
              keychain_name = KeychainManager.keychain_name
              keychain_password = KeychainManager.password
            end
            
            resolved_issuer_id = issuer_id || ENV['APP_STORE_CONNECT_ISSUER_ID']
            unless resolved_issuer_id
              begin
                credentials = AppStoreConnect::Credentials.get(
                  key_id: key_id,
                  issuer_id: issuer_id,
                  key_content: key_content,
                  key_file_path: key_file_path
                )
                resolved_issuer_id = credentials['issuer_id']
              rescue StandardError
              end
            end

            encryption_key ||= ENV['CERTIFICATE_ENCRYPTION_KEY']
            if (encryption_key.nil? || encryption_key.strip.empty?) && resolved_issuer_id
              encryption_key = Storage::KeychainStorage.retrieve_encryption_key(issuer_id: resolved_issuer_id, keychain_name: keychain_name)
              if encryption_key
                UI.message("Retrieved encryption key from keychain")
              end
            end
            is_ci = FastlaneCore::Helper.is_ci?

            UI.message("🔍 Checking for existing distribution certificates...")

            if is_ci
              UI.message("🤖 CI/CD Mode - will only restore from encrypted storage")
              
              unless encryption_key && !encryption_key.strip.empty?
                UI.user_error!(
                  "CERTIFICATE_ENCRYPTION_KEY environment variable is required on CI/CD. " \
                  "Please set it in your CI/CD secrets. " \
                  "If certificates don't exist, run 'bundle exec fastlane run ensure_certificates' locally first to create and encrypt them. " \
                  "To get the encryption key, run 'bundle exec fastlane run get_certificate_encryption_key' locally."
                )
              end

              unless Storage::CertificateStorage.encrypted_exists?(project_root, certificate_name: certificate_name)
                UI.user_error!(
                  "Encrypted certificate files not found in fastlane/certificates/#{certificate_name}.p12.enc. " \
                  "Please run 'ensure_certificates' locally first to create and encrypt the certificate, " \
                  "then commit the fastlane/certificates/ directory to your repository."
                )
              end

              metadata = Storage::CertificateStorage.load_metadata(project_root, certificate_name: certificate_name)
              unless metadata
                UI.user_error!(
                  "Certificate metadata file (fastlane/certificates/#{certificate_name}.yaml) not found. " \
                  "Please run 'ensure_certificates' locally first to create the certificate."
                )
              end

              if metadata['expires_at']
                expires_at = Time.parse(metadata['expires_at'])
                if expires_at < Time.now
                  UI.user_error!(
                    "Certificate has expired (expired on #{expires_at.strftime('%Y-%m-%d')}). " \
                    "Please run 'ensure_certificates' locally to create a new certificate."
                  )
                end
              end

              begin
                UI.message("Restoring certificate from encrypted storage...")
                plain_bytes = Storage::CertificateStorage.restore_encrypted(project_root, encryption_key, certificate_name: certificate_name)
                
                unless plain_bytes
                  UI.user_error!(
                    "Failed to decrypt certificate. The encryption key may be incorrect. " \
                    "Please verify CERTIFICATE_ENCRYPTION_KEY matches the key used when creating the certificate."
                  )
                end

                if FastlaneCore::Helper.mac?
                  Tempfile.create(['distribution', '.p12']) do |f|
                    f.binmode
                    f.write(plain_bytes)
                    f.close
                    
                    p12_password = 'fastlane'
                    KeychainHelper.import_certificate_to_keychain(f.path, p12_password, keychain_name, keychain_password)
                  end
                  
                  sha1 = metadata['sha1']
                  if KeychainHelper.certificate_exists_in_keychain?(sha1, keychain_name)
                    UI.success("✓ Restored and installed certificate from encrypted storage")
                    return {
                      id: metadata['id'],
                      name: metadata['common_name'],
                      expires: metadata['expires_at'],
                      sha1: sha1
                    }
                  else
                    UI.important("⚠ Certificate restored but not found in keychain")
                  end
                end

                UI.success("✓ Certificate restored from encrypted storage")
                return {
                  id: metadata['id'],
                  name: metadata['common_name'],
                  expires: metadata['expires_at'],
                  sha1: metadata['sha1']
                }
              rescue StandardError => e
                UI.user_error!(
                  "Failed to restore certificate from encrypted storage: #{e.message}\n" \
                  "Please verify CERTIFICATE_ENCRYPTION_KEY is correct, or run 'ensure_certificates' locally to recreate the certificate."
                )
              end
            end

            metadata = Storage::CertificateStorage.load_metadata(project_root, certificate_name: certificate_name)
            
            if metadata
              stored_sha1 = metadata['sha1']
              stored_expires = metadata['expires_at']
              
              if stored_sha1 && KeychainHelper.certificate_exists_in_keychain?(stored_sha1, keychain_name)
                is_valid = true
                
                if stored_expires
                  expires_at = Time.parse(stored_expires)
                  if expires_at < Time.now
                    UI.important("⚠ Certificate in keychain has expired (expired on #{expires_at.strftime('%Y-%m-%d')})")
                    is_valid = false
                  end
                end
                
                if is_valid
                  begin
                    remote_certs = AppStoreConnect::API.fetch_certificates(
                      key_id: key_id,
                      issuer_id: issuer_id,
                      key_content: key_content,
                      key_file_path: key_file_path,
                      types: ['IOS_DISTRIBUTION']
                    )
                    
                    if remote_certs && !remote_certs.empty?
                      remote_cert = remote_certs.first
                      remote_attrs = remote_cert['attributes'] || {}
                      remote_content = remote_attrs['certificateContent']
                      
                      if remote_content
                        remote_der = Base64.decode64(remote_content.gsub(/\s+/, ''))
                        remote_cert_obj = OpenSSL::X509::Certificate.new(remote_der)
                        remote_sha1 = OpenSSL::Digest::SHA1.hexdigest(remote_cert_obj.to_der).upcase
                        
                        if stored_sha1 == remote_sha1
                          UI.success("✓ Distribution certificate found in keychain and validated")
                          return {
                            id: remote_cert['id'],
                            name: remote_attrs['name'],
                            expires: remote_attrs['expirationDate'],
                            sha1: stored_sha1
                          }
                        else
                          UI.important("⚠ Certificate in keychain (SHA1: #{stored_sha1}) does not match remote certificate (SHA1: #{remote_sha1})")
                          is_valid = false
                        end
                      end
                    end
                  rescue StandardError => e
                    UI.important("⚠ Could not validate against remote certificate: #{e.message}")
                  end
                end
                
                if !is_valid
                  UI.message("Cleaning up invalid certificate from keychain and repo...")
                  KeychainHelper.delete_certificate_from_keychain(stored_sha1, keychain_name)
                  
                  encrypted_path = Storage::CertificateStorage.encrypted_p12_path(project_root, certificate_name: certificate_name)
                  metadata_path = Storage::CertificateStorage.metadata_path(project_root, certificate_name: certificate_name)
                  File.delete(encrypted_path) if File.exist?(encrypted_path)
                  File.delete(metadata_path) if File.exist?(metadata_path)
                end
              else
                UI.message("💾 Certificate not in keychain, attempting to restore from encrypted storage...")
                
                if encryption_key && Storage::CertificateStorage.encrypted_exists?(project_root, certificate_name: certificate_name)
                  begin
                    plain_bytes = Storage::CertificateStorage.restore_encrypted(project_root, encryption_key, certificate_name: certificate_name)
                    
                    if plain_bytes
                      if stored_expires
                        expires_at = Time.parse(stored_expires)
                        if expires_at < Time.now
                          UI.important("⚠ Certificate in storage has expired (expired on #{expires_at.strftime('%Y-%m-%d')})")
                        else
                          Tempfile.create(['distribution', '.p12']) do |f|
                            f.binmode
                            f.write(plain_bytes)
                            f.close
                            
                            p12_password = 'fastlane'
                            KeychainHelper.import_certificate_to_keychain(f.path, p12_password, keychain_name, keychain_password)
                          end
                          
                          if KeychainHelper.certificate_exists_in_keychain?(stored_sha1, keychain_name)
                            UI.success("✓ Restored and installed certificate from encrypted storage")
                            return {
                              id: metadata['id'],
                              name: metadata['common_name'],
                              expires: stored_expires,
                              sha1: stored_sha1
                            }
                          end
                        end
                      end
                    end
                  rescue StandardError => e
                    UI.important("⚠ Failed to restore from encrypted storage: #{e.message}")
                  end
                else
                  UI.important("⚠ Encrypted certificate not found or encryption key not set")
                end
              end
            end
            
            UI.message("☁️  Fetching remote distribution certificate from App Store Connect...")
            remote_certs = AppStoreConnect::API.fetch_certificates(
              key_id: key_id,
              issuer_id: issuer_id,
              key_content: key_content,
              key_file_path: key_file_path,
              types: ['IOS_DISTRIBUTION']
            )
            
            if remote_certs && !remote_certs.empty?
              UI.important("")
              UI.important("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
              UI.important("ERROR: Certificate exists on App Store Connect but not available locally")
              UI.important("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
              UI.important("")
              UI.important("To use this existing certificate:")
              UI.important("  👥 Ask a teammate to share the fastlane/certificates/ directory")
              UI.important("  📋 Get the CERTIFICATE_ENCRYPTION_KEY from them")
              UI.important("")
              UI.important("Or if the certificate needs to be replaced:")
              UI.important("  ⚠️  Revoke the certificate on App Store Connect first")
              UI.important("  🔄 Then run this action again to create a new one")
              UI.important("")
              UI.important("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
              UI.important("")
              
              return nil
            else
              UI.message("✨ No distribution certificate found on App Store Connect")
              UI.message("Creating new certificate...")
              
              CertificateCreator.create_new_distribution_certificate(
                key_id: key_id,
                issuer_id: resolved_issuer_id || issuer_id,
                key_content: key_content,
                key_file_path: key_file_path,
                keychain_name: keychain_name,
                keychain_password: keychain_password,
                project_root: project_root,
                encryption_key: encryption_key,
                certificate_name: certificate_name
              )
            end
          end
        end
      end
    end
  end
end

