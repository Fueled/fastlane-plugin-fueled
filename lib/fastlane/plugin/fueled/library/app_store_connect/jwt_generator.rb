# frozen_string_literal: true

require 'jwt'
require 'openssl'

module Fastlane
  module Helper
    module AppStoreConnect
      module JWTGenerator
        module_function

        ##
        # Generate a JWT for App Store Connect.
        #
        # Params:
        # - p8_content:        String, full PEM content of the private key
        # - key_id:    String, 10-character Key ID
        # - issuer_id: String, ASC Issuer ID (UUID)
        #
        # Returns: Signed JWT string
        ##
        def generate(p8_content:, key_id:, issuer_id:)
          # Normalize key content (handles spaces, escaped newlines, etc.)
          normalized_key = normalize_p8_content(p8_content)
          
          # Parse EC private key
          private_key = parse_ec_key(normalized_key)

          now = Time.now.to_i

          payload = {
            iss: issuer_id,
            iat: now,
            exp: now + (20 * 60), # 20 minutes max allowed by Apple
            aud: 'appstoreconnect-v1',
          }

          headers = {
            kid: key_id,
            alg: 'ES256',
            typ: 'JWT',
          }

          JWT.encode(payload, private_key, 'ES256', headers)
        end

        ##
        # Quick validation helper — verifies the key is EC and can sign.
        #
        # Params:
        # - p8_content: String, full PEM content of the private key
        #
        # Returns: Boolean
        ##
        def validate_key(p8_content)
          normalized_key = normalize_p8_content(p8_content)
          parse_ec_key(normalized_key)
          true
        rescue StandardError
          false
        end

        ##
        # Normalize P8 key content to proper PEM format
        # Handles escaped newlines, spaces, and single-line formats
        ##
        def normalize_p8_content(p8_content)
          return p8_content if p8_content.nil? || p8_content.empty?
          
          content = p8_content.strip
          
          # Handle escaped newlines
          content = content.gsub(/\\n/, "\n")
          
          # Find BEGIN marker position
          begin_start = content.index(/-{4,6}BEGIN/i)
          unless begin_start
            raise ArgumentError, "Invalid P8 key format: missing BEGIN marker. " \
              "Please ensure your APP_STORE_CONNECT_KEY_CONTENT contains the full PEM-formatted key."
          end
          
          # Find where BEGIN marker ends (look for sequence of dashes after BEGIN text)
          # Pattern: BEGIN followed by optional text, then dashes
          begin_marker_match = content[begin_start..-1].match(/^(-{4,6}BEGIN[^-]*?)(-{4,6})(\s|$)/)
          unless begin_marker_match
            raise ArgumentError, "Invalid P8 key format: malformed BEGIN marker."
          end
          
          begin_text = (begin_marker_match[1] + begin_marker_match[2]).strip
          begin_end_pos = begin_start + begin_marker_match.end(0)
          
          # Find END marker position (search from the end backwards)
          end_match = content.match(/(-{4,6}END[^-]*?-{4,6})(\s|$)/)
          unless end_match
            raise ArgumentError, "Invalid P8 key format: missing END marker. " \
              "Please ensure your APP_STORE_CONNECT_KEY_CONTENT contains the full PEM-formatted key."
          end
          
          end_text = end_match[1].strip
          end_start_pos = end_match.begin(0)
          
          # Normalize markers to ensure exactly 5 dashes
          begin_text = begin_text.sub(/^-{1,6}BEGIN/i, '-----BEGIN').sub(/-+$/, '-----')
          end_text = end_text.sub(/^-{1,6}END/i, '-----END').sub(/-+$/, '-----')
          
          # Extract base64 content between markers
          # Start after the BEGIN marker (skip any whitespace)
          start_pos = begin_end_pos
          while start_pos < content.length && content[start_pos].match?(/\s/)
            start_pos += 1
          end
          
          # End before the END marker (skip any whitespace before END)
          end_pos = end_start_pos
          while end_pos > start_pos && content[end_pos - 1].match?(/\s/)
            end_pos -= 1
          end
          
          base64_content = content[start_pos...end_pos]
          
          # Handle spaces/newlines in base64 content
          if base64_content && !base64_content.include?("\n")
            cleaned_base64 = base64_content.gsub(/\s+/, '')
            base64_content = cleaned_base64.scan(/.{1,64}/).join("\n")
          elsif base64_content
            lines = base64_content.split("\n").map { |line| line.gsub(/\s+/, '') }.reject(&:empty?)
            base64_content = lines.join("\n")
          else
            base64_content = ''
          end
          
          # Normalize markers and reconstruct PEM format
          begin_text = begin_text.gsub(/^-{1,6}BEGIN/, '-----BEGIN')
          end_text = end_text.gsub(/^-{1,6}END/, '-----END')
          normalized = "#{begin_text}\n#{base64_content}\n#{end_text}\n"
          
          normalized
        end

        ##
        # Parse EC private key from normalized PEM content
        ##
        def parse_ec_key(p8_content)
          # Validate the key starts with proper PEM header
          unless p8_content.strip.start_with?('-----BEGIN') && p8_content.include?('-----END')
            raise ArgumentError, "Invalid PEM format: key must start with -----BEGIN and contain -----END"
          end
          
          begin
            OpenSSL::PKey::EC.new(p8_content)
          rescue OpenSSL::PKey::ECError => e
            begin
              key = OpenSSL::PKey.read(p8_content)
              unless key.is_a?(OpenSSL::PKey::EC)
                raise ArgumentError, "Expected EC private key, got #{key.class}"
              end
              key
            rescue OpenSSL::PKey::PKeyError, ArgumentError => e2
              # Provide more detailed error message
              first_line = p8_content.lines.first&.strip || ''
              raise ArgumentError, "Could not parse EC private key. " \
                "Please ensure your APP_STORE_CONNECT_KEY_CONTENT or APP_STORE_CONNECT_KEY_FILE " \
                "contains a valid P8 file from App Store Connect.\n" \
                "First line of normalized key: #{first_line[0..50]}...\n" \
                "Original error: #{e.class}: #{e.message}"
            end
          end
        end
      end
    end
  end
end

