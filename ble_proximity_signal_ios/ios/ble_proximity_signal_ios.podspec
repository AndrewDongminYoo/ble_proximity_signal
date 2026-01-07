#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#
Pod::Spec.new do |s|
  s.name             = 'ble_proximity_signal_ios'
  s.version          = '0.1.0'
  s.summary          = 'An iOS implementation of the ble_proximity_signal plugin.'
  s.description      = <<-DESC
  An iOS implementation of the ble_proximity_signal plugin.
                       DESC
  s.homepage         = 'https://andrewdongminyoo.vercel.app'
  s.license          = { :type => 'BSD', :file => '../LICENSE' }
  s.author           = { 'Dongmin, Yu' => 'ydm2790@gmail.com' }
  s.source           = { :path => '.' }  
  s.source_files = 'ble_proximity_signal_ios/Sources/**/*.swift'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '6.1'
end
