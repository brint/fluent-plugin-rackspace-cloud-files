module Fluent

  require 'fluent/mixin/config_placeholders'

  class RackspaceCloudFilesOutput < TimeSlicedOutput
    Fluent::Plugin.register_output('rackspace_cloud_files', self)

    def initialize
      super
      require 'fog'
      require 'zlib'
      require 'time'
      require 'tempfile'
      require 'open3'
    end

    config_param :path, :string, default: ''
    config_param :time_format, :string, default: nil

    include SetTagKeyMixin
    config_set_default :include_tag_key, false

    include SetTimeKeyMixin
    config_set_default :include_time_key, false

    config_param :rackspace_auth_url, :string, default: 'https://identity.api.rackspacecloud.com/v2.0'
    config_param :rackspace_username, :string
    config_param :rackspace_api_key, :string
    config_param :rackspace_container, :string
    config_param :rackspace_region, :string

    config_param :object_key_format, :string, default: "%{path}%{time_slice}_%{index}.%{file_extension}"
    config_param :store_as, :string, default: 'gzip'
    config_param :auto_create_container, :bool, default: true
    config_param :check_apikey_on_start, :bool, default: true
    config_param :proxy_uri, :string, default: nil
    config_param :ssl_verify, :bool, default: true

    # attr_reader :container

    include Fluent::Mixin::ConfigPlaceholders

    def placeholders
      [:percent]
    end

    def configure(conf)
      super

      if format_json = conf['format_json']
        @format_json = true
      else
        @format_json = false
      end

      @ext, @mime_type = case @store_as
        when 'gzip' then ['gz', 'application/x-gzip']
        when 'json' then ['json', 'application/json']
        else ['txt', 'text/plain']
      end

      @timef = TimeFormatter.new(@time_format, @localtime)

      if @localtime
        @path_slicer = Proc.new {|path|
          Time.now.strftime(path)
        }
      else
        @path_slicer = Proc.new {|path|
          Time.now.utc.strftime(path)
        }
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
      if @include_time_key || !@format_json
        time_str = @timef.format(time)
      end

      # copied from each mixin because current TimeSlicedOutput can't support mixins.
      if @include_tag_key
        record[@tag_key] = tag
      end
      if @include_time_key
        record[@time_key] = time_str
      end

      if @format_json
        Yajl.dump(record) + "\n"
      else
        "#{time_str}\t#{tag}\t#{Yajl.dump(record)}\n"
      end
    end

    def write(chunk)
      i = 0

      begin
        path = @path_slicer.call(@path)
        values_for_swift_object_key = {
          'path' => path,
          'time_slice' => chunk.key,
          'file_extension' => @ext,
          'index' => i
        }
        swift_path = @object_key_format.gsub(%r(%{[^}]+})) { |expr|
          values_for_swift_object_key[expr[2...expr.size-1]]
        }
        i += 1
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
          @storage.put_object(@rackspace_container, swift_path, file, {content_type: @mime_type})
        end
        $log.info "Put Log to Rackspace Cloud Files. container=#{@rackspace_container} object=#{swift_path}"
      ensure
        tmp.close(true) rescue nil
        w.close rescue nil
        w.unlink rescue nil
      end
    end

    private

    def check_container
      begin
        @storage.get_container(@rackspace_container)
      rescue Fog::Storage::Rackspace::NotFound
        if @auto_create_container
          $log.info "Creating container #{@rackspace_container} in region #{@rackspace_region}"
          @storage.put_container(@rackspace_container)
        else
          raise "The specified container does not exist: container = #{rackspace_container}"
        end
      end
    end

    def check_object_exists(container, object)
      begin
        @storage.head_object(container, object)
      rescue Fog::Storage::Rackspace::NotFound
        return false
      end
      return true
    end

  end
end
