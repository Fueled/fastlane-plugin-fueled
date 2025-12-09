# frozen_string_literal: true

require 'openssl'

module Fastlane
  module Helper
    module AppleDevPortal
      module Certificates
        module CSRGenerator
          module_function

          # Generate a Certificate Signing Request for distribution
          #
          # Returns: Hash with :csr_pem and :private_key_pem
          def generate_distribution
            generate_csr_with_cn('Apple Distribution')
          end

          # Generate a CSR with a specific common name
          #
          # Params:
          # - common_name: String, the common name for the certificate
          #
          # Returns: Hash with :csr_pem and :private_key_pem
          def generate_csr_with_cn(common_name)
            key = OpenSSL::PKey::RSA.new(2048)

            name = OpenSSL::X509::Name.new([
              ['CN', common_name, OpenSSL::ASN1::UTF8STRING],
            ])

            csr = OpenSSL::X509::Request.new
            csr.version = 0
            csr.subject = name
            csr.public_key = key.public_key
            csr.sign(key, OpenSSL::Digest.new('SHA256'))

            {
              csr_pem: csr.to_pem.strip,
              private_key_pem: key.to_pem.strip,
            }
          end
        end
      end
    end
  end
end

