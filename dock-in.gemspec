# coding: utf-8
Gem::Specification.new do |s|
  s.name        = 'dock-in'
  s.version     = '0.0.1'
  s.date        = '2015-09-10'
  s.summary     = "Dock in you containers to Apache and Drush"
  s.description = "Dock-in creates Apache vhosts and drush aliases for your running container."
  s.authors     = ["Arne Jørgensen"]
  s.email       = 'arne@arnested.dk'
  s.files       = ["lib/dock-in.rb"]
  s.homepage    = 'https://arnested.dk'
  s.license     = 'MIT'
  s.executables << 'dock-in'
  s.add_runtime_dependency 'docker-api', '~> 1.22'
  s.add_runtime_dependency 'json', '~> 1.8'
  s.add_runtime_dependency 'terminal-notifier', '~> 1.6'
  s.add_runtime_dependency 'ffi-rzmq', '~> 2.0'
end
