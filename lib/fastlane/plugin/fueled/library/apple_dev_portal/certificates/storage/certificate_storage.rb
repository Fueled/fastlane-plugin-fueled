# frozen_string_literal: true

require 'yaml'
require 'fileutils'
require_relative '../encryption/p12_cipher'
require 'fastlane_core/ui/ui'

module Fastlane
  module Helper
    module AppleDevPortal
      module Certificates
        module Storage
          module CertificateStorage
            module_function

            CERTIFICATES_DIR = 'fastlane/certificates'

            # Load certificate metadata from local storage
            #
            # Params:
            # - project_root: String, project root directory
            # - certificate_name: String, certificate name (default: "distribution")
            #
            # Returns: Hash with metadata or nil if not found
            def load_metadata(project_root, certificate_name: 'distribution')
              path = metadata_path(project_root, certificate_name: certificate_name)
              return nil unless File.exist?(path)

              YAML.safe_load(File.read(path))
            end

            # Get path to encrypted p12 file
            #
            # Params:
            # - project_root: String, project root directory
            # - certificate_name: String, certificate name (default: "distribution")
            #
            # Returns: String, path to encrypted p12 file
            def encrypted_p12_path(project_root, certificate_name: 'distribution')
              File.join(project_root, CERTIFICATES_DIR, "#{certificate_name}.p12.enc")
            end

            # Get path to metadata file
            #
            # Params:
            # - project_root: String, project root directory
            # - certificate_name: String, certificate name (default: "distribution")
            #
            # Returns: String, path to metadata file
            def metadata_path(project_root, certificate_name: 'distribution')
              File.join(project_root, CERTIFICATES_DIR, "#{certificate_name}.yaml")
            end

            # Save encrypted p12 and metadata
            #
            # Params:
            # - plain_bytes: String, the p12 file bytes
            # - metadata: Hash, certificate metadata
            # - project_root: String, project root directory
            # - encryption_key: String, encryption key (from env var or generated)
            # - certificate_name: String, certificate name (default: "distribution")
            #
            # Returns: Boolean, true if saved successfully
            def save_encrypted(plain_bytes, metadata, project_root, encryption_key, certificate_name: 'distribution')
              require 'digest'

              # Ensure encryption key is set
              unless encryption_key && !encryption_key.strip.empty?
                UI.user_error!('Encryption key required. Set CERTIFICATE_ENCRYPTION_KEY environment variable.')
              end

              # Encrypt the p12
              encrypted = Encryption::P12Cipher.encrypt_p12(plain_bytes, encryption_key)

              # Create directory
              dir = File.join(project_root, CERTIFICATES_DIR)
              FileUtils.mkdir_p(dir)

              # Save encrypted p12
              File.write(encrypted_p12_path(project_root, certificate_name: certificate_name), encrypted)

              # Save metadata
              File.write(metadata_path(project_root, certificate_name: certificate_name), metadata.to_yaml)

              true
            end

            # Restore and decrypt p12 from encrypted storage
            #
            # Params:
            # - project_root: String, project root directory
            # - encryption_key: String, encryption key (from env var)
            # - certificate_name: String, certificate name (default: "distribution")
            #
            # Returns: String, decrypted p12 bytes or nil if not found
            def restore_encrypted(project_root, encryption_key, certificate_name: 'distribution')
              encrypted_path = encrypted_p12_path(project_root, certificate_name: certificate_name)
              return nil unless File.exist?(encrypted_path)

              unless encryption_key && !encryption_key.strip.empty?
                UI.user_error!('Encryption key required to restore certificate. Set CERTIFICATE_ENCRYPTION_KEY environment variable.')
              end

              encrypted = File.read(encrypted_path).strip
              Encryption::P12Cipher.decrypt_p12(encrypted, encryption_key)
            end

            # Check if encrypted certificate exists
            #
            # Params:
            # - project_root: String, project root directory
            # - certificate_name: String, certificate name (default: "distribution")
            #
            # Returns: Boolean
            def encrypted_exists?(project_root, certificate_name: 'distribution')
              File.exist?(encrypted_p12_path(project_root, certificate_name: certificate_name)) && 
                File.exist?(metadata_path(project_root, certificate_name: certificate_name))
            end
          end
        end
      end
    end
  end
end

