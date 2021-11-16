require_relative '../helper/fueled_helper'

module Fastlane
  module Actions
    module SharedValues
    end

    class InstallWwdrCertificateAction < Action
      def self.run(params)
        sh("mkdir -p tmp")
        sh("cd tmp && curl -O -L http://developer.apple.com/certificationauthority/AppleWWDRCA.cer")
        other_action.import_certificate(
          certificate_path: "tmp/AppleWWDRCA.cer",
          keychain_name: params[:keychain_name],
          keychain_password: params[:keychain_password]
        )
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        "Pulls and adds the WWDR Apple Certificate to the given keychain"
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            key: :keychain_name,
            env_name: "KEYCHAIN_NAME",
            description: "The keychain name to install the certificate to",
            is_string: true,
            default_value: "login"
          ),
          FastlaneCore::ConfigItem.new(
            key: :keychain_password,
            env_name: "KEYCHAIN_PASSWORD",
            description: "The keychain password to install the certificate to",
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
