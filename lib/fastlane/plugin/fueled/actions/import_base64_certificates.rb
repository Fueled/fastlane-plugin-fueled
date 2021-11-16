require_relative '../helper/fueled_helper'

module Fastlane
  module Actions
    module SharedValues
    end

    class ImportBase64CertificatesAction < Action
      def self.run(params)
        sh("mkdir -p tmp")
        sh("echo '#{params[:base64_input]}' | base64 -d -o tmp/certs.p12")
        other_action.import_certificate(
          certificate_path: "tmp/certs.p12",
          certificate_password: params[:p12_password],
          keychain_name: params[:keychain_name],
          keychain_password: params[:keychain_password]
        )
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        "Import p12 certificates encoded as base64"
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            key: :base64_input,
            env_name: "BASE64_CERTIFICATE_INPUT",
            description: "The base64 string describing the p12 file",
            is_string: true,
            optional: false
          ),
          FastlaneCore::ConfigItem.new(
            key: :p12_password,
            env_name: "P12_PASSWORD",
            description: "The decrypted p12 password",
            is_string: true,
            default_value: ""
          ),
          FastlaneCore::ConfigItem.new(
            key: :keychain_name,
            env_name: "KEYCHAIN_NAME",
            description: "The keychain name to install the certificates to",
            is_string: true,
            default_value: "login"
          ),
          FastlaneCore::ConfigItem.new(
            key: :keychain_password,
            env_name: "KEYCHAIN_PASSWORD",
            description: "The keychain password to install the certificates to",
            is_string: true,
            default_value: ""
          )
        ]
      end

      def self.authors
        ["fueled"]
      end

      def self.is_supported?(platform)
        [:ios, :mac].include?(platform)
      end
    end
  end
end
