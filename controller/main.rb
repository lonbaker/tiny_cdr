require 'date'
class MainController < Controller
  layout :main
  helper :xhtml
  engine :Erubis

  # the index action is called automatically when no other action is specified
  def index
    @head  = '<script type="text/javascript" src="/js/index.js"></script>'
    @title = "TinyCDR - FreeSWITCH CDR Reporting"
  end

  def user_report
    start, stop = request[:date_start, :date_end]
    username, phone_num = request[:username, :phone_num].map{|s| s.to_s.strip }
    username = nil if username.empty?
    phone_num = nil if phone_num.empty?
    @title = "Call Detail"
    @title << " for #{username}" unless username.nil?
    avoid_locals = (request[:avoid_locals].empty? ? false : true) rescue nil

    ds = TinyCdr::Call.user_report(start, stop, {:username => username,
                                                 :phone    => phone_num,
                                                 :avoid_locals => avoid_locals})
    @calls = ds.all

    @total_time = @calls.inject(0) {|a,b| a + b.duration.to_i }/60
  end

  def user_report_couch
    @title = "Call Detail for #{h request[:username]}"
    view = request[:avoid_locals] ? 'call_detail_avoid_locals' : 'call_detail'

    @calls = Makura::Model.database.view(
      "report/_view/#{view}",
      startkey: [request[:username], Time.strptime(request[:date_start], '%m/%d/%Y').to_i],
      endkey: [request[:username], Time.strptime(request[:date_end], '%m/%d/%Y').to_i]
    )['rows'].map{|row| row['value'] }
  end
end
