platform :ios, '15.0'

target 'PeerTutor' do
  use_frameworks!

  # Firebase dependencies
  pod 'Firebase'
  pod 'FirebaseCore'
  pod 'FirebaseAuth'
  pod 'FirebaseFirestore'
  pod 'FirebaseStorage'
  pod 'FirebaseFirestoreSwift'

  post_install do |installer|
    installer.pods_project.targets.each do |target|
      # Apply specific settings for the BoringSSL-GRPC target
      if target.name == 'BoringSSL-GRPC'
        target.source_build_phase.files.each do |file|
          if file.settings && file.settings['COMPILER_FLAGS']
            flags = file.settings['COMPILER_FLAGS'].split
            # Remove '-GCC_WARN_INHIBIT_ALL_WARNINGS' flag
            flags.reject! { |flag| flag == '-GCC_WARN_INHIBIT_ALL_WARNINGS' }
            file.settings['COMPILER_FLAGS'] = flags.join(' ')
          end
        end
      end

      # General settings for all targets
      target.build_configurations.each do |config|
        # Set iOS deployment target
        config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
        
        
        # Disable code signing for pods
        config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
        config.build_settings['CODE_SIGNING_REQUIRED'] = 'NO'
        config.build_settings['CODE_SIGNING_IDENTITY'] = '-'
        
        # M1/M2 Mac compatibility settings
        config.build_settings['EXCLUDED_ARCHS[sdk=iphonesimulator*]'] = 'arm64'
        config.build_settings['ONLY_ACTIVE_ARCH'] = 'YES'
        config.build_settings['BUILD_LIBRARY_FOR_DISTRIBUTION'] = 'YES'
      end
    end
  end
end
