require 'stringio'

module VagrantPlugins
  module Share
    # Contains helper methods that the command uses.
    class Helper
      class Api
        @@logger = Log4r::Logger.new("vagrant::plugins::share_api")

        class Logger
          def initialize(target)
            @target = target
          end

          def <<(string)
            @target.debug(string.chomp)
          end
        end

        def self.start_api(machine)
          require "webrick/https"
          begin
            logger = Logger.new(@@logger)
            $stderr = StringIO.new("")
            api = WEBrick::HTTPServer.new(
              AccessLog: [
                [logger, WEBrick::AccessLog::COMMON_LOG_FORMAT]
              ],
              Logger: WEBrick::Log.new(logger),
              Port: 0,
              SSLCertName: [%w(CN vagrant)],
              SSLEnable: true
            )
          ensure
            $stderr = STDERR
          end
          if block_given?
            yield api
          end
          api
        end

      end
    end
  end
end
