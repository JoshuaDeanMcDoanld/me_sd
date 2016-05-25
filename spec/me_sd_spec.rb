require_relative "../lib/me_sd"

RSpec.describe MESD do
  describe "sd" do
    require "yaml"
    sd_data = YAML.load_file("spec/sd_data.yml")
    host = sd_data["host"]
    port = sd_data["port"]
    username = sd_data["username"]
    password = sd_data["password"]
    sd = MESD.new({ host: host, port: port, username: username, password: password })

    it "should create sd sessions" do
      expect(!!sd).to be true
    end

    it "should get all requests" do
      all_requests = sd.get_all_requests
      all_requests_size = sd_data["all_requests_size"]
      expect(all_requests.size).to eq(all_requests_size)
    end

    it "should get last n requests" do
      last_requests = sd.get_last_requests(10)
      expect(last_requests.size).to eq(10)
      p last_requests[0]
    end

    it "should get custom request data" do
      good_request_data = sd_data["good_request"]
      good_request = Request.new({ session: sd.session, id: good_request_data["id"] })
      expect(!!good_request).to be true
      expect(good_request.data.name).to eq(good_request_data["name"])
      expect(good_request.name).to eq(good_request_data["name"])
      expect(good_request.description).to eq(good_request_data["description"])
      expect(good_request.resolution).to eq(good_request_data["resolution"])
      expect(good_request.resolution).to eq(good_request_data["resolution"])
      expect(good_request.status).to eq(good_request_data["status"])
      expect(good_request.priority).to eq(good_request_data["priority"])
      expect(good_request.author_name).to eq(good_request_data["author_name"])
      require "date"
      expect(good_request.create_date).to eq(DateTime.parse(good_request_data["create_date"]))
      # reset request data
      good_request = Request.new({ session: sd.session, id: good_request_data["id"] })
      expect(good_request.data(:name, :resolution).name).to eq(good_request_data["name"])
      expect(good_request.data(:name, :resolution).resolution).to eq(good_request_data["resolution"])
      expect(good_request.data(:name, :resolution).description).to be nil
    end

    it "should rescue bad custom request errors" do
      bad_request_data = sd_data["bad_request"]
      bad_request = Request.new({ session: sd.session, id: bad_request_data["id"] })
      expect(bad_request.data).to be false
      expect(!!bad_request.last_error).to be true
    end

    it "should rescue session errors" do
      print "Waiting for timeout..."
      sd_error = MESD.new({ host: "#{host}/error", port: port, username: username, password: password })
      expect(!!sd_error.last_error).to be true
    end
  end
end
