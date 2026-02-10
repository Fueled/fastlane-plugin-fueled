# frozen_string_literal: true

require 'open3'
require 'fastlane_core/ui/ui'

module Fastlane
  module Helper
    module AppleDevPortal
      module Certificates
        module KeychainHelper
          module_function

          def resolve_keychain_path(keychain_name)
            return keychain_name if File.exist?(keychain_name) || keychain_name.start_with?('/')
            
            keychain_path = File.expand_path("~/Library/Keychains/#{keychain_name}.keychain-db")
            return keychain_path if File.exist?(keychain_path)
            
            keychain_path_old = File.expand_path("~/Library/Keychains/#{keychain_name}.keychain")
            return keychain_path_old if File.exist?(keychain_path_old)
            
            require_relative 'keychain_manager'
            managed_keychain_path = KeychainManager.keychain_path
            if File.exist?(managed_keychain_path)
              possible_paths = [
                File.expand_path("~/Library/Keychains/#{keychain_name}"),
                File.expand_path("~/Library/Keychains/#{keychain_name}.keychain-db"),
                File.expand_path("~/Library/Keychains/#{keychain_name}.keychain")
              ]
              return managed_keychain_path if possible_paths.include?(managed_keychain_path)
            end
            
            keychain_name
          end

          def certificate_exists_in_keychain?(sha1, keychain_name)
            keychain_path = resolve_keychain_path(keychain_name)
            output, _, status = Open3.capture3(
              'security', 'find-certificate', '-a', '-Z', keychain_path
            )

            return false unless status.success?

            output.include?(sha1)
          end

          def delete_certificate_from_keychain(sha1, keychain_name)
            keychain_path = resolve_keychain_path(keychain_name)
            output, _, status = Open3.capture3(
              'security', 'find-certificate', '-a', '-c', sha1, '-Z', keychain_path
            )

            return false unless status.success?
            return false unless output.include?(sha1)

            cert_hash = nil
            output.each_line do |line|
              if line =~ /SHA-1 hash: (.+)$/
                cert_hash = $1.strip
                break
              end
            end

            return false unless cert_hash

            _, err, status = Open3.capture3(
              'security', 'delete-certificate', '-Z', cert_hash, keychain_path
            )

            if status.success?
              UI.message("✓ Deleted revoked certificate from keychain")
              true
            else
              _, err2, status2 = Open3.capture3(
                'security', 'delete-certificate', '-c', sha1, keychain_path
              )
              
              if status2.success?
                UI.message("✓ Deleted revoked certificate from keychain")
                true
              else
                UI.important("⚠ Could not delete certificate from keychain: #{err2 || err}")
                false
              end
            end
          end

          def import_certificate_to_keychain(cert_path, cert_password, keychain_name, keychain_password)
            keychain_path = resolve_keychain_path(keychain_name)
            
            require_relative 'keychain_manager'
            if keychain_path == KeychainManager.keychain_path
              KeychainManager.ensure_accessible
              KeychainManager.unlock
            elsif keychain_password && !keychain_password.empty?
              _, unlock_err, unlock_status = Open3.capture3(
                'security', 'unlock-keychain',
                '-p', keychain_password,
                keychain_path
              )
              unless unlock_status.success?
                UI.important("Warning: Could not unlock keychain: #{unlock_err}")
              end
            end
            
            begin
              require 'openssl'
              p12_data = File.binread(cert_path)
              begin
                OpenSSL::PKCS12.new(p12_data, cert_password)
              rescue OpenSSL::PKCS12::PKCS12Error
                OpenSSL::PKCS12.new(p12_data, '')
              end
            rescue StandardError => e
              UI.important("Warning: Could not validate p12 file before import: #{e.message}")
            end
            
            import_cmd = ['security', 'import', cert_path,
                         '-f', 'pkcs12',
                         '-k', keychain_path,
                         '-T', '/usr/bin/codesign',
                         '-A']
            
            if cert_password && !cert_password.empty?
              import_cmd += ['-P', cert_password]
            end
            
            _, err, status = Open3.capture3(*import_cmd)
            
            if !status.success? && keychain_path == KeychainManager.keychain_path
              require_relative 'keychain_manager'
              import_cmd_name = ['security', 'import', cert_path,
                               '-f', 'pkcs12',
                               '-k', KeychainManager.keychain_name,
                               '-T', '/usr/bin/codesign',
                               '-A']
              if cert_password && !cert_password.empty?
                import_cmd_name += ['-P', cert_password]
              end
              
              KeychainManager.unlock
              
              _, err2, status2 = Open3.capture3(*import_cmd_name)
              
              if status2.success?
                status = status2
                err = nil
              else
                err = err2 || err
              end
            end

            unless status.success?
              if err.to_s.include?('wrong password') || err.to_s.include?('MAC verification failed')
                UI.user_error!("Failed to import certificate to keychain: Wrong password. " \
                  "The p12 file may have been created with a different password. " \
                  "Original error: #{err}")
              else
                UI.user_error!("Failed to import certificate to keychain: #{err}")
              end
            end

            if keychain_password && !keychain_password.empty?
              _, err, status = Open3.capture3(
                'security', 'set-key-partition-list',
                '-S', 'apple-tool:,apple:',
                '-k', keychain_password,
                keychain_path
              )
              UI.important("Warning: Could not set key partition list: #{err}") unless status.success?
            end
          end
        end
      end
    end
  end
end

