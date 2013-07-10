Pod::Spec.new do |s|
  s.name = 'MUKAdMobViewController'
  s.platform = :ios, '6.0'
  s.version = '1.0'
  s.summary = 'View controller with an AdMob banner.'
  s.homepage = 'https://bitbucket.org/muccy/mukadmobviewcontroller'
  s.author = {
    'Marco Muccinelli' => 'muccymac@gmail.com'
  }
  
  s.license = {
    :type => 'Internal',
    :text => 'Internal usage only.'
  }

  s.source = {
    :git => 'https://muccy@bitbucket.org/muccy/mukadmobviewcontroller.git',
    :tag => s.version.to_s
  }

  s.requires_arc = true
  s.source_files = 'MUKAdMobViewController/*.{h,m}'
  s.dependency 'AdMob', '~>6.4'
end