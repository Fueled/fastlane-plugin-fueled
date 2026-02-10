# frozen_string_literal: true

require_relative '../helper/fueled_helper'
require 'fastlane_core/helper'

module Fastlane
  module Actions
    module SharedValues
    end

    class GetCertificateEncryptionKeyAction < Action
      def self.run(params)
        if FastlaneCore::Helper.is_ci?
          UI.user_error!("This action can only be run locally, not on CI/CD. " \
                        "The encryption key should be retrieved locally and added as a secret in your CI/CD system.")
        end

        project_root = params[:project_root]
        
        # Use custom keychain if not specified (same as ensure_certificates)
        unless params[:keychain_name]
          require_relative '../library/apple_dev_portal/certificates/keychain_manager'
          Helper::AppleDevPortal::Certificates::KeychainManager.ensure_accessible
          keychain_name = Helper::AppleDevPortal::Certificates::KeychainManager.keychain_name
          keychain_password = Helper::AppleDevPortal::Certificates::KeychainManager.password
        else
          keychain_name = params[:keychain_name]
          keychain_password = params[:keychain_password]
        end
        
        issuer_id = params[:issuer_id] || ENV['APP_STORE_CONNECT_ISSUER_ID']
        
        # Try to get issuer_id from credentials if not provided
        unless issuer_id
          begin
            require_relative '../library/app_store_connect/credentials'
            credentials = Helper::AppStoreConnect::Credentials.get(
              key_id: params[:key_id],
              issuer_id: params[:issuer_id],
              key_content: params[:key_content],
              key_file_path: params[:key_file_path]
            )
            issuer_id = credentials['issuer_id']
          rescue StandardError
            # If credentials can't be loaded, issuer_id will be nil
          end
        end
        
        require_relative '../library/apple_dev_portal/certificates/storage/keychain_storage'

        # Get encryption key from: env var > keychain (if issuer_id available)
        encryption_key = ENV['CERTIFICATE_ENCRYPTION_KEY']
        if (encryption_key.nil? || encryption_key.strip.empty?) && issuer_id
          encryption_key = Helper::AppleDevPortal::Certificates::Storage::KeychainStorage.retrieve_encryption_key(issuer_id: issuer_id, keychain_name: keychain_name)
        end

        # Fail if not found
        if encryption_key.nil? || encryption_key.strip.empty?
          if issuer_id
            UI.user_error!("CERTIFICATE_ENCRYPTION_KEY not found in environment or keychain. " \
                          "Run 'bundle exec fastlane run ensure_certificates' to create a certificate and generate the key.")
          else
            UI.user_error!("CERTIFICATE_ENCRYPTION_KEY not found. " \
                          "Set APP_STORE_CONNECT_ISSUER_ID or CERTIFICATE_ENCRYPTION_KEY environment variable.")
          end
        end

        # Copy to clipboard silently (don't print the key)
        copy_to_clipboard(encryption_key)
        UI.success("✓ Encryption key copied to clipboard")

        # Return a message instead of the actual key to prevent it from being printed
        "Encryption key copied to clipboard"
      end

      def self.copy_to_clipboard(text)
        if FastlaneCore::Helper.mac?
          IO.popen('pbcopy', 'w') { |f| f << text }
        elsif FastlaneCore::Helper.linux?
          # Try xclip first, then xsel
          if system('which xclip > /dev/null 2>&1')
            IO.popen('xclip -selection clipboard', 'w') { |f| f << text }
          elsif system('which xsel > /dev/null 2>&1')
            IO.popen('xsel --clipboard --input', 'w') { |f| f << text }
          else
            UI.user_error!("Could not copy to clipboard. Please install xclip or xsel.")
          end
        else
          UI.user_error!("Clipboard not supported on this platform.")
        end
        true
      rescue StandardError => e
        UI.user_error!("Failed to copy to clipboard: #{e.message}")
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        "Get certificate encryption key from keychain and copy to clipboard"
      end

      def self.details
        "Retrieves CERTIFICATE_ENCRYPTION_KEY from environment or keychain and copies it to clipboard. " \
        "Does not print the key for security. Only runs locally (not on CI/CD)."
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            key: :project_root,
            env_name: "PROJECT_ROOT",
            description: "Project root directory",
            is_string: true,
            optional: true,
            default_value: Dir.pwd
          ),
          FastlaneCore::ConfigItem.new(
            key: :keychain_name,
            env_name: "KEYCHAIN_NAME",
            description: "Keychain name to store encryption key (defaults to custom fueled keychain)",
            is_string: true,
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :keychain_password,
            env_name: "KEYCHAIN_PASSWORD",
            description: "Keychain password (only needed for custom keychains)",
            is_string: true,
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :issuer_id,
            env_name: "APP_STORE_CONNECT_ISSUER_ID",
            description: "App Store Connect Issuer ID (required for keychain storage)",
            is_string: true,
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :key_id,
            env_name: "APP_STORE_CONNECT_KEY_ID",
            description: "App Store Connect Key ID (for retrieving issuer_id from credentials)",
            is_string: true,
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :key_content,
            env_name: "APP_STORE_CONNECT_KEY_CONTENT",
            description: "App Store Connect Key content (for retrieving issuer_id from credentials)",
            is_string: true,
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :key_file_path,
            env_name: "APP_STORE_CONNECT_KEY_FILE",
            description: "App Store Connect Key file path (for retrieving issuer_id from credentials)",
            is_string: true,
            optional: true
          )
        ]
      end

      def self.authors
        ["fueled"]
      end

      def self.is_supported?(platform)
        [:ios, :mac].include?(platform)
      end

      def self.example_code
        [
          '# Get encryption key from keychain and copy to clipboard',
          'get_certificate_encryption_key'
        ]
      end

      def self.category
        :code_signing
      end
    end
  end
end

