# frozen_string_literal: true

require 'fastlane_core/ui/ui'

module Fastlane
  module Helper
    module AppStoreConnect
      module Credentials
        module_function

        # Get App Store Connect credentials from environment variables
        #
        # Supports two patterns:
        # 1. Direct env vars: APP_STORE_CONNECT_KEY_ID, APP_STORE_CONNECT_ISSUER_ID, APP_STORE_CONNECT_KEY_CONTENT
        # 2. File-based key: APP_STORE_CONNECT_KEY_FILE (path to .p8 file)
        #
        # Params:
        # - key_id: String, optional (defaults to APP_STORE_CONNECT_KEY_ID env var)
        # - issuer_id: String, optional (defaults to APP_STORE_CONNECT_ISSUER_ID env var)
        # - key_content: String, optional (defaults to APP_STORE_CONNECT_KEY_CONTENT env var or reads from APP_STORE_CONNECT_KEY_FILE)
        # - key_file_path: String, optional (path to .p8 file, overrides key_content)
        #
        # Returns: Hash with :p8, :key_id, :issuer_id
        #
        # Raises: FastlaneCore::Interface::FastlaneError if credentials are missing
        def get(key_id: nil, issuer_id: nil, key_content: nil, key_file_path: nil)
          resolved_key_id = key_id || ENV['APP_STORE_CONNECT_KEY_ID']
          resolved_issuer_id = issuer_id || ENV['APP_STORE_CONNECT_ISSUER_ID']
          resolved_key_file = key_file_path || ENV['APP_STORE_CONNECT_KEY_FILE']
          resolved_key_content = key_content || ENV['APP_STORE_CONNECT_KEY_CONTENT']

          # Validate required fields
          if resolved_key_id.nil? || resolved_key_id.strip.empty?
            UI.user_error!('Missing App Store Connect Key ID. Set APP_STORE_CONNECT_KEY_ID environment variable or pass key_id parameter.')
          end

          if resolved_issuer_id.nil? || resolved_issuer_id.strip.empty?
            UI.user_error!('Missing App Store Connect Issuer ID. Set APP_STORE_CONNECT_ISSUER_ID environment variable or pass issuer_id parameter.')
          end

          # Get key content from file or env var
          p8_content = if resolved_key_file && File.exist?(resolved_key_file)
                         File.read(resolved_key_file).strip
                       elsif resolved_key_content && !resolved_key_content.strip.empty?
                         resolved_key_content.strip
                       else
                         UI.user_error!('Missing App Store Connect Private Key. Set APP_STORE_CONNECT_KEY_CONTENT (p8 content) or APP_STORE_CONNECT_KEY_FILE (path to .p8 file) environment variable, or pass key_content/key_file_path parameter.')
                       end

          {
            'p8' => p8_content,
            'key_id' => resolved_key_id,
            'issuer_id' => resolved_issuer_id
          }
        end
      end
    end
  end
end

