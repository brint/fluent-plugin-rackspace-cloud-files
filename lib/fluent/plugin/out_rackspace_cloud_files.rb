module Fluent #:nodoc: all
  require 'fluent/mixin/config_placeholders'

  class RackspaceCloudFilesOutput < Fluent::TimeSlicedOutput
    Fluent::Plugin.register_output('rackspace_cloud_files', self)

    def initialize
      super
      require 'fog'
      require 'zlib'
      require 'time'
      require 'tempfile'
    end

    config_param :path, :string, default: ''
    config_param :time_format, :string, default: nil

    include SetTagKeyMixin
    config_set_default :include_tag_key, false

    include SetTimeKeyMixin
    config_set_default :include_time_key, false

    config_param :rackspace_auth_url, :string,
                 default: 'https://identity.api.rackspacecloud.com/v2.0'
    config_param :rackspace_username, :string
    config_param :rackspace_api_key, :string
    config_param :rackspace_container, :string
    config_param :rackspace_region, :string

    config_param :object_key_format, :string,
                 default: '%{path}%{time_slice}_%{index}.%{file_extension}'
    config_param :store_as, :string, default: 'gzip'
    config_param :auto_create_container, :bool, default: true
    config_param :check_apikey_on_start, :bool, default: true
    config_param :proxy_uri, :string, default: nil
    config_param :ssl_verify, :bool, default: true
    config_param :format_json, :bool, default: false

    # attr_reader :container

    include Fluent::Mixin::ConfigPlaceholders

    def placeholders
      [:percent]
    end

    def configure(conf)
      super

      @ext, @mime_type = storage_method

      @timef = TimeFormatter.new(@time_format, @localtime)

      @path_slicer = time_slicer
    end

    def storage_method
      case @store_as
      when 'gzip' then return ['gz', 'application/x-gzip']
      when 'json' then return ['json', 'application/json']
      else return ['txt', 'text/plain']
      end
    end

    def time_slicer
      if @localtime
        return proc do |path|
          Time.now.strftime(path)
        end
      else
        return proc do |path|
          Time.now.utc.strftime(path)
        end
      end
    end

    def start
      super

      Excon.defaults[:ssl_verify_peer] = @ssl_verify

      @storage = Fog::Storage.new provider: 'Rackspace',
                                  rackspace_auth_url: @rackspace_auth_url,
                                  rackspace_username: @rackspace_username,
                                  rackspace_api_key: @rackspace_api_key,
                                  rackspace_region: @rackspace_region

      check_container
    end

    def format(tag, time, record)
      time_str = @timef.format(time) if @include_time_key || !@format_json

      # copied from each mixin because current TimeSlicedOutput can't support
      # mixins.
      record[@tag_key] = tag if @include_tag_key

      record[@time_key] = time_str if @include_time_key

      if @format_json
        Yajl.dump(record) + "\n"
      else
        "#{time_str}\t#{tag}\t#{Yajl.dump(record)}\n"
      end
    end

    def write(chunk)
      i = 0
      previous_path = nil

      begin
        path = @path_slicer.call(@path)
        values_for_swift_object_key = {
          'path' => path,
          'time_slice' => chunk.key,
          'file_extension' => @ext,
          'index' => i
        }
        swift_path = @object_key_format.gsub(%r(%{[^}]+})) do |expr|
          values_for_swift_object_key[expr[2...expr.size - 1]]
        end
        if (i > 0) && (swift_path == previous_path)
          fail 'duplicated path is generated. use %{index} in '\
          "object_key_format: path = #{swift_path}"
        end
        i += 1
        previous_path = swift_path
      end while check_object_exists(@rackspace_container, swift_path)

      tmp = Tempfile.new('rackspace-cloud-files-')
      begin
        if @store_as == 'gzip'
          w = Zlib::GzipWriter.new(tmp)
          chunk.write_to(w)
          w.close
        else
          chunk.write_to(tmp)
          tmp.close
        end
        File.open(tmp.path) do |file|
          @storage.put_object(@rackspace_container, swift_path, file,
                              content_type: @mime_type)
        end
        log.info 'Put Log to Rackspace Cloud Files. container='\
                  "#{@rackspace_container} object=#{swift_path}"
      ensure
        tmp.close(true) rescue nil
        w.close rescue nil
        w.unlink rescue nil
      end
    end

    private

    def check_container
      @storage.get_container(@rackspace_container)
    rescue Fog::Storage::Rackspace::NotFound
      if @auto_create_container
        log.info 'Creating container #{@rackspace_container} in region '\
                  "#{@rackspace_region}"
        @storage.put_container(@rackspace_container)
      else
        raise 'The specified container does not exist: container = '\
              "#{rackspace_container}"
      end
    end

    def check_object_exists(container, object)
      @storage.head_object(container, object)
      return true
    rescue Fog::Storage::Rackspace::NotFound
      return false
    end
  end
end
