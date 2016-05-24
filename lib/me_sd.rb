# usage:
#
# sd = MESD.new("192.168.0.150", "8080", "user", "P@ssw0rd")
# => true
# unless sd.errors
#   requests = sd.get_all_requests
#   sd.get_request_data(requests[0])
#   requests[0]
# end
# => #<MESD::Request:0x0000000265d360 @id="29", @description="request decription", @resolution="request resolution", ...>
# request = MESD::Request.new({id: "117711"})
# sd.get_request_data(request)
# sd.last_error
# => "auth error"
# sd.get_request_data({ request: request, only: ["name"] })
# => #<MESD::Request:0x000000023b6800 @id="29", @name="my_request">

class MESD
  attr_accessor :session, :last_error, :curobj, :current_body, :requests

  require "net/http"
  EXCEPTIONS = [Timeout::Error, Errno::EINVAL, Errno::ECONNRESET, Errno::EHOSTUNREACH, EOFError,
   Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError, Net::ProtocolError]

  def initialize(host, port = 80, username, password)
    uri = URI("http://#{host}:#{port}")
    begin
      Net::HTTP.start(uri.host, uri.port) do |http|
        p "here1"
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
        }
        request = http.post(uri, auth_data, auth_headers)
        @session = {
          host: host,
          port: port,
          cookie: cookie,
        }
        @last_error = "wrong credentials" unless self.session_healthy?
      end
    rescue *EXCEPTIONS => @last_error
    end
  end

  # logs in and tries to find out is session healthy
  # criteria: logout button is present
  def session_healthy?
    session = self.session
    return false unless session
    session_healthy = false
    uri = URI("http://#{session[:host]}:#{session[:port]}/MySchedule.do")
    begin
      Net::HTTP.start(uri.host, uri.port) do |http|
        request = Net::HTTP::Get.new(uri)
        request.add_field("Cookie", "#{session[:cookie]}")
        request = http.request(request)
        # ...
        # <a style="display:inline" href="\&quot;javascript:" prelogout('null')\"="">Log out</a>
        # ...
        session_healthy = true if /preLogout/.match(request.body)
      end
    rescue *EXCEPTIONS => @last_error
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
    return false unless session
    uri = URI("http://#{session[:host]}:#{session[:port]}/WOListView.do")
    begin
      Net::HTTP.start(uri.host, uri.port) do |http|
        data = "globalViewName=All_Requests&viewName=All_Requests"
        headers = {
          "Referer" => "http://#{session[:host]}:#{session[:port]}/WOListView.do",
          "Host" => "#{session[:host]}:#{session[:port]}",
          "Cookie" => "#{session[:cookie]}",
        }
        request = http.post(uri, data, headers)
        @current_body = request.response.body
        @curobj = get_curobj
      end
    rescue *EXCEPTIONS => @last_error
    end
  end

  def next_page
    require "date"
    session = self.session
    return false unless session
    # 13 digits time
    timestamp = DateTime.now.strftime("%Q")
    uri = URI("http://#{session[:host]}:#{session[:port]}/STATE_ID/#{timestamp}/"\
      "RequestsView.cc?UNIQUE_ID=RequestsView&SUBREQUEST=true")
    begin
      Net::HTTP.start(uri.host, uri.port) do |http|
        request = Net::HTTP::Get.new(uri)
        request.add_field("Referer", "http://#{session[:host]}:#{session[:port]}/WOListView.do")
        @curobj = get_curobj
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
    rescue *EXCEPTIONS => @last_error
    end
    # if (first item + per page) > total items then it is the last page
    if (@curobj["_FI"].to_i + @curobj["_PL"].to_i) > @curobj["_TL"].to_i
      print "100%.."
      return false
    end
    true
  end

  def get_curobj
    body = @current_body
    # somewhere in body
    # "<Script>curObj=V33;curObj[\"_PN\"]=\"1\";curObj[\"_PL\"]=\"25\";curObj[\"_TL\"]=\"28\";"\
    # "curObj[\"globalViewName\"]=\"All_Requests\";curObj[\"_TI\"]=\"25\";curObj[\"_FI\"]=\"1\";"\
    # "curObj[\"_SO\"]=\"D\";curObj[\"viewName\"]=\"All_Requests\";</Script>"
    search_start_str = "<Script>curObj=V"
    curobj_start_pos = body.index(search_start_str)
    return false unless curobj_start_pos
    v = /<Script>curObj=V(?<V>\d+);/.match(body)["V"]
    curobj_end_pos = body.index("</Script>", curobj_start_pos)
    curobj_raw = body[curobj_start_pos + search_start_str.size + v.size...curobj_end_pos]
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
  end

  def get_request_data(args)
    unless session_healthy?
      @last_error = "session error"
      return false
    end
    if args.class == MESD::Request
      request = args
      only = []
    elsif args.class == Hash
      request = args[:request]
      only = defined?(args[:only]) ? args[:only] : []
    end
    properties = [
      {
        name: "description",
        url: "WorkOrder.do?woMode=viewWO&woID=#{request.id}",
        search_function: {
          name: "value_between_strings",
          args: ["<td style=\"padding-left:10px;\" colspan=\"3\" valign=\"top\" class=\"fontBlack textareadesc\">", "</td>"],
        },
        post_processing_functions: [:strip],
      },
      {
        name: "resolution",
        url: "AddResolution.do?mode=viewWOResolution&woID=#{request.id}",
        search_function: {
          name: "value_between_strings",
          args: ["<td colspan=\"3\" valign=\"top\" class=\"fontBlack textareadesc\">", "</td>"],
        },
        post_processing_functions: [:strip],
      },
      {
        name: "status",
        url: "WorkOrder.do?woMode=viewWO&woID=#{request.id}",
        search_function: {
          name: "html_parse",
          args: [["css", "#WOHeaderSummary_DIV"], ["css", "#status_PH"], "text"],
        },
        post_processing_functions: [:semicolon_space_value, :symbolize],
      },
      {
        name: "priority",
        url: "WorkOrder.do?woMode=viewWO&woID=#{request.id}",
        search_function: {
          name: "html_parse",
          args: [["css", "#WOHeaderSummary_DIV"], ["css", "#priority_PH"], "text"],
        },
        post_processing_functions: [:semicolon_space_value, :symbolize],
      },
      {
        name: "author_name",
        url: "WorkOrder.do?woMode=viewWO&woID=#{request.id}",
        search_function: {
          name: "html_parse",
          args: [["css", "#requesterName_PH"], "text"],
        },
      },
      {
        name: "create_date",
        url: "WorkOrder.do?woMode=viewWO&woID=#{request.id}",
        search_function: {
          name: "html_parse",
          args: [["css", "#CREATEDTIME_CUR"], "text"],
        },
      },
      {
        name: "name",
        url: "WorkOrder.do?woMode=viewWO&woID=#{request.id}",
        search_function: {
          name: "html_parse",
          args: [["css", "#requestSubject_ID"], "text"],
        },
        post_processing_functions: [:strip],
      },
    ]
    properties.each do |property|
      next if !only.empty? && !only.include?(property[:name])
      uri = URI("http://#{@session[:host]}:#{@session[:port]}/#{property[:url]}")
      begin
        Net::HTTP.start(uri.host, uri.port) do |http|
          http_request = Net::HTTP::Get.new(uri)
          http_request.add_field("Cookie", "#{@session[:cookie]}")
          http_request = http.request(http_request)
          @current_body = http_request.response.body
          auth_error_pos = @current_body.index("AuthError")
          if auth_error_pos
            @last_error = "auth error"
            return false
          end
          operational_error_pos = @current_body.index("failurebox")
          if operational_error_pos
            @last_error = "operational error"
            return false
          end
          value = self.method(property[:search_function][:name]).call(property[:search_function][:args])
          if property[:post_processing_functions]
            functions = property[:post_processing_functions]
            functions.each do |function|
              if value.methods.include?(function)
                value = value.method(function).call
              elsif self.private_methods.include?(function)
                value = self.method(function).call(value)
              end
            end
          end
          request.send("#{property[:name]}=", value)
        end
      rescue *EXCEPTIONS => @last_error
      end
    end
    request
  end

  def html_parse(steps)
    require "nokogiri"
    value = Nokogiri::HTML(@current_body)
    Array(steps).each { |step| value = value.send(*step) }
    value
  end

  def value_between_strings(bounds)
    search_start_pos = @current_body.index(bounds[0])
    return false unless search_start_pos
    search_end_pos = @current_body.index(bounds[1], search_start_pos)
    @current_body[search_start_pos + bounds[0].size..search_end_pos-1].force_encoding("UTF-8")
  end

  def semicolon_space_value(value)
    value.strip[/:(.*)/m, 1].strip
  end

  def symbolize(value)
    matching = {
      # status
      :open => ["Открыта", "Open"],
      :on_hold => ["Ожидание", "On Hold"],
      :resolved => ["Решена", "Resolved"],
      :closed => ["Закрыта", "Closed"],
      :rejected => ["Отклонена", ""],
      # priority
      :minimal => ["Минимальный", ""],
      :low => ["Низкий", "Low"],
      :normal => ["", "Normal"],
      :medium => ["Средний", "Medium"],
      :high => ["Высокий", "High"],
      :highest => ["Наивысший", ""],
    }
    matching.each do |result, candidates|
      return result if candidates.include?(value)
    end
    false
  end

  private :select_all_requests, :next_page, :get_curobj, :get_requests_urls,
    :html_parse, :value_between_strings, :semicolon_space_value, :symbolize

end

class Request < MESD
  attr_accessor :id, :name, :author_name, :status, :priority, :create_date, :description, :resolution

  def initialize(arg)
    if arg =~ /^\d+$/
      @id = arg
    elsif arg =~ /WorkOrder\.do\?woMode=viewWO&woID=(?<ID>\d+)&&fromListView=true/
      @id = Regexp.last_match(:ID)
    end
  end
end
