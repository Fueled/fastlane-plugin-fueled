module Fastlane
  module Actions
    module SharedValues
    end

    class IntegrationTestsFlutterAction < Action
      def self.run(params)
        UI.message("Running integration tests")
        sh("flutter test integration_test")
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        "Run Integration tests"
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
