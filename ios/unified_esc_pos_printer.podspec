Pod::Spec.new do |s|
  s.name             = 'unified_esc_pos_printer'
  s.version          = '1.0.0'
  s.summary          = 'Native Bluetooth support for unified_esc_pos_printer Flutter plugin.'
  s.description      = <<-DESC
Native BLE implementation for ESC/POS thermal printers on iOS using CoreBluetooth.
                       DESC
  s.homepage         = 'https://github.com/elrizwiraswara/unified_esc_pos_printer'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'Elriz Wiraswara' => 'contact@elriztechnology.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'unified_esc_pos_printer/Sources/unified_esc_pos_printer/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '13.0'
  s.swift_version    = '5.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
