require_relative '../helper/fueled_helper'
require_relative '../library/apple_dev_portal/certificates/certificate_manager'
require_relative '../library/xcode/project_updater'
require_relative '../library/xcode/project_detector'

module Fastlane
  module Actions
    module SharedValues
      CERTIFICATE_INFO = :CERTIFICATE_INFO
    end

    class EnsureCertificatesAction < Action
      def self.run(params)
        UI.message("Ensuring certificates are available...")

        certificate_info = Helper::AppleDevPortal::Certificates::CertificateManager.ensure_distribution_certificate(
          key_id: params[:key_id],
          issuer_id: params[:issuer_id],
          key_content: params[:key_content],
          key_file_path: params[:key_file_path],
          keychain_name: params[:keychain_name],
          keychain_password: params[:keychain_password],
          project_root: params[:project_root],
          encryption_key: params[:encryption_key],
          certificate_name: params[:certificate_name]
        )

        if certificate_info
          Actions.lane_context[SharedValues::CERTIFICATE_INFO] = certificate_info

          if params[:bundle_id]
            project_path = params[:project_path]

            unless project_path
              UI.message("🔍 Searching for Xcode project with bundle ID: #{params[:bundle_id]}")
              detected_project = Helper::Xcode::ProjectDetector.find_project_with_bundle_id(
                bundle_id: params[:bundle_id],
                search_path: params[:search_path] || Dir.pwd
              )
              
              if detected_project
                project_path = detected_project[:project_path]
                UI.message("✓ Found bundle ID in project: #{project_path}")
              else
                UI.important("⚠ Bundle ID '#{params[:bundle_id]}' not found in any Xcode project. " \
                            "Skipping Xcode project signing settings update. " \
                            "Please ensure the bundle ID matches the PRODUCT_BUNDLE_IDENTIFIER in your Xcode project, " \
                            "or provide project_path parameter.")
              end
            end

            if project_path
              begin
                code_sign_identity = extract_code_sign_identity(certificate_info[:name])
                if code_sign_identity
                  Helper::Xcode::ProjectUpdater.update_signing_settings(
                    project_path: project_path,
                    bundle_id: params[:bundle_id],
                    signing_style: 'Manual',
                    code_sign_identity: code_sign_identity
                  )
                end
              rescue StandardError => e
                UI.important("⚠ Could not update Xcode project signing settings: #{e.message}")
              end
            end
          end
          
          UI.success("✓ Certificates ensured successfully!")
          certificate_info
        else
          UI.user_error!("Failed to ensure certificates")
        end
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        "Ensure iOS distribution certificates exist locally and on App Store Connect"
      end

      def self.details
        "This action checks if a distribution certificate exists on App Store Connect and in the local keychain. " \
        "If not found, it creates a new certificate and installs it to the keychain. " \
        "If CERTIFICATE_ENCRYPTION_KEY is set, certificates are encrypted and stored in fastlane/certificates/ " \
        "for sharing between team members and CI/CD systems. " \
        "On CI/CD, this action only restores from encrypted storage and will fail if certificates are missing or invalid. " \
        "On local machines, it can create new certificates. " \
        "If bundle_id and project_path are provided, this action will also update the Xcode project's CODE_SIGN_IDENTITY setting. " \
        "Credentials can be provided via environment variables or parameters."
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            key: :key_id,
            env_name: "APP_STORE_CONNECT_KEY_ID",
            description: "App Store Connect Key ID (10-character string)",
            is_string: true,
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :issuer_id,
            env_name: "APP_STORE_CONNECT_ISSUER_ID",
            description: "App Store Connect Issuer ID (UUID)",
            is_string: true,
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :key_content,
            env_name: "APP_STORE_CONNECT_KEY_CONTENT",
            description: "App Store Connect private key content (p8 file content as string)",
            is_string: true,
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :key_file_path,
            env_name: "APP_STORE_CONNECT_KEY_FILE",
            description: "Path to App Store Connect private key file (.p8)",
            is_string: true,
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :keychain_name,
            env_name: "KEYCHAIN_NAME",
            description: "Keychain name to install certificates to (default: uses custom fastlane keychain)",
            is_string: true,
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :keychain_password,
            env_name: "KEYCHAIN_PASSWORD",
            description: "Keychain password (required if using custom keychain)",
            is_string: true,
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :project_root,
            env_name: "PROJECT_ROOT",
            description: "Project root directory (for encrypted certificate storage)",
            is_string: true,
            optional: true,
            default_value: Dir.pwd
          ),
          FastlaneCore::ConfigItem.new(
            key: :encryption_key,
            env_name: "CERTIFICATE_ENCRYPTION_KEY",
            description: "Encryption key for certificate storage (required for encrypted storage, works on CI/CD)",
            is_string: true,
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :certificate_name,
            env_name: "CERTIFICATE_NAME",
            description: "Certificate name for storage (default: 'distribution'). Use different names for multiple certificates in the same project",
            is_string: true,
            optional: true,
            default_value: "distribution"
          ),
          FastlaneCore::ConfigItem.new(
            key: :bundle_id,
            env_name: "BUNDLE_ID",
            description: "Bundle identifier (optional, required to update Xcode project signing settings)",
            is_string: true,
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :project_path,
            env_name: "PROJECT_PATH",
            description: "Path to Xcode project (.xcodeproj) or workspace (.xcworkspace) (auto-detected from bundle_id if not provided)",
            is_string: true,
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :search_path,
            env_name: "SEARCH_PATH",
            description: "Directory to search for Xcode projects when auto-detecting (default: current directory)",
            is_string: true,
            optional: true,
            default_value: Dir.pwd
          )
        ]
      end

      def self.extract_code_sign_identity(certificate_name)
        return nil unless certificate_name
        
        if certificate_name.include?('iOS Distribution') || certificate_name.include?('iPhone Distribution')
          'iPhone Distribution'
        elsif certificate_name.include?('Mac Distribution')
          'Mac Distribution'
        elsif certificate_name.include?('Apple Distribution')
          'Apple Distribution'
        else
          nil
        end
      end

      def self.output
        [
          ['CERTIFICATE_INFO', 'Hash containing certificate information (id, name, expires, sha1)']
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
          '# Ensure certificates using environment variables',
          'ensure_certificates',
          '',
          '# Ensure certificates with explicit credentials',
          'ensure_certificates(',
          '  key_id: "ABC123DEFG",',
          '  issuer_id: "12345678-1234-1234-1234-123456789012",',
          '  key_file_path: "path/to/AuthKey.p8",',
          '  keychain_name: "temp",',
          '  keychain_password: "password"',
          ')'
        ]
      end

      def self.category
        :code_signing
      end
    end
  end
end

