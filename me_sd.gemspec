Gem::Specification.new do |s|
  s.name        = "me_sd"
  s.version     = "0.2"
  s.date        = "2016-06-2"
  s.summary     = "ManageEngine ServiceDesk Plus gem"
  s.description = "Introduces 'MESD' class that works with ManageEngine ServiceDesk Plus without API access."
  s.authors     = ["Alexander Morozov"]
  s.email       = "ntcomp12@gmail.com"
  s.files       = ["lib/me_sd.rb"]
  s.homepage    = "https://github.com/kengho/me_sd"
  s.license     = "MIT"

  s.add_runtime_dependency "nokogiri", "~> 1"
end
