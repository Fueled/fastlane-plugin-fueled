describe Fastlane::Actions::EnsureCertificatesAction do
  describe '.extract_code_sign_identity' do
    it 'maps legacy iOS Distribution certs to iPhone Distribution' do
      expect(described_class.extract_code_sign_identity('iOS Distribution: P3 Recovery Pty Ltd'))
        .to eq('iPhone Distribution')
    end

    it 'maps Apple Distribution certs to Apple Distribution' do
      expect(described_class.extract_code_sign_identity('Apple Distribution: P3 Recovery Pty Ltd'))
        .to eq('Apple Distribution')
    end

    it 'maps Mac Distribution certs to Mac Distribution' do
      expect(described_class.extract_code_sign_identity('Mac Distribution: Example'))
        .to eq('Mac Distribution')
    end

    it 'returns nil for unrecognized certificate names' do
      expect(described_class.extract_code_sign_identity('Something Else')).to be_nil
    end
  end

  describe 'distribution_certificate_type option' do
    let(:option) do
      described_class.available_options.find { |o| o.key == :distribution_certificate_type }
    end

    it 'exists and defaults to IOS_DISTRIBUTION for back-compat' do
      expect(option).not_to be_nil
      expect(option.default_value).to eq('IOS_DISTRIBUTION')
    end

    it 'accepts DISTRIBUTION (Apple Distribution)' do
      expect { option.verify_block.call('DISTRIBUTION') }.not_to raise_error
    end

    it 'rejects unknown certificate types' do
      expect { option.verify_block.call('NOPE') }
        .to raise_error(FastlaneCore::Interface::FastlaneError)
    end
  end
end
