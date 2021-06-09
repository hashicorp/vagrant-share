require "vagrant"

module VagrantPlugins
  module Share
    module Errors
      # A convenient superclass for all our errors.
      class ShareError < Vagrant::Errors::VagrantError
        error_namespace("vagrant_share.errors")
      end

      class APIError < ShareError
        error_key(:api_error)
      end

      class AuthExpired < ShareError
        error_key(:auth_expired)
      end

      class AuthRequired < ShareError
        error_key(:auth_required)
      end

      class ConnectNameIsURL < ShareError
        error_key(:connect_name_is_url)
      end

      class DetectHTTPCommonPortFailed < ShareError
        error_key(:detect_http_common_port_failed)
      end

      class DetectHTTPForwardedPortFailed < ShareError
        error_key(:detect_http_forwarded_port_failed)
      end

      class IPCouldNotAutoAcquire < ShareError
        error_key(:ip_could_not_auto_acquire)
      end

      class IPInUse < ShareError
        error_key(:ip_in_use)
      end

      class IPInvalid < ShareError
        error_key(:ip_invalid)
      end

      class PortCouldNotAcquire < ShareError
        error_key(:port_could_not_acquire)
      end

      class MachineNotReady < ShareError
        error_key(:machine_not_ready)
      end

      class NgrokUnavailable < ShareError
        error_key(:ngrok_unavailable)
      end

      class ProxyExit < ShareError
        error_key(:proxy_exit)
      end

      class ProxyMachineBadProvider < ShareError
        error_key(:proxy_machine_bad_provider)
      end

      class ServerNotSet < ShareError
        error_key(:server_not_set)
      end

      class ShareNotFound < ShareError
        error_key(:share_not_found)
      end

      class SSHCantInsertKey < ShareError
        error_key(:ssh_cant_insert_key)
      end

      class SSHNotReady < ShareError
        error_key(:ssh_not_ready)
      end

      class SSHNotShared < ShareError
        error_key(:ssh_not_shared)
      end

      class SSHPortNotDetected < ShareError
        error_key(:ssh_port_not_detected)
      end

      class SSHHostPortNotDetected < ShareError
        error_key(:ssh_host_port_not_detected)
      end
    end
  end
end
