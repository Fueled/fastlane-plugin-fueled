module Fastlane
  module Actions
    module SharedValues
    end

    class CiChecksFlutterAction < Action
      def self.run(params)
        UI.message("Running Lint checks")
        sh("flutter analyze")
        UI.message("Running code coverage fix")
        sh("./scripts/code_coverage_helper.sh") #TODO: incorporate the code from `code_coverage_helper.sh` into this action once this issue has been resolved https://github.com/flutter/flutter/issues/27997
        UI.message("Running unit tests")
        sh("rm -rf coverage")
        sh("flutter test --coverage")
        sh("genhtml -o coverage coverage/lcov.info")
        sh("flutter test test/essentials.dart")
        if !params[:skip_integration_tests]
          UI.message("Running integration tests")
          sh("flutter test integration_test")
        end
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        "Run tests and check code coverage"
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            key: :skip_integration_tests,
            env_name: "SKIP_INTEGRATION_TESTS",
            description: "If true, only unit tests are executed",
            optional: true,
            is_string: false,
            default_value: false
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
