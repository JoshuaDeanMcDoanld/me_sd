# usage:
#
# sd = ServiceDesk.new("192.168.0.150", "8080", "user", "P@ssw0rd")
# => true
# unless sd.errors
#   requests = sd.get_all_requests
#   sd.get_request_data(requests[0])
#   requests[0]
# end
# => #<ServiceDesk::Request:0x0000000265d360 @id="29", @description="request decription", @resolution="request resolution">
# request = ServiceDesk::Request.new({id: "117711"})
# sd.get_request_data(request)
# sd.last_error
# => "auth error"

class ServiceDesk
  attr_accessor :session, :errors, :curobj, :current_body, :requests, :last_error

  HEADERS = {
    "User-Agent" => "Mozilla/5.0 (Windows NT 6.1; rv:22.0) Gecko/20100101 Firefox/22.0",
    "Accept" => "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language" => "ru-RU,ru;q=0.8,en-US;q=0.5,en;q=0.3",
    "Accept-Encoding" => "gzip, deflate",
    "Connection:" => "keep-alive",
  }

  def initialize(host, port = 80, username, password)
    require "net/http"
    uri = URI("http://#{host}:#{port}")
    Net::HTTP.start(uri.host, uri.port) do |http|
      request = http.get(uri)
      cookie = request.response["set-cookie"]
      uri = "#{uri}/j_security_check"
      auth_data = ""\
        "j_username=#{username}&"\
        "j_password=#{password}&"\
        "AdEnable=false&"\
        "DomainCount=0&"\
        "LDAPEnable=false&"\
        "LocalAuth=No&"\
        "LocalAuthWithDomain=No&"\
        "dynamicUserAddition_status=true&"\
        "hidden=Select+a+Domain&"\
        "hidden=For+Domain&"\
        "localAuthEnable=true&"\
        "loginButton=Login&"\
        "logonDomainName=-1&"\
      ""
      auth_headers = {
        "Referer" => "http://#{host}:#{port}",
        "Host" => "#{host}:#{port}",
        "Cookie" => "#{cookie};",
      }.merge(HEADERS)
      request = http.post(uri, auth_data, auth_headers)
      @session = {
        host: host,
        port: port,
        cookie: cookie,
      }
      @errors = ["Wrong username or password"] unless self.session_healthy?
    end
  end

  # logs in and tries to find out is session healthy
  # criteria: logout button is present
  def session_healthy?
    session = self.session
    session_healthy = false
    uri = URI("http://#{session[:host]}:#{session[:port]}/MySchedule.do")
    Net::HTTP.start(uri.host, uri.port) do |http|
      request = Net::HTTP::Get.new(uri)
      request.add_field("Cookie", "#{session[:cookie]}")
      request = http.request(request)
      # ...
      # <a style="display:inline" href="\&quot;javascript:" prelogout('null')\"="">Log out</a>
      # ...
      session_healthy = true if /preLogout/.match(request.body)
    end
    session_healthy
  end

  def get_all_requests
    @requests = Array.new
    select_all_requests
    puts "Getting total #{@curobj['_TL']} requests:"
    get_requests_urls(@current_body).each { |url| @requests.push(Request.new({url: url})) }
    begin
      not_last_page = next_page
      get_requests_urls(@current_body).each { |url| @requests.push(Request.new({url: url})) }
    end while not_last_page
    @requests
  end

  def select_all_requests
    session = self.session
    uri = URI("http://#{session[:host]}:#{session[:port]}/WOListView.do")
    Net::HTTP.start(uri.host, uri.port) do |http|
      data = "globalViewName=All_Requests&viewName=All_Requests"
      headers = {
        "Referer" => "http://#{session[:host]}:#{session[:port]}/WOListView.do",
        "Host" => "#{session[:host]}:#{session[:port]}",
        "Cookie" => "#{session[:cookie]}",
      }.merge(HEADERS)
      request = http.post(uri, data, headers)
      @current_body = request.response.body
      @curobj = get_curobj(@current_body)
    end
  end

  def next_page
    require "date"
    session = self.session
    # 13 digits time
    timestamp = DateTime.now.strftime("%Q")
    uri = URI("http://#{session[:host]}:#{session[:port]}/STATE_ID/#{timestamp}/"\
      "RequestsView.cc?UNIQUE_ID=RequestsView&SUBREQUEST=true")
    Net::HTTP.start(uri.host, uri.port) do |http|
      request = Net::HTTP::Get.new(uri)
      request.add_field("Referer", "http://#{session[:host]}:#{session[:port]}/WOListView.do")
      @curobj = get_curobj(@current_body)
      return false unless @curobj
      print "#{(@curobj["_FI"].to_f / @curobj["_TL"].to_f * 100).round}%.."
      # increment page number
      @curobj["_PN"] = (@curobj["_PN"].to_i + 1).to_s
      # update first item
      @curobj["_FI"] = (@curobj["_FI"].to_i + @curobj["_PL"].to_i).to_s
      # @curobj.flatten.join("/") =>
      # "_PN/2/_PL/25/_TL/28/globalViewName/All_Requests/_TI/25/_FI/1/_SO/D/viewName/All_Requests"
      request.add_field("Cookie",
        "#{session[:cookie]}; "\
        "STATE_COOKIE=%26RequestsView/ID/#{@curobj['ID']}/VGT/#{timestamp}/#{@curobj.flatten.join('/')}"\
        "/_VMD/1/ORIGROOT/#{@curobj['ID']}%26_REQS/_RVID/RequestsView/_TIME/#{timestamp}; "\
        "301RequestsshowThreadedReq=showThreadedReqshow; "\
        "301RequestshideThreadedReq=hideThreadedReqhide"\
        ""
      )
      request = http.request(request)
      @current_body = request.response.body
    end
    # if (first item + per page) > total items then it is the last page
    return false if (@curobj["_FI"].to_i + @curobj["_PL"].to_i) > @curobj["_TL"].to_i
    true
  end

  def get_curobj(body)
    # somewhere in body
    # "<Script>curObj=V33;curObj[\"_PN\"]=\"1\";curObj[\"_PL\"]=\"25\";curObj[\"_TL\"]=\"28\";"\
    # "curObj[\"globalViewName\"]=\"All_Requests\";curObj[\"_TI\"]=\"25\";curObj[\"_FI\"]=\"1\";"\
    # "curObj[\"_SO\"]=\"D\";curObj[\"viewName\"]=\"All_Requests\";</Script>"
    curobj_start_pos = body.index(/<Script>curObj=/)
    v = /<Script>curObj=V(?<V>\d+);/.match(body)["V"]
    return false unless curobj_start_pos
    curobj_end_pos = body.index("</Script>", curobj_start_pos)
    curobj_raw = body[curobj_start_pos + "<Script>curObj=".size + v.size...curobj_end_pos]
    # curobj_raw =>
    # "curObj[\"_PN\"]=\"1\";curObj[\"_PL\"]=\"25\";curObj[\"_TL\"]=\"28\";"\
    # "curObj[\"globalViewName\"]=\"All_Requests\";curObj[\"_TI\"]=\"25\";curObj[\"_FI\"]=\"1\";"\
    # "curObj[\"_SO\"]=\"D\";curObj[\"viewName\"]=\"All_Requests\";"
    curObj = Hash.new
    curobj_raw.split(";").each { |c| eval(c) }
    curObj["ID"] = v
    # curObj =>
    # {"_PN"=>"1", "_PL"=>"25", "_TL"=>"28", "globalViewName"=>"All_Requests",
    # "_TI"=>"25", "_FI"=>"1", "_SO"=>"D", "viewName"=>"All_Requests"}
    curObj
  end

  def get_requests_urls(body)
    urls = body.scan(/href=\"WorkOrder\.do\?woMode=viewWO&woID=\d+&&fromListView=true\"/)
    # drop href=" and ending quot
    urls.each_with_index { |url, i| urls[i] = url["href=\"".size..-2] }
    urls
  end

  def get_request_data(request)
    if session_healthy?
      properties = [
        {
          name: "description",
          url: "WorkOrder.do?woMode=viewWO&woID=#{request.id}",
          search_algorithm: {
            name: "between_strings",
            lower_bound: "<td style=\"padding-left:10px;\" colspan=\"3\" valign=\"top\" class=\"fontBlack textareadesc\">",
            upper_bound: "</td>",
          },
        },
        {
          name: "resolution",
          url: "AddResolution.do?mode=viewWOResolution&woID=#{request.id}",
          search_algorithm: {
            name: "between_strings",
            lower_bound: "<td colspan=\"3\" valign=\"top\" class=\"fontBlack textareadesc\">",
            upper_bound: "</td>",
          },
        },
      ]
      properties.each do |property|
        uri = URI("http://#{@session[:host]}:#{@session[:port]}/#{property[:url]}")
        Net::HTTP.start(uri.host, uri.port) do |http|
          http_request = Net::HTTP::Get.new(uri)
          http_request.add_field("Cookie", "#{@session[:cookie]}")
          http_request = http.request(http_request)
          body = http_request.response.body
          auth_error_pos = body.index("AuthError")
          if auth_error_pos
            @last_error = "auth error"
            return false
          end
          operational_error_pos = body.index("failurebox")
          if operational_error_pos
            @last_error = "operational error"
            return false
          end
          if property[:search_algorithm][:name] == "between_strings"
            search_start_pos = body.index(property[:search_algorithm][:lower_bound])
            search_end_pos = body.index(property[:search_algorithm][:upper_bound], search_start_pos)
            value = body[search_start_pos + property[:search_algorithm][:lower_bound].size..search_end_pos-1]
            # value => "\n\t\t\t\t\tVALUE\n\t\t\t\t"
            value = value.force_encoding("UTF-8").strip
            # value => "VALUE"
            request.send("#{property[:name]}=", value)
          end
        end
      end
      request
    else
      @last_error = "session error"
      return false
    end
  end

  private :select_all_requests, :next_page, :get_curobj, :get_requests_urls

  class Request
    attr_accessor :id, :description, :resolution

    def initialize(args)
      if args[:url]
        @id = args[:url][/WorkOrder\.do\?woMode=viewWO&woID=(?<ID>\d+)&&fromListView=true/, "ID"]
      elsif args[:id]
        @id = args[:id]
      end
    end
  end
end
