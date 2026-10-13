require 'openssl'
require 'securerandom'
require 'time'
require_relative '../helper/fueled_helper'
require_relative '../library/apple_dev_portal/certificates/storage/certificate_storage'
require_relative 'get_certificate_encryption_key'

module Fastlane
  module Actions
    class EncryptCertificateAction < Action
      # ensure_certificates restores the stored p12 with this password.
      STORAGE_P12_PASSWORD = 'fastlane'.freeze
      CERTIFICATES_DIR = Helper::AppleDevPortal::Certificates::Storage::CertificateStorage::CERTIFICATES_DIR

      def self.run(params)
        UI.user_error!("encrypt_certificate must be run locally, not on CI/CD") if FastlaneCore::Helper.is_ci?

        p12_path = File.expand_path(params[:p12_path])
        UI.user_error!("Certificate not found at #{p12_path}") unless File.exist?(p12_path)

        pkcs12 = read_p12(p12_path, params[:p12_password].to_s)

        certificate = pkcs12.certificate
        metadata = certificate_metadata(certificate)
        if certificate.not_after < Time.now
          UI.user_error!("Certificate '#{metadata['common_name']}' expired on #{certificate.not_after.strftime('%Y-%m-%d')}")
        end

        # Re-package with the storage password, so ensure_certificates can import it.
        storage_p12 = OpenSSL::PKCS12.create(STORAGE_P12_PASSWORD, metadata['common_name'], pkcs12.key, certificate, pkcs12.ca_certs)

        encryption_key = params[:encryption_key]
        generated_key = encryption_key.nil? || encryption_key.strip.empty?
        if generated_key
          encryption_key = SecureRandom.base64(32)
          # Copy before writing anything: if the clipboard fails, no files are left encrypted with a lost key.
          GetCertificateEncryptionKeyAction.copy_to_clipboard(encryption_key)
        end

        Helper::AppleDevPortal::Certificates::Storage::CertificateStorage.save_encrypted(
          storage_p12.to_der,
          metadata,
          params[:project_root],
          encryption_key,
          certificate_name: params[:certificate_name]
        )
        encrypted_path = File.join(CERTIFICATES_DIR, "#{params[:certificate_name]}.p12.enc")
        metadata_path = File.join(CERTIFICATES_DIR, "#{params[:certificate_name]}.yaml")
        UI.success("✓ Saved encrypted certificate '#{metadata['common_name']}' to #{encrypted_path}")

        if generated_key
          UI.important("A new encryption key was generated and copied to your clipboard. " \
                       "Save it as CERTIFICATE_ENCRYPTION_KEY in your CI/CD secrets and password manager; it is not stored anywhere else.")
        end

        UI.message("Commit #{encrypted_path} and #{metadata_path}")
        metadata
      end

      def self.certificate_metadata(certificate)
        {
          'sha1' => OpenSSL::Digest::SHA1.hexdigest(certificate.to_der).upcase,
          'common_name' => certificate.subject.to_a.find { |entry| entry[0] == 'CN' }&.at(1),
          'expires_at' => certificate.not_after.utc.iso8601,
          'created_at' => Time.now.utc.iso8601,
          'id' => nil
        }
      end

      # p12 files exported from Keychain Access often use legacy algorithms (RC2/3DES) that OpenSSL 3
      # only reads with its legacy provider loaded.
      def self.read_p12(p12_path, password)
        data = File.binread(p12_path)
        begin
          OpenSSL::PKCS12.new(data, password)
        rescue OpenSSL::PKCS12::PKCS12Error => e
          UI.user_error!("Could not open #{p12_path}: #{e.message}. Check the p12 password.") unless load_legacy_provider

          begin
            OpenSSL::PKCS12.new(data, password)
          rescue OpenSSL::PKCS12::PKCS12Error => legacy_error
            UI.user_error!("Could not open #{p12_path}: #{legacy_error.message}. Check the p12 password.")
          end
        end
      end

      def self.load_legacy_provider
        return false unless defined?(OpenSSL::Provider)

        OpenSSL::Provider.load('legacy')
        true
      rescue OpenSSL::Provider::ProviderError
        false
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        "Encrypt an existing distribution certificate (.p12) into fastlane/certificates for ensure_certificates"
      end

      def self.details
        "Use this for certificates that are not managed through App Store Connect, e.g. an enterprise (in-house) certificate " \
        "kept in a password manager. The certificate is stored in the same format ensure_certificates creates, " \
        "so ensure_certificates(signing_source: 'repository') can restore it locally and on CI/CD without App Store Connect. " \
        "If CERTIFICATE_ENCRYPTION_KEY is not set, a new key is generated and copied to the clipboard."
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            key: :p12_path,
            env_name: "CERTIFICATE_P12_PATH",
            description: "Path to the .p12 file (certificate and private key)",
            is_string: true,
            optional: false
          ),
          FastlaneCore::ConfigItem.new(
            key: :p12_password,
            env_name: "CERTIFICATE_P12_PASSWORD",
            description: "Password of the .p12 file (asked with hidden input if not set)",
            is_string: true,
            optional: false,
            sensitive: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :encryption_key,
            env_name: "CERTIFICATE_ENCRYPTION_KEY",
            description: "Encryption key for certificate storage (generated if not set)",
            is_string: true,
            optional: true,
            sensitive: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :certificate_name,
            env_name: "CERTIFICATE_NAME",
            description: "Certificate name for storage (default: 'distribution')",
            is_string: true,
            optional: true,
            default_value: "distribution"
          ),
          FastlaneCore::ConfigItem.new(
            key: :project_root,
            env_name: "PROJECT_ROOT",
            description: "Project root directory (for encrypted certificate storage)",
            is_string: true,
            optional: true,
            default_value: Dir.pwd
          )
        ]
      end

      def self.return_value
        "Hash with the stored certificate metadata (sha1, common_name, expires_at, created_at)"
      end

      def self.authors
        ["fueled"]
      end

      def self.is_supported?(platform)
        [:ios, :mac].include?(platform)
      end

      def self.example_code
        [
          '# Asks for the .p12 password with hidden input (or reads CERTIFICATE_P12_PASSWORD)',
          'encrypt_certificate(',
          '  p12_path: "~/Downloads/Enterprise Distribution.p12"',
          ')'
        ]
      end

      def self.category
        :code_signing
      end
    end
  end
end
