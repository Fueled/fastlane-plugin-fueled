module Fastlane
    module Actions

        class UseGitCredentialStoreAction < Action
        
            def self.run(params)
              
              # generate_bash_script.rb
              commands = <<-BASH
              #!/bin/bash

              USERNAME=#{params[:git_user_name]}
              PASSWORD=#{params[:git_token]}

              # Install Git Credential Manager if not already installed
              if ! command -v git-credential-manager &> /dev/null
              then
                  echo "Git Credential Manager not found. Installing..."

                  if [[ "$OSTYPE" == "linux-gnu"* ]]; then
                      echo "Installing Git Credential Manager on Linux..."
                      curl -LO https://github.com/microsoft/Git-Credential-Manager/releases/latest/download/gcmcore-linux_amd64.tar.gz
                      tar -xvf gcmcore-linux_amd64.tar.gz
                      sudo ./install.sh
                  elif [[ "$OSTYPE" == "darwin"* ]]; then
                      echo "Installing Git Credential Manager on macOS..."
                      brew tap microsoft/git
                      brew install --cask git-credential-manager
                  elif [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]]; then
                      echo "Installing Git Credential Manager on Windows..."
                      winget install Microsoft.GitCredentialManager
                  else
                      echo "Unsupported OS. Please install Git Credential Manager manually."
                      exit 1
                  fi
              else
                  echo "Git Credential Manager is already installed."
              fi

              # Set Git Credential Manager as the default credential helper
              echo "Configuring Git to use Git Credential Manager..."
              git config --global --replace-all credential.helper manager

              # Set Git credentials
              echo "Setting Git credentials..."
              echo "protocol=https
              host=github.com
              username=$USERNAME
              password=$PASSWORD" | git credential approve

              echo "Git Credential Manager is now set as the default credential helper and credentials are configured."
              BASH
              
              if system(commands)
                UI.success("Your git credentials are saved to the git credential store ✅.")
              else
                UI.user_error!("Something went wrong, your git credentials are not saved. 🚫")
              end
            end
        
        #####################################################
        # @!group Documentation
        #####################################################
  
        def self.description
            "Employ Git's credential storage to securely save the Git username and password/token, eliminating the need to specify them repeatedly with each Git command."
        end

        def self.available_options
            [
              FastlaneCore::ConfigItem.new(
                key: :git_token,
                env_name: "GIT_TOKEN",
                description: "The git token that will be added to the git credential store",
                is_string: true,
                optional: false
              ),
              FastlaneCore::ConfigItem.new(
                key: :git_user_name,
                env_name: "GIT_USER_NAME",
                description: "The git username that will be added to the git credential store",
                is_string: true,
                optional: true,
                default_value: "Fueled"
              ),
              FastlaneCore::ConfigItem.new(
                key: :git_host,
                env_name: "GIT_HOST",
                description: "The host of your git repository (e.g. github.com, bitbucket.com, or gitlab.com)",
                is_string: true,
                optional: true,
                default_value: "github.com"
              )
            ]
          end
    
          def self.authors
            ["fueled"]
          end
    
          def self.is_supported?(platform)
              true
          end
    end
  end
end