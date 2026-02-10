# frozen_string_literal: true

require 'open3'
require 'fastlane_core/ui/ui'

module Fastlane
  module Helper
    module AppleDevPortal
      module Certificates
        module Storage
          module KeychainStorage
            module_function

            SERVICE_NAME = 'fastlane-plugin-fueled'

            # Resolve keychain path from keychain name
            def resolve_keychain_path(keychain_name)
              # If it's already a full path, return it
              return keychain_name if File.exist?(keychain_name) || keychain_name.start_with?('/')
              
              # For fueled keychain, use the custom keychain path
              if keychain_name == 'fueled.keychain-db' || keychain_name == 'fueled'
                require_relative '../keychain_manager'
                return KeychainManager.keychain_path if File.exist?(KeychainManager.keychain_path)
              end
              
              # For "login" keychain, try to find the actual path
              if keychain_name == 'login'
                login_keychain_new = File.expand_path('~/Library/Keychains/login.keychain-db')
                return login_keychain_new if File.exist?(login_keychain_new)
                
                login_keychain_old = File.expand_path('~/Library/Keychains/login.keychain')
                return login_keychain_old if File.exist?(login_keychain_old)
              end
              
              # For other keychains, try to find them in the default location
              keychain_path = File.expand_path("~/Library/Keychains/#{keychain_name}.keychain-db")
              return keychain_path if File.exist?(keychain_path)
              
              keychain_path_old = File.expand_path("~/Library/Keychains/#{keychain_name}.keychain")
              return keychain_path_old if File.exist?(keychain_path_old)
              
              # Return as-is if not found
              keychain_name
            end

            # Store encryption key in macOS keychain (account-specific by issuer_id)
            #
            # Params:
            # - encryption_key: String, the encryption key to store
            # - issuer_id: String, App Store Connect Issuer ID (used to make key unique per account)
            # - keychain_name: String, keychain name (default: "login")
            #
            # Returns: Boolean, true if stored successfully
            def store_encryption_key(encryption_key, issuer_id:, keychain_name: 'login')
              return false unless FastlaneCore::Helper.mac?
              return false if encryption_key.nil? || encryption_key.strip.empty?
              return false if issuer_id.nil? || issuer_id.strip.empty?

              account_name = account_name_for_issuer(issuer_id)
              keychain_path = resolve_keychain_path(keychain_name)

              # Unlock keychain if it's our custom keychain
              if keychain_path.include?('fueled.keychain-db')
                require_relative '../keychain_manager'
                KeychainManager.ensure_accessible
              end

              # Use security add-generic-password to store in keychain
              # -s: service name
              # -a: account name (includes issuer_id for uniqueness)
              # -w: password (the encryption key)
              # -U: update if exists
              _, err, status = Open3.capture3(
                'security', 'add-generic-password',
                '-s', SERVICE_NAME,
                '-a', account_name,
                '-w', encryption_key,
                '-U',
                keychain_path
              )

              if status.success?
                UI.message("✓ Stored encryption key in keychain")
                true
              else
                UI.important("⚠ Failed to store encryption key in keychain: #{err}")
                false
              end
            end

            # Retrieve encryption key from macOS keychain (account-specific by issuer_id)
            #
            # Params:
            # - issuer_id: String, App Store Connect Issuer ID
            # - keychain_name: String, keychain name (default: "login")
            #
            # Returns: String, the encryption key or nil if not found
            def retrieve_encryption_key(issuer_id:, keychain_name: 'login')
              return nil unless FastlaneCore::Helper.mac?
              return nil if issuer_id.nil? || issuer_id.strip.empty?

              account_name = account_name_for_issuer(issuer_id)
              keychain_path = resolve_keychain_path(keychain_name)

              # Unlock keychain if it's our custom keychain
              if keychain_path.include?('fueled.keychain-db')
                require_relative '../keychain_manager'
                KeychainManager.ensure_accessible
                # For custom keychain, search without specifying path (searches all keychains in search list)
                output, err, status = Open3.capture3(
                  'security', 'find-generic-password',
                  '-s', SERVICE_NAME,
                  '-a', account_name,
                  '-w'
                )
              else
                # For other keychains, use keychain path
                output, err, status = Open3.capture3(
                  'security', 'find-generic-password',
                  '-s', SERVICE_NAME,
                  '-a', account_name,
                  '-w',
                  keychain_path
                )
              end

              if status.success? && !output.strip.empty?
                output.strip
              else
                nil
              end
            end

            # Check if encryption key exists in keychain (account-specific by issuer_id)
            #
            # Params:
            # - issuer_id: String, App Store Connect Issuer ID
            # - keychain_name: String, keychain name (default: "login")
            #
            # Returns: Boolean
            def encryption_key_exists?(issuer_id:, keychain_name: 'login')
              return false unless FastlaneCore::Helper.mac?
              return false if issuer_id.nil? || issuer_id.strip.empty?

              account_name = account_name_for_issuer(issuer_id)
              keychain_path = resolve_keychain_path(keychain_name)

              _, _, status = Open3.capture3(
                'security', 'find-generic-password',
                '-s', SERVICE_NAME,
                '-a', account_name,
                keychain_path
              )

              status.success?
            end

            # Delete encryption key from keychain (account-specific by issuer_id)
            #
            # Params:
            # - issuer_id: String, App Store Connect Issuer ID
            # - keychain_name: String, keychain name (default: "login")
            #
            # Returns: Boolean, true if deleted successfully
            def delete_encryption_key(issuer_id:, keychain_name: 'login')
              return false unless FastlaneCore::Helper.mac?
              return false if issuer_id.nil? || issuer_id.strip.empty?

              account_name = account_name_for_issuer(issuer_id)
              keychain_path = resolve_keychain_path(keychain_name)

              _, err, status = Open3.capture3(
                'security', 'delete-generic-password',
                '-s', SERVICE_NAME,
                '-a', account_name,
                keychain_path
              )

              status.success?
            end

            # Generate account name for keychain storage based on issuer_id
            #
            # Params:
            # - issuer_id: String, App Store Connect Issuer ID
            #
            # Returns: String, account name for keychain
            def account_name_for_issuer(issuer_id)
              "certificate-encryption-key:#{issuer_id}"
            end
          end
        end
      end
    end
  end
end

