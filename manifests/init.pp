# == Class: dns
#
# Using custom types untill next stdlib release
class dns (
  Pattern[/^(nsd|knot)$/]                 $daemon = $::dns::params::daemon,
  Dns::Absolute_path               $slaves_target = $::dns::params::slaves_target,
  Dns::Absolute_path                $tsigs_target = $::dns::params::tsigs_target,
  String                                    $nsid = $::dns::params::nsid,
  String                                $identity = $::dns::params::identity,
  Array[Dns::Ip_address]            $ip_addresses = $::dns::params::ip_addresses,
  Boolean                                 $master = false,
  String                                $instance = 'default',
  Pattern[/^(present|absent)$/]           $ensure = 'present',
  Boolean                       $enable_zonecheck = true,
  Hash                                     $zones = {},
  Hash                                     $files = {},
  Hash                                      $tsig = {},
  Boolean                          $enable_nagios = false,
) inherits dns::params {

  $slaves_template = 'dns/etc/puppetlabs/facter/facts.d/dns_slave_addresses.yaml.erb'
  $tsigs_template  = 'dns/etc/puppetlabs/facter/facts.d/dns_slave_tsigs.yaml.erb'
  if $enable_zonecheck {
    if $::kernel != 'FreeBSD' {
      include ::python
    }
    package {'zonecheck':
      ensure   => '1.0.10',
      provider => 'pip',
    }
    file {'/usr/local/etc/zone_check.conf':
      ensure  => $ensure,
      content => template('dns/usr/local/etc/zone_check.conf.erb'),
    }
    cron {'/usr/local/bin/zonecheck':
      ensure  => $ensure,
      command => '/usr/bin/flock -n /var/lock/zonecheck.lock /usr/local/bin/zonecheck --puppet-facts',
      minute  => '*/15',
    }
  }
  if $daemon == 'nsd' {
    $nsd_enable  =  true
    $knot_enable =  false
    file {'/usr/local/bin/dns-control':
      ensure => link,
      target => '/usr/sbin/nsd-control',
    }
  } else {
    $nsd_enable  =  false
    $knot_enable =  true
    file {'/usr/local/bin/dns-control':
      ensure => link,
      target => '/usr/sbin/knotc',
    }
  }
  if $master {
    #these come from the custom facts dir
    $slave_tsigs     = $::dns_slave_tsigs
    $slave_addresses = $::dns_slave_addresses
    concat{$tsigs_target:}
    concat::fragment{
      "dns_slave_tsigs_yaml_${::fqdn}":
        target  => $tsigs_target,
        content => "dns_slave_tsigs:\n",
        order   => '01',
    }
    Concat::Fragment <<| tag == "dns::${instance}_slave_tsigs" |>>
    concat{$slaves_target:}
    concat::fragment{
      "dns_slave_addresses_yaml_${::fqdn}":
        target  => $slaves_target,
        content => "dns_slave_addresses:\n",
        order   => '01',
    }
    Concat::Fragment <<| tag == "dns::${instance}_slave_interface_yaml" |>>
  } else {
    $slave_tsigs     = {}
    $slave_addresses = {}
    @@concat::fragment{ "dns_slave_tsig_yaml_${::fqdn}":
      target  => $tsigs_target,
      tag     => "dns::${instance}_slave_tsigs",
      content => template($tsigs_template),
      order   => '10',
    }
    @@concat::fragment{ "dns_slave_addresses_yaml_${::fqdn}":
      target  => $slaves_target,
      tag     => "dns::${instance}_slave_interface_yaml",
      content => template($slaves_template),
      order   => '10',
    }
  }
  #We add 0 to cast string to int
  if $::processorcount + 0  > 3 {
    $server_count = $::processorcount - 3
  } else {
    $server_count = 1
  }

  if $ensure == 'present' {
    class { '::nsd':
      enable          => $nsd_enable,
      ip_addresses    => $ip_addresses,
      tsigs           => $slave_tsigs,
      slave_addresses => $slave_addresses,
      zones           => $zones,
      tsig            => $tsig,
      server_count    => $server_count,
      files           => $files,
      nsid            => $nsid,
      identity        => $identity,
    }
    class { '::knot':
      enable          => $knot_enable,
      ip_addresses    => $ip_addresses,
      tsigs           => $slave_tsigs,
      slave_addresses => $slave_addresses,
      zones           => $zones,
      tsig            => $tsig,
      server_count    => $server_count,
      files           => $files,
      nsid            => $nsid,
      identity        => $identity,
    }
  }
  if $enable_nagios {
    $_ip_addresses_list = join($ip_addresses, ' ')

    $zones.each |String $zoneset, Hash $_config| {
      $_config['zones'].each |String $zone| {
        if has_key($_config, 'masters') {
          $_masters = delete($_config['masters'], ['127.0.0.1','0::1'])
          if ! empty($_masters) {
            $master_check_args = join($_masters, ' ')
            @@nagios_service{ "${::fqdn}_DNS_ZONE_MASTERS_${zone}":
              ensure              => present,
              use                 => 'generic-service',
              host_name           => $::fqdn,
              service_description => "DNS_ZONE_MASTERS_${zone}",
              check_command       => "check_nrpe_args!check_dns!${zone}!${master_check_args}!${_ip_addresses_list}",
            }
          }
        }
      }
    }
  }
}
