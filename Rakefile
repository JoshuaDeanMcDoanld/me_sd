require "rake"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

task :default  => :spec


# task :default  => :test
#
# task :test do
#   require_relative "lib/me_sd"
#   require "yaml"
#   sd_data = YAML.load_file("sd_data.yml")
#   host = sd_data["host"]
#   port = sd_data["port"]
#   username = sd_data["username"]
#   password = sd_data["password"]
#   id1 = sd_data["id1"]
#   sd = MESD.new({ host: host, port: port, username: username, password: password })
#   unless sd.last_error
#     request = Request.new({ session: sd.session, id: id1 })
#     requests = sd.get_all_requests
#     requests = sd.get_last_requests(100)
#     # request = Request.new({ session: sd.session, id: 322959 }) # no resolution
#     # request = Request.new({ session: sd.session, id: 321359 }) # normal
#     # request = Request.new({ session: sd.session, id: 107711 }) # no privileges
#     # request = Request.new({ session: sd.session, id: "asd" }) # wrong id
#     # p request.data(:resolution).resolution
#     # p request.last_error
#     # p request.data
#     # p request.resolution
#     # p request.get_resolution
#     # request = ServiceDesk::Request.new("320894")
#     # request = ServiceDesk::Request.new({id: "107711"})
#     # request = ServiceDesk::Request.new({id: "asd"})
#
#
#     # p requests.size
#     # p requests[0].data
#     # p requests[0].data(:resolution)
#     # p requests[0].data
#   end
#   p sd
# end
