module VagrantPlugins
  module Share
    module Cap
      class TinyCore

        DEFAULT_SHARE_PASSWORD="VAGRANT_SHARE_DEFAULT_PASSWORD".freeze

        def self.share_proxy(machine, options={})
          proxy_port = options.fetch(:proxy, 31338)
          proxied_ports = options.fetch(:forwards, [])
          shared_password = options[:shared_password] || DEFAULT_SHARE_PASSWORD

          machine.communicate.tap do |comm|
            comm.sudo("sysctl -w net.ipv4.ip_forward=1")
            comm.sudo("/usr/local/sbin/iptables -t filter -I INPUT -p tcp -i eth0 --dport #{proxy_port} -j ACCEPT")
            comm.sudo("/usr/local/sbin/iptables -t nat -A OUTPUT -d `route | grep default | awk '{print $2}'`/32 -j RETURN")
            proxied_ports.each do |port_number|
              comm.sudo("/usr/local/sbin/iptables -t nat -A OUTPUT -p tcp --dport #{port_number} -j DNAT --to-destination `route | grep default | awk '{print $2}'`:#{port_number}")
            end
            if options[:target]
              comm.sudo("/usr/local/sbin/iptables -t nat -A OUTPUT -p tcp -j DNAT --to-destination #{options[:target]}")
            end
            comm.sudo("start-stop-daemon -b --start --exec /usr/local/bin/ss-server " \
              "-- -password #{shared_password} -s :#{proxy_port}")
          end
          proxy_port
        end

        def self.connect_proxy(machine, vm_ip, proxy_port, **opts)
          if opts[:type].to_s == "standalone"
            redsocks_conf = REDSOCKS_CONF.
              gsub("%PROXY_IP%", "127.0.0.1").
              gsub("%PROXY_PORT%", "31339")
          else
            ip_parts    = vm_ip.split(".")
            ip_parts[3] = "1"
            host_ip     = ip_parts.join(".")

            redsocks_conf = REDSOCKS_CONF.
              gsub("%PROXY_IP%", host_ip).
              gsub("%PROXY_PORT%", proxy_port.to_s)
          end
          shared_password = opts[:shared_password] || DEFAULT_SHARE_PASSWORD

          machine.communicate.tap do |comm|
            comm.sudo("sysctl -w net.ipv4.ip_forward=1")
            comm.sudo("/usr/local/sbin/iptables -t nat -A PREROUTING -i eth1 -p tcp -j REDIRECT --to-ports 31338")
            comm.sudo("/usr/local/sbin/iptables -A INPUT -i eth1 -j ACCEPT")

            comm.sudo("rm -f ~/redsocks.conf")
            redsocks_conf.split("\n").each do |line|
              comm.sudo("echo '#{line}' >> ~/redsocks.conf")
            end

            if opts[:type].to_s == "standalone"
              comm.sudo("start-stop-daemon -b --start --exec /usr/local/bin/ss-client " \
                "-- -socks :31339 -password #{shared_password} -c #{vm_ip}:#{proxy_port}")
            end

            comm.sudo(
              "start-stop-daemon -b --start --exec /usr/local/bin/redsocks " \
                "-- -c ~/redsocks.conf")
          end
        end

        # This is the configuration for redsocks that we use to proxy
        REDSOCKS_CONF = <<EOF
base {
        log_debug = on;
        log_info = on;
        log = "file:/root/redsocks.log";
        daemon = off;
        redirector = iptables;
}

redsocks {
        local_ip = 0.0.0.0;
        local_port = 31338;
        ip = %PROXY_IP%;
        port = %PROXY_PORT%;
        type = socks5;
}
EOF


      end
    end
  end
end
