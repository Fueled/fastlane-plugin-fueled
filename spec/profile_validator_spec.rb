describe Fastlane::Helper::AppleDevPortal::Profiles::ProfileValidator do
  # Empty profile_certificate_ids keeps these cases off the ASC API (no cert loop).
  describe '.validate with required_certificate_id' do
    it 'flags a profile that does not include the required certificate' do
      result = described_class.validate(
        profile_id: 'P1',
        profile_expiration_date: nil,
        profile_certificate_ids: [],
        bundle_id_id: 'B1',
        required_certificate_id: 'CERT_X'
      )
      expect(result[:needs_update]).to be true
      expect(result[:reason]).to include('CERT_X')
    end

    it 'does not flag when no certificate is required (back-compat)' do
      result = described_class.validate(
        profile_id: 'P1',
        profile_expiration_date: nil,
        profile_certificate_ids: [],
        bundle_id_id: 'B1'
      )
      expect(result[:needs_update]).to be false
    end
  end
end
