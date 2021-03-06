module TinyCdr
  class Log
    include Makura::Model

    properties :channel_data, :variables, :app_log, :callflow

    def self.sync(name)
      root = File.expand_path("../../couch/#{name}", __FILE__)
      glob = File.join(root, "**/*.js")

      begin
        layout = self["_design/#{name}"] || {}
      rescue Makura::Error::ResourceNotFound
        layout = {}
      end

      layout['language'] ||= 'javascript'
      layout['_id'] ||= "_design/#{name}"

      Dir.glob(glob) do |file|
        keys = File.dirname(file).sub(root, '').scan(/[^\/]+/)
        doc = File.read(file)
        last = nil
        keys.inject(layout){|k,v| last = k[v] ||= {} }
        last[File.basename(file, '.js')] = doc
      end

      database.save(layout)
    end

    sync :log

    def self.find_or_create_from_xml(uuid, xml)
      parser = LogParser.new
      Nokogiri::XML::SAX::Parser.new(parser).parse(xml)
      instance = Log.new(parser.out['cdr'])
      instance['_id'] = uuid

      instance.save # may conflict
      return instance
    rescue Makura::Error::Conflict => e
      warn e
      return self[instance['_id']]
    end
  end

  class LogParser < Nokogiri::XML::SAX::Document
    attr_reader :out

    def start_document
      @keys = []
      @out = {}
    end

    def start_element(name, attrs = [])
      @keys << name
      @attrs = (Hash[*attrs] rescue Hash[attrs])
      @buffer = []
    rescue ArgumentError => e
      Ramaze::Log.error e
      Ramaze::Log.error attrs
    end

    def characters(string)
      @buffer << string
    end

    INTEGER = %w[
    sip_received_port sip_contact_port sip_via_port sip_via_rport max_forwards
    write_rate local_media_port sip_term_status read_rate
  ]

    def end_element(name)
      content = @buffer.join.strip
      content =
        case name
        when /(time|sec|epoch|duration)$/, *INTEGER
          begin
            Integer(content)
          rescue ArgumentError
            Time.strptime(CGI.unescape(content), '%A, %B %d %Y, %I %M %p').to_i
          rescue ArgumentError
            CGI.unescape(content)
          end
        else
          case content
          when 'true'
            true
          when 'false'
            false
          when ''
            nil
          else
            CGI.unescape(content)
          end
        end

      if @keys == %w[cdr app_log application] ||
        @keys == %w[cdr callflow extension application]

        @keys.inject(@out){|s,v|
        if v == 'application'
          (s[v] ||= []) << {@attrs['app_name'] => @attrs['app_data']}
        else
          s[v] ||= {}
        end
      }
      else
        @keys.inject(@out){|s,v|
          if content && v == @keys.last && @buffer.any?
            s[v] = content
          elsif v == @keys.last
            s[v] ||= nil
          else
            s[v] ||= {}
          end
        }
      end

      @keys.pop
      @buffer.clear
    end
  end
end
