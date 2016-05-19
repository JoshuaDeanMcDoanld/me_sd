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

class ServiceDesk
  attr_accessor :session, :errors, :curobj, :current_body, :requests

  HEADERS = {
    "User-Agent" => "Mozilla/5.0 (Windows NT 6.1; rv:22.0) Gecko/20100101 Firefox/22.0",
    "Accept" => "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language" => "ru-RU,ru;q=0.8,en-US;q=0.5,en;q=0.3",
    "DNT" => "1",
    "Connection:" => "keep-alive",
  }
  REQUESTS_PER_PAGE = 25

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
    get_requests_urls(@current_body).each { |url| @requests.push(Request.new(url)) }
    begin
      not_last_page = next_page
      get_requests_urls(@current_body).each { |url| @requests.push(Request.new(url)) }
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
      # increment page number
      @curobj["_PN"] = (@curobj["_PN"].to_i + 1).to_s
      # update first item
      @curobj["_FI"] = (@curobj["_FI"].to_i + REQUESTS_PER_PAGE).to_s
      # @curobj.flatten.join("/") =>
      # "_PN/2/_PL/25/_TL/28/globalViewName/All_Requests/_TI/25/_FI/1/_SO/D/viewName/All_Requests"
      request.add_field("Cookie",
        "#{session[:cookie]}; "\
        "STATE_COOKIE=%26RequestsView/ID/33/VGT/#{timestamp}/#{@curobj.flatten.join('/')}"\
        "/_VMD/1/ORIGROOT/33%26_REQS/_RVID/RequestsView/_TIME/#{timestamp}; "\
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
    curobj_start_pos = body.index("<Script>curObj=V33;")
    return false unless curobj_start_pos
    curobj_end_pos = body.index("</Script>", curobj_start_pos)
    curobj_raw = body[curobj_start_pos + "<Script>curObj=V33;".size...curobj_end_pos]
    # curobj_raw =>
    # "curObj[\"_PN\"]=\"1\";curObj[\"_PL\"]=\"25\";curObj[\"_TL\"]=\"28\";"\
    # "curObj[\"globalViewName\"]=\"All_Requests\";curObj[\"_TI\"]=\"25\";curObj[\"_FI\"]=\"1\";"\
    # "curObj[\"_SO\"]=\"D\";curObj[\"viewName\"]=\"All_Requests\";"
    curObj = Hash.new
    curobj_raw.split(";").each { |c| eval(c) }
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
      # description
      uri = URI("http://#{@session[:host]}:#{@session[:port]}/WorkOrder.do?woMode=viewWO&woID=#{request.id}")
      Net::HTTP.start(uri.host, uri.port) do |http|
        http_request = Net::HTTP::Get.new(uri)
        http_request.add_field("Cookie", "#{session[:cookie]}")
        http_request = http.request(http_request)
        body = http_request.response.body
        # body =>
        # <td style=\"padding-left:10px;\" colspan=\"3\" valign=\"top\" class=\"fontBlack textareadesc\">
        # \n\n\t\t\t\tDESCRIPTION\n\t\t\t\t
        # </td>
        search_place_start = "<td style=\"padding-left:10px;\" colspan=\"3\" valign=\"top\" class=\"fontBlack textareadesc\">"
        search_place_end = "</td>"
        search_place_start_pos = body.index(search_place_start)
        search_place_end_pos = body.index(search_place_end, search_place_start_pos)
        request.description = body[search_place_start_pos + search_place_start.size..search_place_end_pos-1]
        # request.description => "\n\t\t\t\t\tDESCRIPTION\n\t\t\t\t"
        request.description = request.description.gsub(/\s+/, "")
        # request.description => "DESCRIPTION"
      end
      # resolution
      uri = URI("http://#{@session[:host]}:#{@session[:port]}/AddResolution.do?mode=viewWOResolution&woID=#{request.id}")
      Net::HTTP.start(uri.host, uri.port) do |http|
        http_request = Net::HTTP::Get.new(uri)
        http_request.add_field("Cookie", "#{session[:cookie]}")
        http_request = http.request(http_request)
        body = http_request.response.body
        # body =>
        # ...
        # <td colspan=\"3\" valign=\"top\" class=\"fontBlack textareadesc\">
        # \n\t\t\t\t\tRESOLUTION\n\t\t\t\t
        # </td>
        # ...
        search_place_start = "<td colspan=\"3\" valign=\"top\" class=\"fontBlack textareadesc\">"
        search_place_end = "</td>"
        search_place_start_pos = body.index(search_place_start)
        search_place_end_pos = body.index(search_place_end, search_place_start_pos)
        request.resolution = body[search_place_start_pos + search_place_start.size..search_place_end_pos-1]
        # request.resolution => "\n\t\t\t\t\tRESOLUTION\n\t\t\t\t"
        request.resolution = request.resolution.gsub(/\s+/, "")
        # request.resolution => "RESOLUTION"
      end
      true
    else
      return false
    end
  end

  private :select_all_requests, :next_page, :get_curobj, :get_requests_urls

  class Request
    attr_accessor :id, :resolution, :description

    def initialize(url)
      @id = url[/WorkOrder\.do\?woMode=viewWO&woID=(?<ID>\d+)&&fromListView=true/, "ID"]
    end
  end
end
