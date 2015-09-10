#!/usr/bin/env ruby

require 'docker'
require 'json'
require 'yaml'
require 'tempfile'
require 'terminal-notifier'
require 'ffi-rzmq'

class DockIn
  def run
    context = ZMQ::Context.new(1)
    trap("INT") { puts "Shutting down"; context.terminate; exit }

    default_config = {
      'tld' => '.localhost.tv',
      'drush alias' => '~/.drush/dock.aliases.drushrc.php',
      'apache vhost' => '/etc/apache2/other/dock.conf',
      'docker machine' => 'default',
      'apache reload' => 'sudo apachectl graceful',
      'read timeout' => 3600
    }

    begin
      @config = default_config.merge!(YAML.load_file(File.expand_path('~/.dock-in.yml')))
    rescue Errno::ENOENT
      @config = default_config
    end

    %x(docker-machine env #{@config['docker machine']}).split("\n").each { |line|
      if line[0] != '#'
        key, value = line.gsub(/^export /, '').split('=')
        ENV[key] = value.gsub(/^"/, '').gsub(/"$/, '')
      end
    }

    # Action on a stream of events as they come in
    fix

    Docker.options[:read_timeout] = @config['read timeout']
    Docker::Event.stream { |event|
      if %w(start stop).include?(event.status)
        fix
      end
    }
  end

  def atomic_write(path, temp_path, content)
    File.open(temp_path, 'w+') do |f|
      f.write(content)
    end

    FileUtils.mv(temp_path, path)
  end

  def vhost(tld, name, host, port); <<-EOS.undent
    <VirtualHost *:80>
        ServerName #{name}#{tld}
        ServerAlias *.#{name}#{tld}

        ProxyPreserveHost On
        ProxyPass / http://#{host}:#{port}/
    </VirtualHost>
    EOS
  end

  def drushalias(tld, name, docroot, driver, user, password, host, port, database); <<-EOS.undent
    $aliases['#{name}'] = array(
      'uri' => '#{name}#{tld}',
      'root' => '#{docroot}',
      'db-url' => '#{driver}://#{user}:#{password}@#{host}:#{port}/#{database}',
    );
    EOS
  end

  def fix
    host = %x(docker-machine ip #{@config['docker machine']}).strip
    @vhosts = ["# This is a generated file.\n"]
    @aliases = ["<?php // This is a generated file.\n"]
    @names = []
    Docker::Container.all(all: true, filters: { status: ['running'] }.to_json).each { |container|
      # puts JSON.pretty_generate(container.json)
      name = container.json['Name'].gsub(%r{^/}, '')
      @names.push(name)
      wwwport = container.json['NetworkSettings']['Ports']['80/tcp'].first['HostPort']
      dbport = container.json['NetworkSettings']['Ports']['3306/tcp'].first['HostPort']
      docroot = container.json['Volumes']['/www']
      drush = JSON.parse(%x(drush status --root=#{docroot} --show-passwords --pipe))
      @vhosts.push(vhost(@config['tld'], name, host, wwwport))
      if drush['db-driver']
        @aliases.push(drushalias(@config['tld'], name, docroot, drush['db-driver'], drush['db-username'], drush['db-password'], host, dbport, drush['db-name']))
      end
    }

    atomic_write(File.expand_path(@config['drush alias']), Tempfile.new('uu').path, @aliases.join("\n"))
    atomic_write(File.expand_path(@config['apache vhost']), Tempfile.new('uu').path, @vhosts.join("\n"))
    TerminalNotifier.notify('Containers: ' + @names.join(', '), :title => 'Dock In', :sender => 'com.kitematic.kitematic')
    %x(#{@config['apache reload']})
  end

end


class String
  def undent
    gsub(/^.{#{slice(/^ +/).length}}/, '')
  end
end
