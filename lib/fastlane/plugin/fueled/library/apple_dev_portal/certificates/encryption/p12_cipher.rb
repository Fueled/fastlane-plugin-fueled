# frozen_string_literal: true

require 'rbnacl'
require 'base64'
require 'fastlane_core/ui/ui'

module Fastlane
  module Helper
    module AppleDevPortal
      module Certificates
        module Encryption
          module P12Cipher
            module_function

            # Encrypt p12 bytes using a key
            #
            # Params:
            # - plain_bytes: String, the p12 file bytes
            # - key: String, the encryption key (32 bytes for AES-256)
            #
            # Returns: String, base64-encoded encrypted data
            def encrypt_p12(plain_bytes, key)
              key_bytes = normalize_key(key)
              secret_box = RbNaCl::SecretBox.new(key_bytes)
              nonce = RbNaCl::Random.random_bytes(secret_box.nonce_bytes)
              ciphertext = secret_box.encrypt(nonce, plain_bytes)
              Base64.strict_encode64(nonce + ciphertext)
            end

            # Decrypt p12 bytes using a key
            #
            # Params:
            # - encrypted_base64: String, base64-encoded encrypted data
            # - key: String, the encryption key (32 bytes for AES-256)
            #
            # Returns: String, the decrypted p12 file bytes
            def decrypt_p12(encrypted_base64, key)
              key_bytes = normalize_key(key)
              secret_box = RbNaCl::SecretBox.new(key_bytes)
              encrypted_data = Base64.decode64(encrypted_base64)
              nonce = encrypted_data[0, secret_box.nonce_bytes]
              ciphertext = encrypted_data[secret_box.nonce_bytes..-1]
              secret_box.decrypt(nonce, ciphertext)
            rescue StandardError => e
              UI.user_error!("Failed to decrypt certificate: #{e.message}")
            end

            # Normalize key to 32 bytes (for AES-256)
            # Uses SHA-256 hash if key is not exactly 32 bytes
            def normalize_key(key)
              require 'digest'
              key_str = key.to_s
              if key_str.bytesize == 32
                key_str
              else
                Digest::SHA256.digest(key_str)
              end
            end

            private_class_method :normalize_key
          end
        end
      end
    end
  end
end

