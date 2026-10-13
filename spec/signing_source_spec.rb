require 'tmpdir'
require 'openssl'

module SigningSpecHelpers
  def self_signed_certificate(common_name:, not_after: Time.now + (365 * 24 * 3600))
    key = OpenSSL::PKey::RSA.new(2048)
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 1
    cert.subject = OpenSSL::X509::Name.parse("/CN=#{common_name}/O=Fueled")
    cert.issuer = cert.subject
    cert.public_key = key.public_key
    cert.not_before = Time.now - 3600
    cert.not_after = not_after
    cert.sign(key, OpenSSL::Digest.new('SHA256'))
    [key, cert]
  end

  def write_p12(dir, password:, common_name: 'iPhone Distribution: Fueled', not_after: Time.now + (365 * 24 * 3600))
    key, cert = self_signed_certificate(common_name: common_name, not_after: not_after)
    path = File.join(dir, 'enterprise.p12')
    File.binwrite(path, OpenSSL::PKCS12.create(password, common_name, key, cert).to_der)
    [path, cert]
  end

  def profile_plist(uuid:, name:, bundle_id:, expiration:, certificates: [])
    certificate_data = certificates.map { |cert| "<data>#{[cert.to_der].pack('m0')}</data>" }.join
    <<~PLIST
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
        <key>Name</key><string>#{name}</string>
        <key>UUID</key><string>#{uuid}</string>
        <key>TeamIdentifier</key><array><string>ABCDE12345</string></array>
        <key>ExpirationDate</key><date>#{expiration.utc.strftime('%Y-%m-%dT%H:%M:%SZ')}</date>
        <key>Entitlements</key><dict><key>application-identifier</key><string>ABCDE12345.#{bundle_id}</string></dict>
        <key>DeveloperCertificates</key><array>#{certificate_data}</array>
      </dict>
      </plist>
    PLIST
  end
end

describe 'signing_source option' do
  [Fastlane::Actions::EnsureCertificatesAction,
   Fastlane::Actions::EnsureProvisioningProfilesAction].each do |action|
    context action.name do
      let(:option) { action.available_options.find { |o| o.key == :signing_source } }

      it 'defaults to app_store_connect, so existing projects keep their behavior' do
        expect(option.default_value).to eq('app_store_connect')
        expect(option.env_name).to eq('SIGNING_SOURCE')
      end

      it 'accepts repository' do
        expect { option.verify_block.call('repository') }.not_to raise_error
      end

      it 'rejects unknown sources' do
        expect { option.verify_block.call('nope') }.to raise_error(FastlaneCore::Interface::FastlaneError)
      end

      it 'has a description that does not end with a period' do
        expect(option.description).not_to end_with('.')
      end
    end
  end
end

describe Fastlane::Actions::EncryptCertificateAction do
  include SigningSpecHelpers

  let(:storage) { Fastlane::Helper::AppleDevPortal::Certificates::Storage::CertificateStorage }

  before { allow(FastlaneCore::Helper).to receive(:is_ci?).and_return(false) }

  it 'stores the p12 encrypted, in the format ensure_certificates restores' do
    Dir.mktmpdir do |dir|
      p12_path, cert = write_p12(dir, password: 'secret')

      metadata = described_class.run(p12_path: p12_path, p12_password: 'secret', encryption_key: 'a-key',
                                     certificate_name: 'distribution', project_root: dir)

      expect(storage.encrypted_exists?(dir)).to be(true)
      expect(metadata['sha1']).to eq(OpenSSL::Digest::SHA1.hexdigest(cert.to_der).upcase)
      expect(metadata['common_name']).to eq('iPhone Distribution: Fueled')
      expect(storage.load_metadata(dir)['sha1']).to eq(metadata['sha1'])

      restored = OpenSSL::PKCS12.new(storage.restore_encrypted(dir, 'a-key'), described_class::STORAGE_P12_PASSWORD)
      expect(restored.certificate.to_der).to eq(cert.to_der)
    end
  end

  it 'generates a key and copies it to the clipboard when none is set' do
    Dir.mktmpdir do |dir|
      p12_path, = write_p12(dir, password: 'secret')
      copied = nil
      allow(Fastlane::Actions::GetCertificateEncryptionKeyAction).to receive(:copy_to_clipboard) { |key| copied = key }

      described_class.run(p12_path: p12_path, p12_password: 'secret', encryption_key: nil,
                          certificate_name: 'distribution', project_root: dir)

      expect(copied).not_to be_nil
      expect(storage.restore_encrypted(dir, copied)).not_to be_nil
    end
  end

  it 'writes nothing when the generated key cannot be copied to the clipboard' do
    Dir.mktmpdir do |dir|
      p12_path, = write_p12(dir, password: 'secret')
      allow(Fastlane::Actions::GetCertificateEncryptionKeyAction).to receive(:copy_to_clipboard)
        .and_raise(FastlaneCore::Interface::FastlaneError.new, 'no clipboard')

      expect do
        described_class.run(p12_path: p12_path, p12_password: 'secret', encryption_key: nil,
                            certificate_name: 'distribution', project_root: dir)
      end.to raise_error(FastlaneCore::Interface::FastlaneError)
      expect(storage.encrypted_exists?(dir)).to be(false)
      expect(Dir).not_to exist(File.join(dir, 'fastlane', 'certificates'))
    end
  end

  it 'requires the p12 password, so fastlane asks for it with hidden input' do
    option = described_class.available_options.find { |o| o.key == :p12_password }
    expect(option.optional).to be(false)
    expect(option.sensitive).to be(true)
    expect(option.default_value).to be_nil
  end

  it 'rejects a wrong p12 password' do
    Dir.mktmpdir do |dir|
      p12_path, = write_p12(dir, password: 'secret')
      expect do
        described_class.run(p12_path: p12_path, p12_password: 'wrong', encryption_key: 'a-key',
                            certificate_name: 'distribution', project_root: dir)
      end.to raise_error(FastlaneCore::Interface::FastlaneError, /Check the p12 password/)
    end
  end

  it 'rejects an expired certificate' do
    Dir.mktmpdir do |dir|
      p12_path, = write_p12(dir, password: 'secret', not_after: Time.now - 60)
      expect do
        described_class.run(p12_path: p12_path, p12_password: 'secret', encryption_key: 'a-key',
                            certificate_name: 'distribution', project_root: dir)
      end.to raise_error(FastlaneCore::Interface::FastlaneError, /expired/)
    end
  end

  it 'refuses to run on CI' do
    allow(FastlaneCore::Helper).to receive(:is_ci?).and_return(true)
    expect do
      described_class.run(p12_path: 'x.p12', p12_password: '', encryption_key: 'a-key',
                          certificate_name: 'distribution', project_root: Dir.pwd)
    end.to raise_error(FastlaneCore::Interface::FastlaneError, /locally/)
  end
end

describe Fastlane::Helper::AppleDevPortal::Certificates::CertificateManager do
  include SigningSpecHelpers

  let(:keychain_helper) { Fastlane::Helper::AppleDevPortal::Certificates::KeychainHelper }

  it 'restores from the repository without calling App Store Connect when restore_only is set' do
    Dir.mktmpdir do |dir|
      allow(FastlaneCore::Helper).to receive(:is_ci?).and_return(false)
      p12_path, = write_p12(dir, password: 'secret')
      Fastlane::Actions::EncryptCertificateAction.run(p12_path: p12_path, p12_password: 'secret', encryption_key: 'a-key',
                                                     certificate_name: 'distribution', project_root: dir)

      expect(Fastlane::Helper::AppStoreConnect::API).not_to receive(:fetch_certificates)
      allow(Fastlane::Helper::AppStoreConnect::Credentials).to receive(:get).and_raise('no App Store Connect credentials')
      allow(keychain_helper).to receive(:import_certificate_to_keychain)
      allow(keychain_helper).to receive(:certificate_exists_in_keychain?).and_return(true)

      info = described_class.ensure_distribution_certificate(
        keychain_name: 'test', keychain_password: 'test', project_root: dir,
        encryption_key: 'a-key', restore_only: true
      )

      expect(keychain_helper).to have_received(:import_certificate_to_keychain)
      expect(info[:name]).to eq('iPhone Distribution: Fueled')
    end
  end
end

describe Fastlane::Helper::AppleDevPortal::Profiles::RepositoryProfileInstaller do
  include SigningSpecHelpers

  around do |example|
    Dir.mktmpdir do |home|
      original_home = ENV['HOME']
      ENV['HOME'] = home
      example.run
    ensure
      ENV['HOME'] = original_home
    end
  end

  let(:uuid) { '0E8F5B2C-1A2B-4C3D-9E8F-0123456789AB' }

  def write_profile(dir, expiration: Time.now + (30 * 24 * 3600), file_name: 'enterprise.mobileprovision',
                    uuid: '0E8F5B2C-1A2B-4C3D-9E8F-0123456789AB', bundle_id: 'com.fueled.app', certificates: [])
    profiles_dir = File.join(dir, 'fastlane', 'profiles')
    FileUtils.mkdir_p(profiles_dir)
    path = File.join(profiles_dir, file_name)
    File.write(path, profile_plist(uuid: uuid, name: 'Enterprise Profile', bundle_id: bundle_id,
                                   expiration: expiration, certificates: certificates))
    path
  end

  def install(dir, **options)
    described_class.install(bundle_id: 'com.fueled.app', project_path: 'App.xcodeproj', search_path: dir, **options)
  end

  before { allow(Fastlane::Helper::AppleDevPortal::Profiles::ProfileDownloader).to receive(:update_xcode_project) }

  it 'installs the committed profile and points the Xcode project to it' do
    Dir.mktmpdir do |dir|
      write_profile(dir)

      info = described_class.install(bundle_id: 'com.fueled.app', project_path: File.join(dir, 'App.xcodeproj'), search_path: dir)

      expect(info).to include(uuid: uuid, name: 'Enterprise Profile', team_id: 'ABCDE12345')
      expect(File).to exist(File.join(ENV['HOME'], "Library/MobileDevice/Provisioning Profiles/#{uuid}.mobileprovision"))
      expect(Fastlane::Helper::AppleDevPortal::Profiles::ProfileDownloader).to have_received(:update_xcode_project)
        .with(project_path: File.join(dir, 'App.xcodeproj'), bundle_id: 'com.fueled.app', profile_uuid: uuid, team_id: 'ABCDE12345')
    end
  end

  it 'rejects an expired profile' do
    Dir.mktmpdir do |dir|
      write_profile(dir, expiration: Time.now - 60)
      expect { install(dir) }.to raise_error(FastlaneCore::Interface::FastlaneError, /expired/)
    end
  end

  it 'asks for profile_path when more than one profile is committed' do
    Dir.mktmpdir do |dir|
      write_profile(dir)
      write_profile(dir, file_name: 'other.mobileprovision')
      expect { install(dir) }.to raise_error(FastlaneCore::Interface::FastlaneError, /profile_path/)
    end
  end

  it 'passes the profile path literally, so a crafted file name cannot run commands' do
    Dir.mktmpdir do |dir|
      write_profile(dir, file_name: 'x$(touch pwned)`touch pwned`.mobileprovision')
      Dir.chdir(dir) { install(dir) }
      expect(File).not_to exist(File.join(dir, 'pwned'))
    end
  end

  it 'rejects a profile whose UUID is not a UUID, so it cannot write outside the profiles folder' do
    Dir.mktmpdir do |dir|
      write_profile(dir, uuid: '../../escape')
      expect { install(dir) }.to raise_error(FastlaneCore::Interface::FastlaneError, /invalid UUID/)
    end
  end

  it 'rejects a profile for another bundle id' do
    Dir.mktmpdir do |dir|
      write_profile(dir, bundle_id: 'com.other.app')
      expect { install(dir) }.to raise_error(FastlaneCore::Interface::FastlaneError, /doesn't match/)
    end
  end

  it 'accepts a wildcard profile only when its prefix matches the bundle id' do
    Dir.mktmpdir do |dir|
      write_profile(dir, bundle_id: 'com.fueled.*')
      expect { install(dir) }.not_to raise_error
    end
    Dir.mktmpdir do |dir|
      write_profile(dir, bundle_id: 'com.acme.*')
      expect { install(dir) }.to raise_error(FastlaneCore::Interface::FastlaneError, /doesn't match/)
    end
  end

  it 'accepts a profile that includes the restored certificate' do
    Dir.mktmpdir do |dir|
      _, cert = self_signed_certificate(common_name: 'iPhone Distribution: Fueled')
      write_profile(dir, certificates: [cert])
      sha1 = OpenSSL::Digest::SHA1.hexdigest(cert.to_der)
      expect { install(dir, certificate_sha1: sha1) }.not_to raise_error
    end
  end

  it 'rejects a profile that does not include the restored certificate' do
    Dir.mktmpdir do |dir|
      _, cert = self_signed_certificate(common_name: 'iPhone Distribution: Fueled')
      _, other = self_signed_certificate(common_name: 'iPhone Distribution: Other')
      write_profile(dir, certificates: [other])
      expect { install(dir, certificate_sha1: OpenSSL::Digest::SHA1.hexdigest(cert.to_der)) }
        .to raise_error(FastlaneCore::Interface::FastlaneError, /doesn't include the signing certificate/)
    end
  end
end
