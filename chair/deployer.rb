#!/usr/bin/env ruby

require 'net/ssh'
require 'highline'
require 'yaml'
require 'ostruct'

module Chair

  class Deployer
    attr_accessor :config, :session

    def initialize( config_yaml )
      yaml_loaded = YAML::load_file( config_yaml )
      self.config = OpenStruct.new( yaml_loaded )
      self.session = Chair::Session.new( config.host, config.user )
    end
  end

  class RemoteFileUtils

    def self.copy( from, to, options = {} )
      flags = options[:flags] || ""

      if options[:sudo]
        options[:session].sudo( "cp #{flags} #{from}  #{to}" )
      else
        options[:session].run( "cp #{flags} #{from}  #{to}" )
      end
    end

    def self.link( target, destination, options )
      con_type = options[:sudo] ? :sudo : :run

      cmd = "ln -sf #{target} #{destination}"
      options[:session].send( con_type, cmd )
    end
  end

  class Session
    attr_accessor :ssh_session, :host, :user, :highline, :ssh_options

    def initialize( host, user, ssh_options = {} )
      self.host = host
      self.user = user
      self.ssh_options = ssh_options
      self.highline = HighLine.new
    end

    def with_session
      if self.ssh_session.nil?
        self.ssh_session = Net::SSH.start( self.host, self.user, self.ssh_options )
      end

      return self.ssh_session
    end

    def close_session
      self.ssh_session.close
      self.ssh_session = nil
    end

    def sudo( command )
      with_session

      command = "sudo sh -c '#{command}'"
      self.highline.say( "\n[COMMAND #{self.host}]: Executing: #{command}" )

      self.ssh_session.open_channel do |channel|
        channel.request_pty

        channel.exec( command ) do |channel, success|

          channel.on_extended_data do |ch, status, data|
            if data =~ /password/i || data =~ /Sorry, try again/
              password = self.highline.ask("[PROMPT #{self.host}]: #{data} ") { |q| q.echo = false }
              ch.send_data( password + "\n" )
            else
              self.highline.say("[ERROR  #{self.host}]: #{data}" )
            end
          end

          channel.on_data do |ch, data|
            if data =~ /password/ || data =~ /Sorry, try again/
              password = self.highline.ask("[PROMPT  #{self.host}]: #{data} ") { |q| q.echo = false }
              ch.send_data( password + "\n" )
            else
              self.highline.say("[STDOUT  #{self.host}]: #{data}" )
            end
          end

          channel.on_close do |ch|
            # self.highline.say( "Channel Closing" )
          end
        end

        channel.wait
      end

      ssh_session.loop( 0.1 ) do
        ssh_session.busy?
      end
    end

    def run( command )
      with_session

      command = "sh -c '#{command}'"
      self.highline.say( "\n[COMMAND #{self.host}]: Executing: #{command}" )

      ssh_session.open_channel do |channel|
        channel.request_pty

        channel.exec( command ) do |channel, success|
          raise StandardError, "Couldn't execute" unless success

          channel.on_extended_data do |ch, status, data|
            if data =~ /password/i || data =~ /Sorry, try again/
              password = self.highline.ask("[PROMPT  #{self.host}]: #{data} ") { |q| q.echo = false }
              ch.send_data( password + "\n" )
            else
              self.highline.say("[ERROR  #{self.host}]: #{data}" )
            end
          end

          channel.on_data do |ch, data|
            if data =~ /password/i || data =~ /Sorry, try again/
              password = self.highline.ask("[PROMPT  #{self.host}]: #{data} ") { |q| q.echo = false }
              ch.send_data( password + "\n" )
            else
              self.highline.say("[STDOUT  #{self.host}]: #{data}" )
            end
          end

          channel.on_close do |ch|
            # self.highline.say( "Channel Closing" )
          end
        end

        channel.wait
      end

      ssh_session.loop( 0.1 ) do
        ssh_session.busy?
      end
    end

    def close
      self.ssh_session.close
    end
  end
end


if __FILE__ == $0
  session = Chair::Session.new( "thecarelesslovers.com", "brettnak" )
  session.sudo( "echo \"ran as sudo\"" )
  session.run(  "echo \"ran as user\"" )
  session.close
end
