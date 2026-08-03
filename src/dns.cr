require "socket"

require "socket"

module Yozgat
  module DNS
    def self.resolve_ipv4(domain : String) : Array(String)
      name = domain.strip.rchop(".")
      raise "domain is empty" if name.empty?

      ips = [] of String
      Socket::Addrinfo.resolve(
        name,
        "0",
        family: Socket::Family::INET,
        type: Socket::Type::DGRAM,
      ).each do |addr|
        ips << addr.ip_address.address
      end

      raise "no A records found for this domain" if ips.empty?
      ips
    end

    def self.parse_expected_ipv4(raw : String) : String
      ip = raw.strip
      unless ip.matches?(/^\d{1,3}(\.\d{1,3}){3}$/)
        raise "invalid IPv4 address"
      end
      ip
    end

    def self.verify_a_record(domain : String, expected : String) : Array(String)
      found = resolve_ipv4(domain)
      if found.includes?(expected)
        found
      else
        raise "A record does not point to this server (expected #{expected}, found #{found.join(", ")})"
      end
    end
  end
end
