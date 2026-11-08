Pod::Spec.new do |s|
  s.name             = 'tevel_push'
  s.version          = '0.1.0'
  s.summary          = 'Direct APNs registration for the Tevel invoice app.'
  s.homepage         = 'https://tevel.space'
  s.license          = { :type => 'Proprietary' }
  s.author           = { 'Tevel' => 'support@tevel.space' }
  s.source           = { :path => '.' }
  s.source_files     = 'tevel_push/Sources/tevel_push/**/*.swift'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.swift_version = '5.0'
end
